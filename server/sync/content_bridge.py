"""Temporary reading-history/viewer-profile/backup bridge for old and new
app versions. Reuses the library bridge's journal replay engine with a
second, independent journal."""

import os
import sys
import time

from history_bridge import load_source_dsn, source_connection_kwargs
from library_bridge import (
    LibraryBridge,
    PostgresLibraryDatabase,
    PostgresLibraryState,
)

JOURNAL = "content_bridge"
ADVISORY_LOCK_ID = 238903481230917

TABLE_KEYS = {
    "reading_history": ("user_key", "source_id", "show_id"),
    "profile_reading_history": (
        "user_key", "profile_id", "source_id", "show_id"
    ),
    "viewer_profiles": ("user_key", "profile_id"),
    "backups": ("user_key",),
}
TABLE_FIELDS = {
    "reading_history": (
        "user_key", "source_id", "show_id", "title", "cover", "chapter_id",
        "chapter_number", "chapter_url", "pos", "total", "updated_ms", "type",
    ),
    "profile_reading_history": (
        "user_key", "profile_id", "source_id", "show_id", "title", "cover",
        "chapter_id", "chapter_number", "chapter_url", "pos", "total",
        "updated_ms", "type",
    ),
    "viewer_profiles": (
        "user_key", "profile_id", "name", "avatar", "is_kids", "created_at",
        "photo_url",
    ),
    "backups": ("user_key", "payload", "updated_at"),
}


def main():
    import psycopg2

    source = psycopg2.connect(
        **source_connection_kwargs(load_source_dsn(os.environ["SUPABASE_DSN_FILE"])),
        sslmode="require", connect_timeout=10,
    )
    try:
        vps = psycopg2.connect(os.environ["VPS_DSN"], connect_timeout=10)
        try:
            with vps.cursor() as cursor:
                cursor.execute("select pg_try_advisory_lock(%s)", (ADVISORY_LOCK_ID,))
                if not cursor.fetchone()[0]:
                    return
            bridge = LibraryBridge(
                PostgresLibraryDatabase(
                    source, "supabase", JOURNAL, TABLE_KEYS, TABLE_FIELDS,
                ),
                PostgresLibraryDatabase(
                    vps, "vps", JOURNAL, TABLE_KEYS, TABLE_FIELDS,
                ),
                PostgresLibraryState(vps, JOURNAL),
            )
            processed = 0
            while True:
                if bridge.process_once():
                    processed += 1
                    if processed >= 1000:
                        bridge.source.prune_processed(bridge.state.cursor("supabase"))
                        bridge.vps.prune_processed(bridge.state.cursor("vps"))
                        processed = 0
                else:
                    time.sleep(2)
        finally:
            vps.close()
    finally:
        source.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"content bridge stopped: {type(error).__name__} "
              f"{getattr(error, 'pgcode', '') or ''}", file=sys.stderr)
        raise SystemExit(1)
