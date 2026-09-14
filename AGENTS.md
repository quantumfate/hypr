# Agent notes

This repo is a Hyprland environment. Compositor logic lives in `hypr/**.lua`. Delivery is dual (Nix + Ansible) — see `ARCHITECTURE.md`.

## Contract

Scenes are a **document**. Engines execute it. Do not add per-feature merge, `barred`, or spawn code.

Read [docs/scenes.md](docs/scenes.md) before touching window placement, grouping, or workspace layout.

- Keyed by workspace `default_name` (`code`, `gaming`). Workspace ids are host data in `workspace_specs`.
- Two-tile ratio is `layout_opts.dwindle.default_split_ratio` (`0.67`). Resize loops are internal correctors, not config.
- `group = true` on a member match = one Hyprland group of **only those classes**. Fold matches in; eject foreigners. Never `lock` (it rejects later same-class members).
- Companion windows: member `spawn`. Buffer binds: `bindings` tags (which-key already filters workspace › class › group › layout).
- Mood reachability ("focus scene") is a different word. Do not merge it into scene geometry.

Lua surface (`hypr/events/scene.lua`):

```lua
Scene.active(ws)           -- name or nil
Scene.realize(name)
Scene.tile(name, match)    -- first tile of that match, or nil
```

Long-term store is `$XDG_STATE_HOME` `scenes.json` (schema in sibling `quickshell`). `hyprland.lua`'s `scenes` table is a temporary host fork.

## Hyprland primitives (do not rediscover)

- Dispatchers act on the **focused** window. The `window:` argument is ignored.
- `moveintogroup` needs the group **adjacent** on that axis.
- Correct with a focus-dance (focus → dispatch → restore). Hide that inside engines.
- `auto_group` can still swallow foreigners; runtime eject is required even after compiling `set always` / `barred`.

## Commands

```
just check                         # fmt + tests + luacheck (the gate)
just test                          # lua tests/run.lua
TEST_SPECS=tests/scene_spec.lua lua tests/run.lua
just fmt
```

Tests use `tests/hl_stub.lua`. `require` of event modules self-wires; specs `fresh()` the stub and drain timers. Do not assume a live compositor.

## Style

- Match neighboring Lua: complete-sentence `--` comments, no new comment noise.
- `stylua` + `luacheck` must stay clean.
- Do not mention issue trackers in docs or commit messages.
- Do not invent a second scene table, a second 0.67, or a Dofus-only group guard.
