import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "server" / "sync"))
from history_bridge import HistoryBridge, HistoryEvent


START = datetime(2026, 10, 19, tzinfo=timezone.utc)


class FakeDatabase:
    def __init__(self, origin):
        self.origin = origin
        self.events = []
        self.rows = {}
        self.fail_apply = False

    def next_event(self, after_id):
        return next((event for event in self.events if event.id > after_id), None)

    def apply(self, event):
        if self.fail_apply:
            raise OSError("database unavailable")
        if event.operation == "delete":
            self.rows.pop(event.key, None)
        else:
            self.rows[event.key] = event.row_data


class FakeCoordinator:
    def __init__(self):
        self.cursors = {"supabase": 0, "vps": 0}
        self.winners = {}

    def cursor(self, origin):
        return self.cursors[origin]

    def latest(self, key):
        return self.winners.get(key)

    def commit(self, processed, winner):
        self.winners[processed.key] = winner
        self.cursors[processed.origin] = processed.id


def event(origin, event_id, seconds, operation="upsert", title="show"):
    return HistoryEvent(
        origin=origin,
        id=event_id,
        user_key="user",
        profile_id=None,
        source_id="source",
        show_id="show",
        operation=operation,
        row_data=None if operation == "delete" else {"show_title": title},
        changed_at=START + timedelta(seconds=seconds),
    )


class HistoryBridgeTest(unittest.TestCase):
    def setUp(self):
        self.source = FakeDatabase("supabase")
        self.vps = FakeDatabase("vps")
        self.state = FakeCoordinator()
        self.bridge = HistoryBridge(self.source, self.vps, self.state)

    def test_upsert_from_old_app_reaches_both_databases(self):
        self.source.events.append(event("supabase", 1, 1))
        self.assertTrue(self.bridge.process_once())
        self.assertEqual(self.source.rows, self.vps.rows)
        self.assertEqual(self.state.cursor("supabase"), 1)

    def test_newer_vps_edit_wins_and_stale_replay_repairs_both_sides(self):
        newer = event("vps", 1, 2, title="new")
        older = event("supabase", 1, 1, title="old")
        self.vps.events.append(newer)
        self.assertTrue(self.bridge.process_once())
        self.source.events.append(older)
        self.source.rows[older.key] = older.row_data
        self.assertTrue(self.bridge.process_once())
        self.assertEqual(self.source.rows[older.key]["show_title"], "new")
        self.assertEqual(self.vps.rows[older.key]["show_title"], "new")

    def test_delete_reaches_both_and_old_upsert_cannot_resurrect(self):
        delete = event("vps", 1, 3, operation="delete")
        self.vps.events.append(delete)
        self.assertTrue(self.bridge.process_once())
        self.source.events.append(event("supabase", 1, 2))
        self.assertTrue(self.bridge.process_once())
        self.assertEqual(self.source.rows, {})
        self.assertEqual(self.vps.rows, {})

    def test_failed_target_write_does_not_advance_cursor(self):
        self.source.events.append(event("supabase", 1, 1))
        self.vps.fail_apply = True
        with self.assertRaises(OSError):
            self.bridge.process_once()
        self.assertEqual(self.state.cursor("supabase"), 0)
        self.vps.fail_apply = False
        self.assertTrue(self.bridge.process_once())
        self.assertEqual(self.state.cursor("supabase"), 1)


if __name__ == "__main__":
    unittest.main()
