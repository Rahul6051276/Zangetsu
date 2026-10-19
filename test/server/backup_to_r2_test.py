import pathlib
import sys
import tempfile
import unittest
import json
from urllib.parse import urlparse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "server" / "sync"))


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None

    def read(self, size=-1):
        if size < 0:
            body, self.body = self.body, b""
            return body
        body, self.body = self.body[:size], self.body[size:]
        return body


class BackupToR2Test(unittest.TestCase):
    def test_upload_is_downloaded_and_verified_before_success(self):
        from backup_to_r2 import backup

        objects = {}
        restores = []

        def run(command, **_):
            if command[0] == "pg_dump":
                pathlib.Path(command[command.index("--file") + 1]).write_bytes(b"db")
            elif command[0] == "pg_restore":
                restores.append(command)
            else:
                self.fail(f"unexpected command: {command[0]}")

        def open_url(request, **_):
            name = pathlib.PurePosixPath(urlparse(request.full_url).path).name
            key = f"daily/{name}"
            if request.method == "PUT":
                objects[key] = request.data
                return FakeResponse(json.dumps({"key": key, "size": len(request.data)}).encode())
            return FakeResponse(objects[key])

        with tempfile.TemporaryDirectory() as directory:
            token = pathlib.Path(directory) / "token"
            token.write_text("test-token")
            backup(directory, run=run, open_url=open_url,
                   endpoint="https://backup.test/v1/backup", token_file=token)
            self.assertEqual(len(list(pathlib.Path(directory).iterdir())), 1)

        self.assertEqual(len(objects), 1)
        self.assertEqual(next(iter(objects.values())), b"db")
        self.assertEqual(len(restores), 2)

    def test_corrupt_download_fails(self):
        from backup_to_r2 import backup

        objects = {}

        def run(command, **_):
            if command[0] == "pg_dump":
                pathlib.Path(command[command.index("--file") + 1]).write_bytes(b"db")

        def open_url(request, **_):
            name = pathlib.PurePosixPath(urlparse(request.full_url).path).name
            key = f"daily/{name}"
            if request.method == "PUT":
                objects[key] = b"corrupt"
                return FakeResponse(json.dumps({"key": key, "size": len(request.data)}).encode())
            return FakeResponse(objects[key])

        with tempfile.TemporaryDirectory() as directory:
            token = pathlib.Path(directory) / "token"
            token.write_text("test-token")
            with self.assertRaises(ValueError):
                backup(directory, run=run, open_url=open_url,
                       endpoint="https://backup.test/v1/backup", token_file=token)
            self.assertEqual(len(list(pathlib.Path(directory).iterdir())), 1)
