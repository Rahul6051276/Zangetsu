import pathlib
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, str(
    pathlib.Path(__file__).resolve().parents[2] / "server" / "sync"
))
from content_bridge import JOURNAL, TABLE_FIELDS, TABLE_KEYS
from library_bridge import LibraryBridge, LibraryEvent


class ContentEventTest(unittest.TestCase):
    def test_key_is_stable_regardless_of_json_property_order(self):
        now = datetime.now(timezone.utc)
        first = LibraryEvent(
            "supabase", 1, "reading_history", "user", "",
            {"source_id": "source", "show_id": "show"},
            "upsert", {}, now,
        )
        second = LibraryEvent(
            "vps", 2, "reading_history", "user", "",
            {"show_id": "show", "source_id": "source"},
            "delete", None, now,
        )
        self.assertEqual(first.key, second.key)

    def test_only_the_four_content_tables_are_replayed(self):
        self.assertEqual(set(TABLE_FIELDS), {
            "reading_history", "profile_reading_history",
            "viewer_profiles", "backups",
        })
        self.assertEqual(JOURNAL, "content_bridge")

    def test_backup_key_is_the_account_alone(self):
        now = datetime.now(timezone.utc)
        first = LibraryEvent("supabase", 1, "backups", "user", "",
                             {}, "upsert", {}, now)
        second = LibraryEvent("vps", 2, "backups", "user", "",
                              {}, "delete", None, now)
        self.assertEqual(first.key, second.key)
        self.assertEqual(TABLE_KEYS["backups"], ("user_key",))

    def test_viewer_profile_key_uses_the_profile_id(self):
        now = datetime.now(timezone.utc)
        self.assertEqual(
            LibraryEvent("vps", 1, "viewer_profiles", "user", "",
                         {"profile_id": "viewer"}, "upsert", {}, now).key,
            LibraryEvent("supabase", 2, "viewer_profiles", "user", "",
                         {"profile_id": "viewer"}, "delete", None, now).key,
        )

    def test_new_source_event_is_applied_to_both_sides(self):
        event = LibraryEvent(
            "supabase", 1, "reading_history", "user", "",
            {"source_id": "source", "show_id": "show"},
            "upsert", {}, datetime.now(timezone.utc),
        )
        source = _Endpoint(event)
        vps = _Endpoint(None)
        state = _State()
        self.assertTrue(LibraryBridge(source, vps, state).process_once())
        self.assertEqual(source.applied, [event])
        self.assertEqual(vps.applied, [event])

    def test_stale_event_is_overwritten_by_the_winner_on_both_sides(self):
        now = datetime.now(timezone.utc)
        key = {"profile_id": "viewer"}
        stale = LibraryEvent("supabase", 2, "viewer_profiles", "user", "",
                             key, "upsert", {}, now)
        winner = LibraryEvent("vps", 1, "viewer_profiles", "user", "",
                              key, "delete", None, now.replace(year=now.year + 1))
        source = _Endpoint(stale)
        vps = _Endpoint(None)
        state = _State(previous=winner)
        self.assertTrue(LibraryBridge(source, vps, state).process_once())
        self.assertEqual(source.applied, [winner])
        self.assertEqual(vps.applied, [winner])

    def test_concurrent_edits_converge_on_the_newer_event(self):
        now = datetime.now(timezone.utc)
        key = {"source_id": "source", "show_id": "show"}
        older = LibraryEvent("supabase", 1, "reading_history", "user", "",
                             key, "upsert", {"pos": 1}, now)
        newer = LibraryEvent("vps", 2, "reading_history", "user", "",
                             key, "delete", None, now.replace(year=now.year + 1))
        source = _Endpoint(older)
        vps = _Endpoint(newer)
        bridge = LibraryBridge(source, vps, _State())
        self.assertTrue(bridge.process_once())
        self.assertTrue(bridge.process_once())
        self.assertIs(source.applied[-1], newer)
        self.assertIs(vps.applied[-1], newer)


class _Endpoint:
    def __init__(self, event):
        self.event = event
        self.applied = []

    def next_event(self, after):
        if self.event is not None and self.event.id > after:
            return self.event
        return None

    def apply(self, event):
        self.applied.append(event)


class _State:
    def __init__(self, previous=None):
        self.previous = previous
        self.cursors = {}

    def cursor(self, origin):
        return self.cursors.get(origin, 0)

    def latest(self, _):
        return self.previous

    def commit(self, processed, winner):
        self.previous = winner
        self.cursors[processed.origin] = processed.id


if __name__ == "__main__":
    unittest.main()
