#!/usr/bin/env python3
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

try:
    if sys.version_info < (3, 10):
        raise ImportError()
    from zoneinfo import ZoneInfo
    import icalendar
    from dateutil.rrule import rrulestr
except ImportError:
    print(json.dumps({"ok": False, "code": "dependency", "message": "Python 3.10 or newer with icalendar and python-dateutil is required.", "mutated": False, "task": None}))
    sys.exit(0)


class BackendError(Exception):
    def __init__(self, code, message):
        self.code = code
        self.message = message
        super().__init__(message)


def fail(code, message):
    raise BackendError(code, message)


def cli(*arguments, config=None):
    try:
        options = ["--config", config] if config else []
        result = subprocess.run(["todo", "--porcelain", *options, *map(str, arguments)], capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        fail("dependency", "Todoman executable 'todo' was not found.")
    except subprocess.TimeoutExpired:
        fail("command", "Todoman timed out; refresh before retrying a mutation.")
    if result.returncode:
        if arguments and arguments[0] == "lists" and "No such command" in result.stderr:
            fail("unsupported", "This Todoman CLI does not support list discovery.")
        fail("command", "Todoman command failed; check its configuration and task availability.")
    return result.stdout


def cli_json(*arguments, config=None):
    try:
        return json.loads(cli(*arguments, config=config))
    except (ValueError, TypeError):
        fail("unsupported", "Todoman returned an unsupported porcelain response.")


def parsed_file(task_id):
    path = Path(cli("path", task_id).strip())
    try:
        data = path.read_bytes()
        calendar = icalendar.Calendar.from_ical(data)
        todos = calendar.walk("VTODO")
        if len(todos) != 1 or todos[0].get("RECURRENCE-ID") is not None:
            fail("unsupported", "The calendar file has ambiguous or recurrence-override tasks.")
        component = todos[0]
        if not component.get("UID") or isinstance(component.get("UID"), list):
            fail("unsupported", "The task has no UID.")
        return path, data, calendar, component
    except BackendError:
        raise
    except Exception:
        fail("unsupported", "The task calendar file could not be safely parsed.")


def fixed_zone(tzid):
    match = re.fullmatch(r"(?:UTC|GMT)([+-])(\d{2}):(\d{2})", tzid)
    if not match:
        return None
    hours, minutes = int(match[2]), int(match[3])
    if hours > 23 or minutes > 59:
        fail("validation", "The date or timezone is invalid.")
    offset = timedelta(hours=hours, minutes=minutes)
    return timezone(offset if match[1] == "+" else -offset)


def typed_date(component, name):
    value = component.get(name)
    if value is None:
        return None
    if isinstance(value, list):
        fail("unsupported", "The task has duplicate date properties.")
    decoded = value.dt
    if isinstance(decoded, datetime):
        tzid = str(value.params.get("TZID", ""))
        if tzid and decoded.tzinfo is None:
            fixed = fixed_zone(tzid)
            if fixed is not None:
                decoded = decoded.replace(tzinfo=fixed)
        result = {"kind": "datetime", "value": decoded.isoformat()}
        if value.params.get("TZID"):
            result["tzid"] = str(value.params["TZID"])
        return result
    if isinstance(decoded, date):
        return {"kind": "date", "value": decoded.isoformat()}
    fail("unsupported", "The task has an unsupported date value.")


def task_from_row(row):
    task_id = row["id"]
    path, data, calendar, component = parsed_file(task_id)
    categories = component.get("CATEGORIES")
    if categories is None:
        category_values = []
    else:
        groups = categories if isinstance(categories, list) else [categories]
        category_values = [str(value) for group in groups for value in group.cats]
    created = component.decoded("CREATED", None)
    created_at = int(created.timestamp()) if isinstance(created, datetime) and created.tzinfo else None
    rule = component.get("RRULE")
    if isinstance(rule, list):
        fail("unsupported", "The task has multiple recurrence rules.")
    status = str(component.get("STATUS", "NEEDS-ACTION"))
    return {"id": task_id, "uid": str(component.get("UID")), "revision": hashlib.sha256(data).hexdigest(), "list": row["list"], "list_colour": row.get("list_colour"), "summary": str(component.get("SUMMARY", "")), "description": str(component.get("DESCRIPTION", "")), "location": str(component.get("LOCATION", "")), "categories": category_values, "priority": int(component.get("PRIORITY", 0)), "status": status, "percent": int(component.get("PERCENT-COMPLETE", 0)), "completed": status != "CANCELLED" and (status == "COMPLETED" or component.get("COMPLETED") is not None), "recurring": bool(rule), "rrule": rule.to_ical().decode() if rule else "", "created_at": created_at, "start": typed_date(component, "DTSTART"), "due": typed_date(component, "DUE")}


def rows(sort="due"):
    config = os.environ.get("TODOMAN_CONFIG")
    if not config:
        home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
        directories = [home, *(os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":")]
        config = next((str(Path(directory) / "todoman" / "config.py") for directory in directories if directory and (Path(directory) / "todoman" / "config.py").exists()), None)
    if not config:
        fail("command", "Todoman configuration could not be found.")
    with tempfile.TemporaryDirectory(prefix="todoman-view-") as directory:
        overlay = Path(directory) / "config.py"
        overlay.write_text("import runpy\nglobals().update(runpy.run_path(" + repr(config) + "))\nstartable = False\n")
        return cli_json("list", "--status", "ANY", "--sort", sort, config=str(overlay))


def find_id(task_id):
    for row in rows():
        if row.get("id") == task_id:
            return task_from_row(row)
    fail("conflict", "The task is no longer available; refresh and reopen it.")


def find_uid(uid, list_name=None):
    matches = []
    for row in rows():
        if list_name is None or row.get("list") == list_name:
            try:
                task = task_from_row(row)
            except BackendError as error:
                if error.code != "unsupported":
                    raise
                try:
                    path = Path(cli("path", row["id"]).strip())
                    calendar = icalendar.Calendar.from_ical(path.read_bytes())
                    values = [component.get("UID") for component in calendar.walk("VTODO")]
                    if not values or any(value is None or isinstance(value, list) or str(value) == uid for value in values):
                        raise error
                except BackendError:
                    raise
                except Exception:
                    raise error
                continue
            if task["uid"] == uid:
                matches.append(task)
    if len(matches) != 1:
        fail("conflict", "The task identity could not be uniquely resolved; refresh before retrying.")
    return matches[0]


def native_safe(task):
    for field in ("start", "due"):
        value = task[field]
        if value and value.get("tzid") and fixed_zone(value["tzid"]) is not None:
            fail("unsupported", "Todoman cannot safely read this fixed-offset timezone; save the date before this action.")
        if value and value["kind"] == "datetime" and datetime.fromisoformat(value["value"].replace("Z", "+00:00")).tzinfo is None:
            fail("unsupported", "Todoman would normalize a floating datetime; this action is unsafe for the task.")
    if task["start"] and task["due"]:
        start, due = parse_date(task["start"]), parse_date(task["due"])
        if type(start) is not type(due) or start >= due:
            fail("unsupported", "Todoman cannot safely rewrite this start/due combination.")


def completion_safe(task):
    native_safe(task)
    rule = task.get("rrule", "")
    if rule and re.search(r"(?:^|;)(?:COUNT|UNTIL)=", rule, re.IGNORECASE):
        fail("unsupported", "Todoman cannot safely advance finite recurrence rules.")
    if rule and any(task.get(field) and task[field].get("tzid") for field in ("start", "due")):
        fail("unsupported", "Todoman normalizes recurring timezone values and may change their local time across transitions.")


def identity(request, revision=True):
    task_id = request.get("id")
    if type(task_id) is not int or task_id < 1 or not isinstance(request.get("uid"), str) or not request["uid"]:
        fail("validation", "A task ID and UID are required.")
    task = find_id(task_id)
    if task["uid"] != request["uid"]:
        fail("conflict", "The task ID now identifies a different task.")
    if revision and (not isinstance(request.get("revision"), str) or request["revision"] != task["revision"]):
        fail("conflict", "The task changed since it was opened.")
    return task


def parse_date(value):
    if value is None:
        return None
    if not isinstance(value, dict) or value.get("kind") not in ("date", "datetime") or not isinstance(value.get("value"), str):
        fail("validation", "A date must be null or a typed date value.")
    try:
        if value["kind"] == "date":
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value["value"]):
                raise ValueError()
            return date.fromisoformat(value["value"])
        parsed = datetime.fromisoformat(value["value"].replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            fail("unsupported", "New timed values require an explicit timezone offset.")
        if value.get("tzid"):
            zoned = parsed.astimezone(fixed_zone(value["tzid"]) or ZoneInfo(value["tzid"]))
            if zoned.utcoffset() != parsed.utcoffset() or zoned.replace(tzinfo=None) != parsed.replace(tzinfo=None):
                fail("validation", "The timezone and datetime offset disagree.")
            parsed = zoned
        return parsed if isinstance(parsed.tzinfo, ZoneInfo) else parsed.astimezone(timezone.utc)
    except BackendError:
        raise
    except Exception:
        fail("validation", "The date or timezone is invalid.")


def validate(changes, current=None):
    if not isinstance(changes, dict):
        fail("validation", "Changes must be an object.")
    allowed = {"summary", "description", "location", "categories", "priority", "status", "percent", "start", "due", "rrule", "list"}
    if set(changes) - allowed:
        fail("validation", "Changes contain an unsupported field.")
    for name in ("summary", "description", "location", "rrule", "list"):
        if name in changes and not isinstance(changes[name], str):
            fail("validation", "Text fields must be strings.")
    if "summary" in changes and not changes["summary"].strip():
        fail("validation", "Summary cannot be blank.")
    if "list" in changes and not changes["list"].strip():
        fail("validation", "List cannot be blank.")
    if "categories" in changes and (not isinstance(changes["categories"], list) or any(not isinstance(item, str) or not item for item in changes["categories"])):
        fail("validation", "Categories must be an array of nonempty strings.")
    for name, maximum in (("priority", 9), ("percent", 100)):
        if name in changes and (type(changes[name]) is not int or not 0 <= changes[name] <= maximum):
            fail("validation", "Priority or progress is outside its supported range.")
    if "status" in changes and changes["status"] not in ("NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"):
        fail("validation", "Unsupported status.")
    if changes.get("percent") == 100 and changes.get("status") in ("NEEDS-ACTION", "IN-PROCESS", "CANCELLED"):
        fail("validation", "100 percent conflicts with the selected status.")
    if changes.get("status") == "COMPLETED" and "percent" in changes and changes["percent"] != 100:
        fail("validation", "Completed status requires 100 percent.")
    for name in ("start", "due"):
        if name in changes:
            parse_date(changes[name])
    start = changes.get("start", current.get("start") if current else None)
    due = changes.get("due", current.get("due") if current else None)
    if start and due and ("start" in changes or "due" in changes):
        first, last = parse_date(start), parse_date(due)
        if type(first) is not type(last):
            fail("validation", "Start and due must use matching date types.")
        if first >= last:
            fail("validation", "Start must be earlier than due.")
    if changes.get("rrule", current.get("rrule", "") if current else "") and not (start or due):
        fail("validation", "A recurring task needs a start or due date.")
    if "rrule" in changes and changes["rrule"]:
        rule = changes["rrule"]
        if not (start or due):
            fail("validation", "A recurring task needs a start or due date.")
        if not re.fullmatch(r"[A-Za-z0-9=;,+-]+", rule):
            fail("validation", "Invalid recurrence rule.")
        try:
            icalendar.vRecur.from_ical(rule)
            rrulestr(rule)
        except Exception:
            fail("validation", "Invalid recurrence rule.")
        parts = dict(part.split("=", 1) for part in rule.upper().split(";") if "=" in part)
        if set(parts) - {"FREQ", "INTERVAL", "BYDAY"} or parts.get("FREQ") not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY") or ("BYDAY" in parts and parts["FREQ"] != "WEEKLY"):
            fail("unsupported", "Only basic daily, weekly, monthly and yearly rules can be written; existing custom rules are preserved.")
        if "INTERVAL" in parts and (not parts["INTERVAL"].isdigit() or int(parts["INTERVAL"]) < 1):
            fail("validation", "Recurrence interval must be positive.")
        if "BYDAY" in parts and any(day not in ("MO", "TU", "WE", "TH", "FR", "SA", "SU") for day in parts["BYDAY"].split(",")):
            fail("validation", "Invalid weekly recurrence days.")
    return changes


def update_file(task, changes, mark_mutated):
    path, original, calendar, component = parsed_file(task["id"])
    if str(component.get("UID")) != task["uid"] or hashlib.sha256(original).hexdigest() != task["revision"]:
        fail("conflict", "The task changed before it could be saved.")
    mapping = {"summary": "SUMMARY", "description": "DESCRIPTION", "location": "LOCATION", "categories": "CATEGORIES", "priority": "PRIORITY", "status": "STATUS", "percent": "PERCENT-COMPLETE", "start": "DTSTART", "due": "DUE", "rrule": "RRULE"}
    for name, value in changes.items():
        if name not in mapping:
            continue
        key = mapping[name]
        component.pop(key, None)
        if value is None or value == "" or value == [] or (name in ("priority", "percent") and value == 0):
            continue
        if name in ("start", "due"):
            value = parse_date(value)
        elif name == "rrule":
            value = icalendar.vRecur.from_ical(value)
        component.add(key, value)
    if changes.get("status") in ("NEEDS-ACTION", "IN-PROCESS", "CANCELLED"):
        component.pop("COMPLETED", None)
    now = datetime.now(timezone.utc)
    for key, value in (("LAST-MODIFIED", now), ("DTSTAMP", now), ("SEQUENCE", int(component.get("SEQUENCE", 0)) + 1)):
        component.pop(key, None)
        component.add(key, value)
    encoded = calendar.to_ical()
    temporary = None
    try:
        source_stat = path.stat()
        attributes = {name: os.getxattr(path, name) for name in os.listxattr(path)}
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".todoman-", delete=False) as stream:
            temporary = stream.name
            stream.write(encoded)
            stream.flush()
            os.fchown(stream.fileno(), source_stat.st_uid, source_stat.st_gid)
            os.fchmod(stream.fileno(), stat.S_IMODE(source_stat.st_mode))
            for name in os.listxattr(stream.fileno()):
                if name not in attributes:
                    os.removexattr(stream.fileno(), name)
            for name, value in attributes.items():
                os.setxattr(stream.fileno(), name, value)
            saved_stat = os.fstat(stream.fileno())
            saved_attributes = {name: os.getxattr(stream.fileno(), name) for name in os.listxattr(stream.fileno())}
            if (saved_stat.st_uid, saved_stat.st_gid, stat.S_IMODE(saved_stat.st_mode), saved_attributes) != (source_stat.st_uid, source_stat.st_gid, stat.S_IMODE(source_stat.st_mode), attributes):
                fail("unsupported", "Task file metadata could not be preserved.")
            os.fsync(stream.fileno())
        if hashlib.sha256(path.read_bytes()).hexdigest() != task["revision"]:
            fail("conflict", "The task changed before the final write.")
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            try:
                os.replace(temporary, path)
            except Exception:
                try:
                    if path.read_bytes() != original:
                        mark_mutated()
                except OSError:
                    mark_mutated()
                raise
            mark_mutated()
            temporary = None
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def run(request):
    if not isinstance(request, dict):
        fail("validation", "Request must be an object.")
    if not shutil.which("todo"):
        fail("dependency", "Todoman executable 'todo' was not found.")
    action = request.get("action")
    if action == "snapshot":
        watched = request.get("lists", [])
        sort = request.get("sort", "due")
        if not isinstance(watched, list) or any(not isinstance(item, str) for item in watched) or sort not in ("due", "priority", "created_at", "summary"):
            fail("validation", "Invalid list filter or sort field.")
        available = cli_json("lists")
        tasks, unsupported = [], []
        for row in rows(sort):
            if watched and row.get("list", "").casefold() not in {item.casefold() for item in watched}:
                continue
            try:
                tasks.append(task_from_row(row))
            except BackendError as error:
                if error.code != "unsupported":
                    raise
                unsupported.append({"id": row.get("id"), "list": row.get("list"), "message": error.message})
        return {"ok": True, "tasks": tasks, "lists": available, "unsupported": unsupported}
    if action == "detail":
        return {"ok": True, "task": identity(request, False)}
    if action not in ("create", "save", "complete", "cancel", "reopen", "delete", "move", "copy"):
        fail("validation", "Unknown action.")
    mutated = False
    task = None
    def mark_mutated():
        nonlocal mutated
        mutated = True
    try:
        if action == "create":
            changes = validate(request.get("changes"))
            if not changes.get("summary", "").strip():
                fail("validation", "Summary cannot be blank.")
            if "list" in changes and changes["list"] not in cli_json("lists"):
                fail("validation", "The destination list does not exist.")
            if changes.get("status") == "COMPLETED" or changes.get("percent") == 100:
                completion_safe({"start": changes.get("start"), "due": changes.get("due"), "rrule": changes.get("rrule", "")})
            arguments = ["new", "--priority", str(changes.get("priority", 0))]
            if changes.get("list"):
                arguments += ["--list=" + changes["list"]]
            arguments += ["--", changes["summary"]]
            mutated = True
            output = cli(*arguments)
            try:
                task = find_id(json.loads(output)["id"])
            except Exception:
                fail("partial", "Task creation succeeded but its identity could not be resolved; refresh before retrying.")
            patch = dict(changes)
            patch.setdefault("start", None)
            patch.setdefault("due", None)
        else:
            task = identity(request)
            patch = validate(request.get("changes"), task) if action == "save" else {}
        if action in ("create", "save"):
            target = patch.get("list")
            if target and target not in cli_json("lists"):
                fail("validation", "The destination list does not exist.")
            completing = patch.get("status") == "COMPLETED" or patch.get("percent") == 100
            if completing:
                completion_safe({**task, "start": patch.get("start", task["start"]), "due": patch.get("due", task["due"]), "rrule": patch.get("rrule", task["rrule"])})
            if task["completed"] and completing:
                patch.pop("status", None)
                patch.pop("percent", None)
                completing = False
            if task["completed"] and (patch.get("status") in ("NEEDS-ACTION", "IN-PROCESS") or ("percent" in patch and patch["percent"] < 100)):
                patch.setdefault("status", "NEEDS-ACTION")
                patch.setdefault("percent", 0)
            if completing:
                patch.pop("status", None)
                patch.pop("percent", None)
            file_patch = {key: value for key, value in patch.items() if key != "list"}
            if file_patch:
                update_file(task, file_patch, mark_mutated)
                task = find_uid(task["uid"], task["list"])
            if target and target != task["list"]:
                task = identity(task)
                mutated = True
                cli("move", "--list=" + target, str(task["id"]))
                task = find_uid(task["uid"], target)
            if completing:
                task = identity(task)
                mutated = True
                cli("done", str(task["id"]))
                task = find_uid(task["uid"], task["list"])
        elif action == "reopen":
            update_file(task, {"status": "NEEDS-ACTION", "percent": 0}, mark_mutated)
            task = find_uid(task["uid"], task["list"])
        elif action in ("complete", "cancel"):
            if action == "complete" and task["completed"]:
                return {"ok": True, "task": task}
            if action == "complete":
                completion_safe(task)
            else:
                native_safe(task)
            task = identity(task)
            mutated = True
            cli("done" if action == "complete" else "cancel", str(task["id"]))
            task = find_uid(task["uid"], task["list"])
        elif action == "delete":
            task = identity(task)
            mutated = True
            cli("delete", "--yes", str(task["id"]))
            task = None
        else:
            target = request.get("target_list")
            if not isinstance(target, str) or target not in cli_json("lists"):
                fail("validation", "The destination list does not exist.")
            if action == "move" and target == task["list"]:
                return {"ok": True, "task": task}
            if action == "copy":
                native_safe(task)
            before = {row["id"] for row in rows()} if action == "copy" else set()
            task = identity(task)
            mutated = True
            cli(action, "--list=" + target, str(task["id"]))
            if action == "move":
                task = find_uid(task["uid"], target)
            else:
                new_rows = [row for row in rows() if row["id"] not in before and row["list"] == target]
                if len(new_rows) != 1:
                    fail("partial", "Copy succeeded but its identity could not be uniquely resolved; refresh before retrying.")
                task = task_from_row(new_rows[0])
        return {"ok": True, "task": task}
    except BackendError as error:
        if mutated:
            if task:
                try:
                    task = find_uid(task["uid"])
                except Exception:
                    task = None
            if action == "copy":
                task = None
            return {"ok": False, "code": "partial", "message": error.message + " A change may have occurred; refresh before retrying.", "mutated": True, "task": task}
        raise
    except Exception:
        if mutated:
            if task and action != "copy":
                try:
                    task = find_uid(task["uid"])
                except Exception:
                    task = None
            else:
                task = None
            return {"ok": False, "code": "partial", "message": "The mutation outcome could not be established; refresh before retrying.", "mutated": True, "task": task}
        raise


def main():
    try:
        request = json.load(sys.stdin)
        response = run(request)
    except BackendError as error:
        response = {"ok": False, "code": error.code, "message": error.message, "mutated": False, "task": None}
    except Exception:
        response = {"ok": False, "code": "unsupported", "message": "The request or task data could not be processed safely.", "mutated": False, "task": None}
    print(json.dumps(response, ensure_ascii=False))


if __name__ == "__main__":
    main()
