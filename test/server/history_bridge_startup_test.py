import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "server" / "sync"))
from history_bridge import load_source_dsn, source_connection_kwargs


class HistoryBridgeStartupTest(unittest.TestCase):
    def test_rejects_non_postgres_or_missing_host(self):
        with tempfile.TemporaryDirectory() as directory:
            file = pathlib.Path(directory) / "db-url"
            for value in ("https://example.com", "postgresql:///database"):
                file.write_text(value)
                with self.assertRaises(ValueError):
                    load_source_dsn(file)

    def test_reads_a_postgres_url_without_printing_it(self):
        with tempfile.TemporaryDirectory() as directory:
            file = pathlib.Path(directory) / "db-url"
            file.write_text("postgresql://user:secret@db.example.com/postgres\n")
            self.assertEqual(
                load_source_dsn(file),
                "postgresql://user:secret@db.example.com/postgres",
            )

    def test_reads_a_labeled_connection_file(self):
        with tempfile.TemporaryDirectory() as directory:
            file = pathlib.Path(directory) / "db-url"
            file.write_text(
                "Session pooler connection\n"
                "postgresql://user:secret@db.example.com/postgres\n"
            )
            self.assertEqual(
                load_source_dsn(file),
                "postgresql://user:secret@db.example.com/postgres",
            )

    def test_password_at_sign_does_not_become_part_of_host(self):
        values = source_connection_kwargs(
            "postgresql://postgres.user:test%40password@db.example.com:5432/postgres"
        )
        self.assertEqual(values["host"], "db.example.com")
        self.assertEqual(values["user"], "postgres.user")
        self.assertEqual(values["password"], "test@password")
        self.assertEqual(values["dbname"], "postgres")


if __name__ == "__main__":
    unittest.main()
