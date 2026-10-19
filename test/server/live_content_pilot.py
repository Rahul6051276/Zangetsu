"""Synthetic production bridge smoke test; never touches an existing user."""

import os
import sys
import time
import uuid

import psycopg2

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../server/sync"))
from history_bridge import load_source_dsn, source_connection_kwargs


def row(connection, schema, table, owner):
    with connection.cursor() as cursor:
        cursor.execute(
            f"select to_jsonb(item) from {schema}.{table} item "
            "where user_key = %s limit 1", (owner,),
        )
        result = cursor.fetchone()
    return result[0] if result else None


def wait_for(connection, schema, table, owner, predicate):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if predicate(row(connection, schema, table, owner)):
            return
        time.sleep(0.25)
    raise AssertionError(f"bridge did not update {table} on {schema}")


def main():
    owner = f"content-pilot-{uuid.uuid4()}"
    source = psycopg2.connect(
        **source_connection_kwargs(load_source_dsn(os.environ["SUPABASE_DSN_FILE"])),
        sslmode="require", connect_timeout=10,
    )
    stage = psycopg2.connect(os.environ["VPS_DSN"], connect_timeout=10)
    try:
        with source:
            with source.cursor() as cursor:
                cursor.execute(
                    "insert into public.reading_history "
                    "(user_key, source_id, show_id, title) "
                    "values (%s, 'pilot', 'show', 'old')", (owner,),
                )
        wait_for(stage, "sync_api", "reading_history", owner,
                 lambda item: item is not None and item["title"] == "old")

        with stage:
            with stage.cursor() as cursor:
                cursor.execute(
                    "update sync_api.reading_history set title = 'new' "
                    "where user_key = %s", (owner,),
                )
        wait_for(source, "public", "reading_history", owner,
                 lambda item: item is not None and item["title"] == "new")

        with source:
            with source.cursor() as cursor:
                cursor.execute(
                    "delete from public.reading_history where user_key = %s",
                    (owner,),
                )
        wait_for(stage, "sync_api", "reading_history", owner,
                 lambda item: item is None)

        with stage:
            with stage.cursor() as cursor:
                cursor.execute(
                    "insert into sync_api.viewer_profiles "
                    "(user_key, profile_id, name) "
                    "values (%s, 'viewer', 'Pilot')", (owner,),
                )
        wait_for(source, "public", "viewer_profiles", owner,
                 lambda item: item is not None)

        with stage:
            with stage.cursor() as cursor:
                cursor.execute(
                    "insert into sync_api.profile_reading_history "
                    "(user_key, profile_id, source_id, show_id, title) "
                    "values (%s, 'viewer', 'pilot', 'show', 'Scoped')", (owner,),
                )
                cursor.execute(
                    "insert into sync_api.profile_history "
                    "(user_key, profile_id, source_id, show_id) "
                    "values (%s, 'viewer', 'pilot', 'show')", (owner,),
                )
                cursor.execute(
                    "insert into sync_api.profile_mylist "
                    "(user_key, profile_id, source_id, item_id) "
                    "values (%s, 'viewer', 'pilot', 'item')", (owner,),
                )
                cursor.execute(
                    "insert into sync_api.profile_list_categories "
                    "(user_key, profile_id, name) "
                    "values (%s, 'viewer', 'Saved') returning id", (owner,),
                )
                category_id = cursor.fetchone()[0]
                cursor.execute(
                    "insert into sync_api.profile_mylist_categories "
                    "(user_key, profile_id, source_id, item_id, category_id) "
                    "values (%s, 'viewer', 'pilot', 'item', %s)",
                    (owner, category_id),
                )
        wait_for(source, "public", "profile_reading_history", owner,
                 lambda item: item is not None)
        for table in ("profile_history", "profile_mylist",
                      "profile_list_categories", "profile_mylist_categories"):
            wait_for(source, "public", table, owner,
                     lambda item: item is not None)

        with stage:
            with stage.cursor() as cursor:
                cursor.execute(
                    "delete from sync_api.viewer_profiles where user_key = %s",
                    (owner,),
                )
        for connection, schema in ((source, "public"), (stage, "sync_api")):
            wait_for(connection, schema, "viewer_profiles", owner,
                     lambda item: item is None)
            for table in ("profile_reading_history", "profile_history",
                          "profile_mylist", "profile_list_categories",
                          "profile_mylist_categories"):
                wait_for(connection, schema, table, owner,
                         lambda item: item is None)
        print("pilot-pass: content bridge and all profile child cascades")
    finally:
        source.rollback()
        stage.rollback()
        for connection, schema in ((source, "public"), (stage, "sync_api")):
            with connection:
                with connection.cursor() as cursor:
                    for table in ("reading_history", "profile_reading_history",
                                  "viewer_profiles"):
                        cursor.execute(
                            f"delete from {schema}.{table} where user_key = %s",
                            (owner,),
                        )
        source.close()
        stage.close()


if __name__ == "__main__":
    main()
