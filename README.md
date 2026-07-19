# Todoman Tasks — a DankBar plugin

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS)
DankBar widget for your CalDAV to-dos, backed by
[**todoman**](https://todoman.readthedocs.io/). It puts your open-task count in
the bar and opens a popout where you can browse tasks grouped by due date,
complete them, and add or edit tasks inline — all driven by the `todo` CLI, so
your `.ics` files stay the single source of truth.

> [!IMPORTANT]
> **todoman is required.** This plugin is a front-end for the `todo` command; it
> does not read or write `.ics` files on its own (except a tiny Python helper for
> renaming/clearing fields). Without a working `todo` on `PATH` the widget shows
> an error. See [Requirements](#requirements).

## Requirements

| Requirement | Why | Notes |
|-------------|-----|-------|
| [**todoman**](https://todoman.readthedocs.io/) (`todo` on `PATH`) | Every action shells out to `todo` | Needs a working `~/.config/todoman/config.py` pointing at your `.ics` task dirs |
| **DankMaterialShell ≥ 1.5** | Host shell / plugin API | Declared as `requires_dms` in `plugin.json` |
| **python3** on `PATH` | `ics_edit.py` renames a task and clears due/priority | Only invoked when you edit those fields |

todoman itself reads CalDAV `VTODO`s from local `.ics` directories — typically
kept in sync with a CalDAV server via
[vdirsyncer](https://vdirsyncer.readthedocs.io/). Setting that up is out of scope
here; if `todo list` works in your terminal, this plugin will work.

## Features

- **Bar pill** with a checklist icon and a live open-task count.
- **Due-date grouping** in the popout — tasks are split into fixed sections,
  and empty sections are hidden:

  | Group | Contains |
  |-------|----------|
  | **Overdue** | Due before today |
  | **Due today** | Due today |
  | **Due tomorrow** | Due tomorrow |
  | **Upcoming** | Due in 2+ days |
  | **No due date** | Undated tasks |

- **One-click complete** — `todo done <id>`, with an optimistic checked state.
- **Inline create** — summary plus optional list, due date/time, and priority
  (`todo new`).
- **Inline edit** — change summary, list (`todo move`), due date, and priority;
  clearing due/priority is handled by the bundled `ics_edit.py`.
- **Delete** with an inline confirm step (`todo delete --yes`).
- Each row shows a **priority dot**, the **due date**, and the **list name**.
- Configurable list filter, sort field, refresh interval, and a show-completed
  toggle (see [Settings](#settings)).

## Settings

| Key               | Meaning                                              | Default |
|-------------------|------------------------------------------------------|---------|
| `listFilter`      | Comma-separated list names to show (empty = all)     | `""`    |
| `defaultList`     | Default list for new tasks (empty = todoman default) | `""`    |
| `sortField`       | Order within each group: `due` \| `priority` \| `created_at` \| `summary` | `due` |
| `showCompleted`   | Include done/cancelled tasks                         | `false` |
| `refreshInterval` | Reload interval, in minutes                          | `5`     |

Grouping by due date is always on; `sortField` controls the order of tasks
*within* each group.

## Installation

### Nix flake (declarative)

Add the repo as a flake input and hand it to the DMS `plugins` option — the
attribute name becomes the plugin directory under
`~/.config/DankMaterialShell/plugins/`, and it must match the `id` in
`plugin.json` (`dankTodoman`):

```nix
# flake.nix
inputs.dms-taskman-plugin = {
  url = "github:Shochraos/dms-taskman-plugin";
  flake = false;
};
```

```nix
# home-manager module (where you configure DMS)
programs.dank-material-shell.plugins.dankTodoman = {
  enable = true;
  src = inputs.dms-taskman-plugin;
  # settings = { sortField = "priority"; showCompleted = false; };
};
```

### Manual / local path

Point a `home.file` / `xdg.configFile` entry (or just copy the folder) at your
DMS plugins directory:

```nix
xdg.configFile."DankMaterialShell/plugins/dankTodoman".source = ./.;
```

Either way, restart DMS (or its systemd user service) after installing so it
picks the plugin up.

## How it works

- The widget runs `todo --porcelain list` and renders the JSON. Task **ids are
  todoman's own** — the same ones `todo list` / `todo done` print — so completing
  or editing a task uses ids that stay valid. The list is refetched after every
  create/complete/edit so ids never go stale.
- All mutations go through the `todo` CLI, except renaming a summary and clearing
  a due date or priority, which the CLI can't do directly; those go through
  `ics_edit.py`, a small pass over the task's `.ics` file.

## Files

| File | Purpose |
|------|---------|
| `plugin.json` | Plugin manifest (id, capabilities, requirements) |
| `TodomanWidget.qml` | The bar pill + popout UI and all `todo` interaction |
| `TodomanSettings.qml` | Settings page shown in DMS |
| `ics_edit.py` | Rename summary / clear due / clear priority in an `.ics` |

## AI usage

The frontend (the QML UI) was built with the help of AI, following
DankMaterialShell's Material Design scheme so it matches the rest of the shell.

## License

MIT.
