# dms-todoman-plugin

A [DuxShell](https://github.com/duxlabs-dev/dux-shell) bar widget for your
CalDAV tasks, backed by [Todoman](https://todoman.readthedocs.io/). It shows
your open-task count in the bar and opens an agenda with a separate task
editor. Your existing local `.ics` files remain the source of truth.

> **AI disclaimer:** The QML frontend was built with the help of AI, following
> DuxShell's design language so it matches the rest of the
> shell.

> [!IMPORTANT]
> Todoman and the Python parser environment are both required. A working
> `todo` command alone does not supply the parser modules to a separate
> Python interpreter. See [Requirements](#requirements) and
> [Installation](#installation).

## Requirements

| Requirement | Why | Notes |
|-------------|-----|-------|
| **Todoman ≥ 4.7** (`todo` on the shell's `PATH`) | Task discovery and native lifecycle operations | Needs a working Todoman configuration and local task directories; respects `TODOMAN_CONFIG` |
| **DuxShell ≥ 2.1.1** | Native popout, menus and calendar controls | Declared by `requires_dms` in `plugin.json` |
| **Python ≥ 3.10 with the packages in `requirements.txt`** | Structured iCalendar reads and field edits | Select the interpreter with `pythonExecutable`; defaults to `python3` |

todoman itself reads CalDAV `VTODO`s from local `.ics` directories — typically
kept in sync with a CalDAV server via
[vdirsyncer](https://vdirsyncer.readthedocs.io/). Setting that up is out of scope
here. Check that `todo list` works and that the configured Python interpreter
can import `icalendar` and `dateutil` in the environment used by DuxShell.

## Features

- The bar shows a global open-task count in either orientation. The optional
  next-task display chooses the nearest upcoming task, falling back to the most
  recently overdue task. Long titles are truncated; a vertical bar shows only
  the countdown.
- The agenda uses flat rows, list-colour markers, and due-date section headers.
  Search and list/status/category/priority filters narrow the view without
  changing the bar's watched-list count.
- A separate create/edit view exposes summary, list, independent start and due
  dates, date-only or timed scheduling, numeric priority, notes, categories,
  location, status, and progress.
- Repeat controls cover daily, weekly, monthly, and yearly rules with intervals
  and weekly day selection. Existing custom rules are preserved on unrelated
  edits. Todoman advances the schedule when the task is completed.
- Complete, cancel, reopen, move, copy, and delete tasks. Permanent deletion
  requires confirmation. Reopening one completed occurrence does not rewind a
  recurring series or remove its later occurrences.
- A failed save retains the draft. Task identity/revision checks detect stale
  edits; partial changes are reported rather than presented as an atomic save.
- If an ambiguous or unreadable task entry is omitted, the agenda lists the
  affected entries and marks the bar count with `+` to indicate a lower bound.
  The next-task suggestion can also be incomplete in that state.

The recurrence editor does not add completion-relative scheduling, missed-date
catch-up, or occurrence-count/end-date controls. Monthly rules can skip months
without the requested day; yearly leap-day rules can skip non-leap years.
Existing complex rules are not a promise that every upstream recurrence case
works. Alarms, subtasks, attachments, and CalDAV setup are outside the editor's
scope.

Completion is currently blocked for existing finite rules (`COUNT` or `UNTIL`)
and recurring tasks with named-timezone dates. Isolated Todoman 4.7 checks
showed incorrect rule exhaustion and local-time changes across timezone
transitions. These tasks remain readable and editable; the plugin does not
replace Todoman's recurrence engine.

New fixed-offset timed values are stored in UTC, preserving the instant rather
than a named timezone's wall-clock schedule. Floating datetimes and legacy
synthetic timezone IDs restrict native actions that would rewrite their dates.
Legacy fixed-offset dates must be explicitly resaved before completion,
cancellation, or copying. Start must be earlier than due when both are set.

## Architecture

The QML widget composes the bar, agenda, and task editor. One controller owns
task snapshots, view filters, drafts, and serialized backend requests. It keeps
view filtering separate from the global watched-list count.

A short-lived Python helper communicates with the public `todo` CLI and parses
the files located by `todo path`. The structured read supplies fields that
Todoman's JSON omits, including the UID, recurrence rule, status, and date-only
versus timed values. Field edits use an iCalendar parser rather than physical
line replacements. The helper does not import Todoman's internal Python APIs.

Todoman retains responsibility for native completion and generating the next
recurring occurrence. There is no plugin daemon, second task database, or sync
engine. Writes check the selected task's identity and file revision and then
refetch authoritative state. Multi-step CLI/file operations are not a
transaction with external sync clients; partial failures must be resolved
before retrying an operation that may already have changed a task.

## Settings

| Key               | Meaning                                              | Default |
|-------------------|------------------------------------------------------|---------|
| `listFilter`      | Comma-separated list names the widget **watches** (empty = all) | `""`    |
| `defaultList`     | Default list for new tasks (empty = todoman default) | `""`    |
| `sortField`       | Order within each group: `due` \| `priority` \| `created_at` \| `summary` | `due` |
| `showCompleted`   | Include done/cancelled tasks                         | `false` |
| `showNearestTask` | Append the next due task + countdown to the bar pill | `false` |
| `refreshInterval` | Reload interval, in minutes                          | `5`     |
| `pythonExecutable` | Python interpreter with the parser dependencies; one executable path, not a shell command | `python3` |

Grouping by due date is always on; `sortField` controls the order of tasks
*within* each group.

`listFilter` sets the watched lists. Use **Show filters** in the agenda header
to narrow the view without changing those lists. The helper enumerates Todoman rows across all lists and statuses, then
filters watched lists before reading their individual files. A temporary
configuration overlay disables Todoman's `startable` view default for that
enumeration so future-start tasks remain available; it does not change your
configuration file. A viewed list that disappears from the watched scope resets
the view to *All lists*.

## Installation

### Nix flake (declarative)

Add the repo as a flake input and hand it to the DMS `plugins` option — the
attribute name must match the plugin directory and the `id` in
`plugin.json` (`dankTodoman`):

```nix
# flake.nix
inputs.dms-todoman-plugin = {
  url = "github:Shochraos/dms-todoman-plugin";
  flake = false;
};
```

```nix
let
  todomanPython = pkgs.python3.withPackages (ps: [
    ps.icalendar
    ps.python-dateutil
  ]);
in {
  home.packages = [ pkgs.todoman ];
  programs.dank-material-shell.plugins.dankTodoman = {
    enable = true;
    src = inputs.dms-todoman-plugin;
    settings.pythonExecutable = "${todomanPython}/bin/python3";
  };
}
```

The legacy `programs.dank-material-shell` option name is an API identifier,
not the displayed shell name. Keep the option exported by your DuxShell
Home Manager module. These examples do not update your flake lock or activate
the plugin automatically.

### Manual / local path

Point a `home.file` / `xdg.configFile` entry (or just copy the folder) at your
DMS plugins directory:

```nix
xdg.configFile."dms/plugins/dankTodoman".source = ./.;
```

For a non-Nix installation, create a Python environment and install the helper's
dependencies from this checkout:

```bash
python3 -m venv ~/.local/share/dux-todoman-python
~/.local/share/dux-todoman-python/bin/python -m pip install -r requirements.txt
```

Set the plugin's **Python interpreter** setting to the absolute path of that
environment's `bin/python`. Todoman must still be available on DuxShell's
`PATH`; this environment installs the parser dependencies, not Todoman itself.

Reload or restart DuxShell after installing when you are ready for the plugin
to load. The plugin ID remains `dankTodoman`, so existing placements and settings
do not need renaming. DuxShell 2.x migrates the old `DankMaterialShell` config
directory to `dms` and leaves compatibility symlinks.

## License

[MIT](LICENSE) © 2026 Shochraos
