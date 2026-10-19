"""Run against disposable source-shaped and VPS-shaped databases only."""

import os
import pathlib
import sys
import unittest
import uuid

import psycopg2

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "server" / "sync"))


@unittest.skipUnless(
    os.environ.get("ZANGETSU_CONTENT_SEED_INTEGRATION") == "1",
    "requires disposable content seed databases",
)
class ContentSeedIntegrationTest(unittest.TestCase):
    def test_snapshot_copies_existing_rows_and_records_journal_watermark(self):
        from check_content_parity import compare
        from seed_content_stage import seed

        source = psycopg2.connect(os.environ["CONTENT_SEED_SOURCE_DSN"])
        stage = psycopg2.connect(os.environ["CONTENT_SEED_VPS_DSN"])
        self.addCleanup(source.close)
        self.addCleanup(stage.close)
        owner = f"seed-{uuid.uuid4()}"
        with source:
            with source.cursor() as cursor:
                cursor.execute(
                    "insert into public.viewer_profiles "
                    "(user_key, profile_id, name) values (%s, 'viewer', 'Viewer')",
                    (owner,),
                )
                cursor.execute(
                    "insert into public.profile_reading_history "
                    "(user_key, profile_id, source_id, show_id, title) "
                    "values (%s, 'viewer', 'manga', 'show', 'Existing')",
                    (owner,),
                )
                cursor.execute(
                    "insert into public.backups (user_key, payload) "
                    "values (%s, '{\"saved\":true}')", (owner,),
                )

        with source.cursor() as cursor:
            expected = {}
            for table in ("viewer_profiles", "profile_reading_history", "backups"):
                cursor.execute(f"select count(*) from public.{table}")
                expected[table] = cursor.fetchone()[0]
        source.rollback()

        counts = seed(source, stage)
        for table, count in expected.items():
            self.assertEqual(counts[table], count)
        with stage.cursor() as cursor:
            cursor.execute(
                "select name from sync_api.viewer_profiles where user_key = %s",
                (owner,),
            )
            self.assertEqual(cursor.fetchone()[0], "Viewer")
            cursor.execute(
                "select title from sync_api.profile_reading_history "
                "where user_key = %s", (owner,),
            )
            self.assertEqual(cursor.fetchone()[0], "Existing")
            cursor.execute(
                "select payload from sync_api.backups where user_key = %s",
                (owner,),
            )
            self.assertEqual(cursor.fetchone()[0], '{"saved":true}')
            cursor.execute(
                "select last_id from sync_private.content_bridge_cursors "
                "where origin = 'supabase'"
            )
            self.assertGreater(cursor.fetchone()[0], 0)
            cursor.execute("select count(*) from sync_private.content_bridge_events")
            self.assertEqual(cursor.fetchone()[0], 0)

        with self.assertRaises(ValueError):
            seed(source, stage)

        for table in ("viewer_profiles", "profile_reading_history", "backups"):
            self.assertEqual(compare(source, stage, table)["different"], 0)
        with stage:
            with stage.cursor() as cursor:
                cursor.execute(
                    "update sync_api.viewer_profiles set name = 'Tampered' "
                    "where user_key = %s", (owner,),
                )
        self.assertEqual(compare(source, stage, "viewer_profiles")["different"], 1)


if __name__ == "__main__":
    unittest.main()
