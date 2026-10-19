import pathlib
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "server" / "sync"))
from library_bridge import LibraryBridge, LibraryEvent, TABLE_FIELDS


class LibraryEventTest(unittest.TestCase):
    def test_key_is_stable_regardless_of_json_property_order(self):
        now = datetime.now(timezone.utc)
        first = LibraryEvent(
            "supabase", 1, "mylist", "user", "",
            {"source_id": "source", "item_id": "item"},
            "upsert", {}, now,
        )
        second = LibraryEvent(
            "vps", 2, "mylist", "user", "",
            {"item_id": "item", "source_id": "source"},
            "delete", None, now,
        )
        self.assertEqual(first.key, second.key)

    def test_only_six_user_edited_tables_are_replayed(self):
        self.assertEqual(set(TABLE_FIELDS), {
            "mylist", "profile_mylist", "list_categories",
            "profile_list_categories", "mylist_categories",
            "profile_mylist_categories",
        })
        self.assertNotIn("mylist_sync_clock", TABLE_FIELDS)
        self.assertNotIn("mylist_sync_tombstones", TABLE_FIELDS)

    def test_new_source_event_is_applied_to_both_sides(self):
        event = LibraryEvent(
            "supabase", 1, "mylist", "user", "",
            {"source_id": "source", "item_id": "item"},
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
        key = {"source_id": "source", "item_id": "item"}
        stale = LibraryEvent("supabase", 2, "mylist", "user", "",
                             key, "upsert", {}, now)
        winner = LibraryEvent("vps", 1, "mylist", "user", "",
                              key, "delete", None, now.replace(year=now.year + 1))
        source = _Endpoint(stale)
        vps = _Endpoint(None)
        state = _State(previous=winner)
        self.assertTrue(LibraryBridge(source, vps, state).process_once())
        self.assertEqual(source.applied, [winner])
        self.assertEqual(vps.applied, [winner])

    def test_concurrent_edits_converge_on_the_newer_event(self):
        now = datetime.now(timezone.utc)
        key = {"source_id": "source", "item_id": "item"}
        older = LibraryEvent("supabase", 1, "mylist", "user", "",
                             key, "upsert", {"added_at": 1}, now)
        newer = LibraryEvent("vps", 2, "mylist", "user", "",
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
