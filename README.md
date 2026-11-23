# dms-todoman-plugin

A [DuxShell](https://github.com/duxlabs-dev/dux-shell) bar widget for your
CalDAV tasks, backed by [Todoman](https://todoman.readthedocs.io/). It shows
your open-task count in the bar and opens an agenda with a separate task
editor. Your existing local `.ics` files remain the source of truth.

> **AI disclaimer:** The QML frontend was built with the help of AI, following
> DuxShell's design language so it matches the rest of the
> shell.

## Requirements

- **DuxShell ≥ 2.1.1** to load the widget.
- **A Todoman configuration and local task directories.** The plugin respects
  `TODOMAN_CONFIG`. Use [vdirsyncer](https://vdirsyncer.readthedocs.io/) or your
  existing CalDAV sync setup if you want to keep those directories in sync.
- **Todoman ≥ 4.7 and Python ≥ 3.10 with `icalendar` and `python-dateutil`.** The
  Nix package supplies both runtimes. For a manual install, see the setup below.

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

A short-lived Python helper uses the `todo` CLI for task discovery and parses
the `.ics` files for fields the CLI omits, including the UID, recurrence rule,
and date-only versus timed values. The Nix package includes a private build of
Todoman that adds file paths to its JSON list output, avoiding one `todo path`
call per task on refresh. Manual installs still use the stock CLI. The helper
uses the same iCalendar parser for reads and field edits.

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
| `futureTasks`     | Follow Todoman's `startable` setting (`config`), or `show` / `hide` future-start open tasks | `config` |
| `refreshInterval` | Reload interval, in minutes                          | `5`     |
| `pythonExecutable` | Optional interpreter with the parser dependencies; one executable path, not a shell command | bundled with Nix; auto-detected otherwise |

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

From a checkout, run `nix build`. The package puts `plugin.json` and the QML
files at the output root. You can use that output as the plugin source below.
If you use the project's `nix develop` shell or allow its `.envrc` with direnv,
a plain `nix build` from the project root copies the package into a regular
`result/` directory instead of creating a symlink. It refreshes untouched
build output on subsequent runs. Move `result/` aside before rebuilding if
it contains output from an older wrapper, or if you changed or added files.
Run one build at a time per checkout and do not edit `result/` during a build.

For Home Manager, add the flake input and use its default package directly:

```nix
# flake.nix
inputs.dms-todoman-plugin.url = "github:Shochraos/dms-todoman-plugin";
```

```nix
{
  programs.dank-material-shell.plugins.dankTodoman = {
    enable = true;
    src = inputs.dms-todoman-plugin.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
```

Keep the `dankTodoman` key to retain existing placements and settings. No plugin
registry input, separate `pkgs.todoman`, or Python setting is required for the
widget. If you previously set `pythonExecutable` just to install the parser
dependencies, remove that setting to use the bundled interpreter. An explicit
custom interpreter still works. Keep your own `todoman` package if you also use
`todo` in a terminal.

### Manual / local path

Point a `home.file` / `xdg.configFile` entry (or copy the folder) at your
DuxShell plugins directory:

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
environment's `bin/python`. You can also leave the setting blank if the plugin
can find the parser modules in the environment used by `todo`. For a manual
install, `todo` must be available on DuxShell's `PATH`.

Reload or restart DuxShell after installing when you are ready for the plugin
to load. The plugin ID remains `dankTodoman`, so existing placements and settings
do not need renaming. DuxShell 2.x migrates the old `DankMaterialShell` config
directory to `dms` and leaves compatibility symlinks.

## License

Released into the public domain under [The Unlicense](UNLICENSE).
