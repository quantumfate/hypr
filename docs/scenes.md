# Scenes

Declarative window manager. The document is the interface. Engines execute it.

## Declaration

Config is the only declaration. No per-feature merge, `barred`, or `spawn` code.

Scenes are keyed by workspace `default_name` (`code`, `gaming`). Workspace id is host data in `workspace_specs`.

Source of truth: `$XDG_STATE_HOME` scenes store (`scenes.json`). Schema lives in the sibling quickshell repo. Lua consumes that document; a parallel table in `hyprland.lua` is not the long-term store.

## Split

The two-tile split is `layout_opts.dwindle.default_split_ratio` (`0.67`). That is what the user declares. A resize loop may correct drift internally; it is not the config language.

## Group

`group = true` on a member match set means one Hyprland group containing **only** those classes. Fold matching windows in; eject foreigners.

Do not use Hyprland `lock` — it rejects later same-class members. Compile to `set always` on the match and `barred` on other classes that can land on the workspace. Runtime still ejects, because `auto_group` can still swallow.

## Companions

`spawn` on a member: open the companion when the first match maps; close it when the last leaves. Example: `zen-gaming-media` beside the Dofus group.

## Bindings

Scene and member `bindings` tags are buffer-local. Which-key already filters `workspace › class › group › layout`. The groupbar is the active-member strip; the persistent bar is status, not a taskbar.

## Runtime (Lua)

```lua
Scene.active(ws)
Scene.realize(name)
Scene.tile(name, match)
```

One engine for both scenes:

- `gaming` — Dofus group + `zen-gaming-media` right
- `code` — `Kitty-Main` | `Proj-*` group + `zen-twilight` right

Mood reachability ("focus scene") is a different word. It is not this document.

## Inside engines (not config)

Hide: focus-dance, adjacency hops, ignored `window:` dispatch arg, settle/verify timers.

## Example

```lua
gaming = {
  layout_opts = { dwindle = { default_split_ratio = 0.67 } },
  members = {
    { match = { class = "Dofus.x64" }, group = true, spawn = "zen-gaming-media" },
    { match = { class = "zen-gaming-media" } },
  },
  bindings = { "gaming" },
},
code = {
  layout_opts = { dwindle = { default_split_ratio = 0.67 } },
  members = {
    { match = { class = "Kitty-Main|Proj-*" }, group = true },
    { match = { class = "zen-twilight" } },
  },
  bindings = { "code" },
},
```
