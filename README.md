# hypr

Hyprland compositor configuration, driven by Lua (`hl.*` API). Part of the
quantumfate desktop:

- [**quickshell**](https://github.com/quantumfate/quickshell) — the desktop
  shell / UI. See its
  [ARCHITECTURE.md](https://github.com/quantumfate/quickshell/blob/main/ARCHITECTURE.md)
  for how this config and the UI bridge (shared JSON state + IPC).
- [**scripts**](https://github.com/quantumfate/scripts) — standalone CLI helpers
  invoked from keybinds.

## Layout

```
hypr/
  conf.lua, binds.lua, ...   compositor settings and keybinds
  lib/                       reusable helpers
    store.lua, json.lua        shared JSON state, mirror of quickshell's Store (Bridge 1)
    submap.lua                 which-key submap trees, with on_enter/on_leave hooks
    bind.lua, notify.lua, ...
  services/                  feature modules
    dofus/                     Dofus multibox: team (SoT-backed), swap, launch, ipc
  themes/                    Catppuccin palettes applied to the compositor
  events/                    startup hooks (autostarts quickshell under uwsm)
```

## Bridges to the UI

- **State**: `hypr/lib/store.lua` reads/writes `$XDG_STATE_HOME/<name>.json`, the
  same files the Quickshell `Store` mirrors. The file is the single source of
  truth; both sides converge.
- **Command**: `hypr/services/dofus/ipc.lua` (and the cheatsheet bind) call
  `qs -c quantumfate ipc call …` to drive UI windows.
- **Submap callbacks**: `submap.tree` entries take `on_enter`/`on_leave` to sync
  UI state as submaps are navigated (which-key behaviour).

Full picture:
[quickshell/ARCHITECTURE.md](https://github.com/quantumfate/quickshell/blob/main/ARCHITECTURE.md).
