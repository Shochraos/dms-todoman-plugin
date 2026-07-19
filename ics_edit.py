#!/usr/bin/env python3
"""Field-level edits todoman's CLI can't do: rename SUMMARY, clear DUE/PRIORITY.

Usage: ics_edit.py <todo-id> <new-summary> <clear-due 0|1> <clear-priority 0|1>
Resolves the task's .ics path via `todo path` and rewrites it in place.
"""
import subprocess
import sys


def esc(s: str) -> str:
    # RFC 5545 text escaping for SUMMARY values.
    return (
        s.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", " ")
        .replace("\r", " ")
    )


def main() -> int:
    todo_id, summary = sys.argv[1], sys.argv[2]
    clear_due = sys.argv[3] == "1"
    clear_prio = sys.argv[4] == "1"

    path = subprocess.check_output(["todo", "path", todo_id]).decode().strip()
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    out = []
    for line in lines:
        key = line.split(":", 1)[0].split(";", 1)[0]
        if key == "SUMMARY":
            out.append("SUMMARY:" + esc(summary))
            continue
        if clear_due and key in ("DUE", "DTSTART"):
            continue
        if clear_prio and key == "PRIORITY":
            continue
        out.append(line)

    with open(path, "w", encoding="utf-8") as f:
        f.write("\r\n".join(out) + "\r\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
