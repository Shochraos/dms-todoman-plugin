import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = os.environ.get("DANK_TODOMAN_PACKAGE")


def launch(plugin, home, interpreter="", *, config=None, request=None):
    environment = {"PATH": "", "HOME": str(home), "LC_ALL": "C.UTF-8"}
    if config is not None:
        environment["TODOMAN_CONFIG"] = str(config)
    shell = ["/bin/sh"] if plugin == ROOT else []
    return subprocess.run(
        [*shell, str(plugin / "run_backend.sh"), str(plugin / "todoman_backend.py"), str(interpreter)],
        input=json.dumps(request or {"action": "create", "changes": {"summary": "Not written"}}),
        capture_output=True, text=True, env=environment, timeout=30,
    )


class LauncherTests(unittest.TestCase):
    def test_only_exec_failure_reports_no_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            missing = directory / "missing interpreter"
            invalid = directory / "invalid interpreter"
            invalid.write_text(f"#!{directory}/missing\n")
            invalid.chmod(0o700)
            started = directory / "started interpreter"
            started.write_text("#!/bin/sh\nexit 127\n")
            started.chmod(0o700)
            for plugin in [ROOT] + ([Path(PACKAGE)] if PACKAGE else []):
                for interpreter in (missing, invalid, started):
                    with self.subTest(plugin=plugin, interpreter=interpreter.name):
                        result = launch(plugin, directory, interpreter)
                        self.assertNotEqual(result.returncode, 0)
                        if interpreter == started:
                            self.assertEqual(result.returncode, 127)
                            self.assertEqual(result.stdout, "")
                        else:
                            reply = json.loads(result.stdout)
                            self.assertIs(reply["ok"], False)
                            self.assertIs(reply["mutated"], False)
                            self.assertEqual(reply["code"], "dependency")

    @unittest.skipUnless(PACKAGE, "set DANK_TODOMAN_PACKAGE to test the installed launcher")
    def test_packaged_launcher_reads_a_task_with_empty_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            calendar = root / "calendars" / "Work"
            calendar.mkdir(parents=True)
            config = root / "config.py"
            config.write_text(f"path = {str(calendar.parent / '*')!r}\ncache_path = {str(root / 'cache.sqlite')!r}\n")
            (calendar / "demo.ics").write_bytes(b"\r\n".join((
                b"BEGIN:VCALENDAR", b"VERSION:2.0", b"PRODID:-//Tests//EN",
                b"BEGIN:VTODO", b"DTSTAMP:20240101T120000Z", b"UID:fixture-task", b"SUMMARY:Fixture task",
                b"END:VTODO", b"END:VCALENDAR", b"",
            )))
            result = launch(Path(PACKAGE), root, config=config, request={"action": "snapshot"})
            self.assertEqual(result.returncode, 0, result.stderr)
            reply = json.loads(result.stdout)
            self.assertTrue(reply["ok"], reply)
            self.assertEqual(reply["unsupported"], [])
            self.assertEqual([(task["uid"], task["list"]) for task in reply["tasks"]], [("fixture-task", "Work")])
