# Agent notes

This repo is a Hyprland environment. Compositor logic lives in `hypr/**.lua`; the helpers the desk spawns live in `bin/` (see [bin/Readme.md](bin/Readme.md)). Delivery is dual (Nix + Ansible) — see `ARCHITECTURE.md`.

## Read order

New to the repo, read in this order — each layer points at the next:

1. [README.md](README.md) — what this is, how to install it.
2. [ARCHITECTURE.md](ARCHITECTURE.md) — the packaging model: dual delivery (Nix + Ansible), repo scope, ecosystem coupling, release channels.
3. [docs/scenes.md](docs/scenes.md) — the scene contract (below is the enforcement; this is the reasoning).
4. [bin/Readme.md](bin/Readme.md) — the shell helpers the desktop spawns, and the state/IPC seams to the quickshell sibling repo.
5. Cross-repo: `system-config/docs/hyprfocus.md` (the full `hyprfocus` engine) and quickshell `ARCHITECTURE.md` (shared state + IPC). This repo is one executor of declarations those repos also execute.

## Repo map

| Path                     | Owns                                                                 |
| ------------------------ | -------------------------------------------------------------------- |
| `hypr/`                  | the running compositor logic (Lua); scene engine under `hypr/scene/` |
| `*.conf`                 | hypr\* daemon configs (hypridle, hyprlock, hyprpaper, …)             |
| `bin/`                   | the `,name.sh` helpers binds and quickshell spawn                    |
| `conf/`                  | host-specific data (`workspace_specs`, temporary `scenes` fork)      |
| `etc/`                   | generated/contract data (`scene-managed.json`, systemd targets)      |
| `session/`               | uwsm env, systemd user units, greeter fragment                       |
| `flake.nix` / `ansible/` | the two delivery paths (kept in sync, both first-class)              |
| `tests/`                 | Lua specs (`tests/run.lua` + `hl_stub.lua`) and shell-helper tests   |

## Contract

Scenes are a **document**. Engines execute it. Do not add per-feature merge, `barred`, or spawn code.

Read [docs/scenes.md](docs/scenes.md) before touching window placement, grouping, or workspace layout.

**A scene is geometry only.** It says how windows sit on one named workspace. It does not decide whether that workspace exists, which binding trees are loaded, or what may run — a **mode** declares those, and the compositor is one of its executors. The engine as a whole is `hyprfocus`; the cross-repo architecture lives in the sibling `system-config/docs/hyprfocus.md`.

- Keyed by workspace `default_name` (`code`, `gaming`). Workspace ids are host data in `workspace_specs`.
- The scene **is** the layout (`hl.layout.register`), not a corrector running on top of one. Order is the order boxes are placed; share is a fraction of `ctx.area`. Neither is a dispatched correction.
- `group = true` on a member match = one Hyprland group of **only those classes**. Fold matches in; eject foreigners. Never `lock` (it rejects later same-class members).
- Derive a block's group each pass — the group already holding the most of its tiles wins. Do not remember a membership set: it cannot recover from `auto_group` splitting a block in two.
- Companion windows: member `spawn`. Binding trees are a declared resource, admitted by a mode or a scene — not filtered after the fact.
- Mode reachability is a different word. Do not merge it into scene geometry.

Lua surface (`hypr/events/scene.lua`; the engine itself is layered under `hypr/scene/`):

```lua
Scene.active(ws)           -- name or nil
Scene.realize(name)
Scene.tile(name, match)    -- first tile of that match, or nil
```

Long-term store is `$XDG_STATE_HOME` `scenes.json` (schema in sibling `quickshell`). The host files' `scenes` table (`conf/hosts/`) is a temporary host fork.

## Hyprland primitives (do not rediscover)

The Lua API has object and handle interfaces that make the dispatcher workarounds unnecessary. Reach for these first.

- **`hl.layout.register(name, provider)`** — `recalculate(ctx)` gets `ctx.area` and `ctx.targets`, each with `target:place(box)`. This is how geometry is decided. The compositor calls it on every change, so no event subscription is needed and none should be added.
- **`HL.Group:add(window)` / `:remove(window)`** — window-targeted grouping. No adjacency, no hops.
- **`set_enabled`** on the handles returned by `hl.bind`, `hl.window_rule`, `hl.workspace_rule` and `hl.layer_rule` — rules and binds are admitted and withdrawn at runtime, with no config reload.
- `auto_group` can still swallow foreigners; runtime eject is required even after compiling `set always` / `barred`.

Only if none of the above fits:

- Positioning **dispatchers** act on the **focused** window, so they need a focus-dance (focus → dispatch → restore), which makes geometry depend on focus. Avoid.
- `movewindow` at a monitor edge **moves the window to the adjacent monitor**. It is not usable for ordering.
- A corrective loop over another layout cannot be made stable: it must guess which events matter, measure animated geometry, and steal focus to act. That approach was tried and retired; do not reintroduce it.

## Commands

```sh
just check                         # fmt + tests + luacheck (the gate)
just test                          # lua tests/run.lua + the shell helpers' tests
TEST_SPECS='tests/scene_model_spec.lua tests/scene_spec.lua' lua tests/run.lua
just fmt
just units                         # regenerate etc/systemd targets the contract names
```

Tests use `tests/hl_stub.lua`. `require` of event modules self-wires; specs `fresh()` the stub and drain timers. Do not assume a live compositor.

## Style

- Match neighboring Lua: complete-sentence `--` comments, no new comment noise.
- `stylua` + `luacheck` must stay clean.
- Do not mention issue trackers in docs or commit messages.
- Do not invent a second scene table, a second 0.67, or a Dofus-only group guard.
- Grouping is declared once, by the scene, and compiled to rules. Do not hand-write a `group` key for a class a block already names.
