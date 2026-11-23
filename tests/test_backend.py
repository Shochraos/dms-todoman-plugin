import hashlib
import json
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import todoman_backend as backend


class BackendTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.config = self.directory / "config.py"
        self.config.write_text("startable = True\n")
        self.rows = []
        self.paths = {}
        self.lists = ["Straße", "Other"]
        self.commands = []
        self.failing_command = None
        for mock in (
            patch.dict(os.environ, TODOMAN_CONFIG=str(self.config)),
            patch.object(backend.shutil, "which", return_value="todo"),
            patch.object(backend.subprocess, "run", side_effect=self.todo),
        ):
            mock.start()
            self.addCleanup(mock.stop)

    def todo(self, argv, **kwargs):
        self.assertEqual(argv[:2], ["todo", "--porcelain"])
        args = argv[2:]
        if args[0] == "--config":
            self.assertFalse(runpy.run_path(args[1])["startable"])
            args = args[2:]
        self.commands.append(tuple(args))
        if args[0] == self.failing_command:
            return subprocess.CompletedProcess(argv, 1, "", "fixture command failed")
        if args == ["lists"]:
            output = json.dumps(self.lists)
        elif args[0] == "list":
            output = json.dumps(self.rows)
        else:
            self.assertEqual(args[0], "path")
            output = f"{self.paths[int(args[1])]}\n"
        return subprocess.CompletedProcess(argv, 0, output, "")

    def task_file(self, task_id, *properties):
        path = self.directory / f"{task_id}.ics"
        path.write_bytes("\r\n".join((
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Tests//EN", "BEGIN:VTODO",
            f"UID:uid-{task_id}", f"SUMMARY:Task {task_id}", *properties,
            "END:VTODO", "END:VCALENDAR", "",
        )).encode())
        return path

    def test_snapshot_prefers_row_path_and_preserves_order_and_metadata(self):
        path = self.task_file(3, "STATUS:CANCELLED", "COMPLETED:20241231T120000Z", "DUE;VALUE=DATE:20250101")
        self.paths = {1: self.task_file(1), 2: self.task_file(2), 3: path, 4: self.task_file(4)}
        self.rows = [
            {"id": 3, "list": "Straße", "list_colour": "#123456", "file_path": os.path.relpath(path)},
            {"id": 5, "list": "Other"},
            {"id": 2, "list": "Straße"},
            {"id": 4, "list": "Straße", "file_path": ""},
            {"id": 1, "list": "Straße", "file_path": 7},
        ]
        result = backend.run({"action": "snapshot", "lists": ["STRASSE"], "sort": "priority", "file_path": "ignored.ics"})
        self.assertEqual(self.commands, [
            ("lists",), ("list", "--status", "ANY", "--sort", "priority"),
            ("path", "2"), ("path", "4"), ("path", "1"),
        ])
        self.assertEqual([task["id"] for task in result["tasks"]], [3, 2, 4, 1])
        self.assertEqual(result, {
            "ok": True, "tasks": result["tasks"], "lists": self.lists, "unsupported": [], "startable": True,
        })
        self.assertEqual(result["tasks"][0], {
            "id": 3, "uid": "uid-3", "revision": hashlib.sha256(path.read_bytes()).hexdigest(),
            "list": "Straße", "list_colour": "#123456", "summary": "Task 3", "description": "",
            "location": "", "categories": [], "priority": 0, "status": "CANCELLED", "percent": 0,
            "completed": False, "recurring": False, "rrule": "", "created_at": None, "start": None,
            "due": {"kind": "date", "value": "2025-01-01"},
        })

    def test_snapshot_isolates_malformed_property_from_valid_neighbor(self):
        malformed_priority = self.task_file(1, "PRIORITY:1", "PRIORITY:2")
        malformed_tzid = self.task_file(3, 'DUE;TZID="UTC+25:00":20250101T120000')
        self.paths = {2: self.task_file(2), 3: malformed_tzid}
        self.rows = [
            {"id": 1, "list": "Straße", "file_path": str(malformed_priority)},
            {"id": 3, "list": "Straße"},
            {"id": 2, "list": "Other"},
        ]
        result = backend.run({"action": "snapshot"})
        self.assertTrue(result["ok"])
        self.assertEqual([task["id"] for task in result["tasks"]], [2])
        self.assertEqual(result["unsupported"], [
            {"id": 1, "list": "Straße", "message": "The task has malformed calendar properties."},
            {"id": 3, "list": "Straße", "message": "The date or timezone is invalid."},
        ])

    def test_snapshot_propagates_cli_failures(self):
        self.rows = [{"id": 1, "list": "Straße"}]
        for command in ("lists", "list", "path"):
            with self.subTest(command=command):
                self.failing_command = command
                with self.assertRaises(backend.BackendError) as error:
                    backend.run({"action": "snapshot"})
                self.assertEqual(error.exception.code, "command")

    def test_recurrence_override_remains_unsupported(self):
        override = self.task_file(1, "RECURRENCE-ID:20250101T120000Z")
        self.paths[1] = override
        self.rows = [{"id": 1, "list": "Straße", "file_path": str(override)}]
        result = backend.run({"action": "snapshot"})
        message = "The calendar file has ambiguous or recurrence-override tasks."
        self.assertEqual(result["tasks"], [])
        self.assertEqual(result["unsupported"], [{"id": 1, "list": "Straße", "message": message}])
        with self.assertRaisesRegex(backend.BackendError, message):
            backend.find_uid("uid-1")

    def test_detail_and_save_keep_authoritative_path_resolution(self):
        actual = self.task_file(1)
        original = actual.read_bytes()
        hint = self.task_file(2)
        self.paths[1] = actual
        self.rows = [{"id": 1, "list": "Straße", "file_path": str(hint)}]
        request = {"id": 1, "uid": "uid-1", "file_path": str(hint)}
        detail = backend.run({**request, "action": "detail"})
        self.assertEqual(detail["task"]["revision"], hashlib.sha256(original).hexdigest())
        with self.assertRaises(backend.BackendError) as error:
            backend.run({**request, "action": "save", "revision": hashlib.sha256(hint.read_bytes()).hexdigest(),
                         "changes": {"summary": "Do not write"}})
        self.assertEqual(error.exception.code, "conflict")
        self.assertEqual(self.commands, [("list", "--status", "ANY", "--sort", "due"), ("path", "1")] * 2)
        self.assertEqual(actual.read_bytes(), original)
