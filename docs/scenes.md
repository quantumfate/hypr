# Scenes

Declarative window manager. The document is the interface. Engines execute it.

## A scene is geometry only

A scene says how windows sit on one named workspace. It does **not** decide
whether that workspace exists, which binding trees are loaded, what runs in the
background, or how notifications route. A **mode** declares those, and this
repo is one of its executors.

The engine as a whole is `hyprfocus`; its cross-repo architecture lives in the
sibling `system-config` repo. Read it before changing what a scene is
responsible for — the common mistake is to grow a scene into a mode.

| Question                      | Answered by                           |
| ----------------------------- | ------------------------------------- |
| does this workspace exist?    | mode                                  |
| how are its windows arranged? | scene                                 |
| which binds are loaded here?  | mode, or a scene that carries its own |
| what runs in the background?  | mode                                  |

## Declaration

Config is the only declaration. No per-feature merge, `barred`, or `spawn` code.

Scenes are keyed by workspace `default_name` (`code`, `dofus`). Workspace id is host data in `workspace_specs`.

## Mode → workspace → scene layout

Every focus mode admits exactly the workspaces it needs, and only while it
runs. Special workspaces are retired (LEO-265/330); every scene that used to
live in `special:*` is now an ordinary workspace admitted per mode.

### Gaming

| Monitor   | Workspace         | Scene       | Split                      |
| --------- | ----------------- | ----------- | -------------------------- |
| primary   | `dofus`           | dofus       | 0.67 group / 0.33 browser  |
| primary   | `pokemon`         | pokemon     | 0.30 emulator / 0.65 media |
| primary   | `steam-games`     | steam-games | 1.00 fullscreen            |
| primary   | `proton`          | proton      | 0.50 mail / 0.50 pass      |
| secondary | `communication`   | comms       | 0.50 signal / 0.50 vesktop |
| secondary | `lutris`          | lutris      | 1.00 fullscreen            |
| secondary | `steam`           | steam       | 1.00 fullscreen            |
| secondary | `media`           | media       | 1.00 fullscreen            |
| secondary | `ankama-launcher` | (launch)    | 1.00 fullscreen            |

### Work

| Monitor   | Workspace         | Scene           | Split                       |
| --------- | ----------------- | --------------- | --------------------------- |
| primary   | `code`            | code            | 0.67 group / 0.33 browser   |
| primary   | `proton`          | proton          | 0.50 mail / 0.50 pass       |
| secondary | `obsidian-linear` | obsidian-linear | 0.50 obsidian / 0.50 linear |
| secondary | `logs`            | logs            | tmux-managed                |

### Study

| Monitor   | Workspace         | Scene           | Split                       |
| --------- | ----------------- | --------------- | --------------------------- |
| primary   | `code`            | code            | 0.67 group / 0.33 browser   |
| primary   | `proton`          | proton          | 0.50 mail / 0.50 pass       |
| secondary | `obsidian-linear` | obsidian-linear | 0.50 obsidian / 0.50 linear |

_Neutral_ is the resting mode; its workspace set is the full base.

Source of truth: `$XDG_STATE_HOME` scenes store (`scenes.json`). Lua consumes that document and seeds it on first run from `hypr/scene/defaults.lua`; the host fork is gone. The full editor contract (members, gaps, layout options) is LEO-239 and widens this document in place — do not start a second one.

## Split

The two-tile split is `layout_opts.dwindle.default_split_ratio` (`0.67`). That is what the user declares. A resize loop may correct drift internally; it is not the config language.

## Group

`group = true` on a member match set means one Hyprland group containing **only** those classes. Fold matching windows in; eject foreigners.

Do not use Hyprland `lock` — it rejects later same-class members. `hypr/scene/compile.lua` emits `set always` on the match and the guard on every other class that can land on the workspace. Runtime still ejects, because `auto_group` can still swallow.

Grouping is decided **once**, by the scene. Do not also write a `group` key in `windowrules.lua` for a class a block names; the compiler emits it and the runtime holds it.

The runtime never remembers which group is the block's. It derives it each pass: whichever group already holds the most of the block's tiles wins, and the rest fold into it. A remembered set cannot recover from `auto_group` splitting a block in two — it declares one half authoritative and fights the other forever.

Joining goes through `HL.Group:add`, which names the window it acts on. There is no adjacency search and no `moveintogroup` hop chain.

## Guard

`guard` on a non-group member: `barred` (default) keeps `auto_group` from swallowing it; `deny` also refuses a deliberate toggle, for a tile whose job is to be a fixed region beside a group.

`barred` at scene level lists classes that legitimately open on the workspace without belonging to any block — a game, a launcher overlay.

## Collect

`collect = true` on a member: a window that drifted to another workspace comes home. Off by default.

Ownership is earned by **mapping into the scene**, never by matching its classes — otherwise a terminal you deliberately moved elsewhere gets dragged back. A dormant scene (no member home) collects nothing, and a member parked on a special workspace is hidden on purpose.

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

One engine for all scenes:

- `dofus` — Dofus group + `zen-gaming-media` right
- `code` — `Kitty-Main` | `Proj-*` group + `zen-twilight` right
- `pokemon` — RetroArch emulator + flanking streaming browsers
- `obsidian-linear` — Obsidian + Linear side by side
- `proton` — Proton Mail + Proton Pass companion

Mood reachability ("focus scene") is a different word. It is not this document.

## Editor contract (LEO-239)

A workspace scene is edited through the same document the engine reads. The
editor surface may be a Quickshell panel, a hand edit, or a migration script;
the contract below is the schema it edits against.

### Scene fields

| Field        | Type                  | Meaning                                                                         |
| ------------ | --------------------- | ------------------------------------------------------------------------------- |
| `name`       | string                | workspace `default_name` (`code`, `dofus`). This is the key; ids are host data. |
| `blocks`     | Block[]               | the ordered tiles of the scene                                                  |
| `barred`     | string[]              | classes that may land here but must never join a group                          |
| `strays`     | `"slot"` \| `"float"` | how unmatched tiled windows are treated                                         |
| `solo_frame` | boolean?              | opt-out of the lone-tile decorative frame                                       |
| `bindings`   | string[]?             | binding trees this scene admits while active                                    |
| `moods`      | string[]?             | mood tags that select this scene when the mode does not                         |
| `machines`   | table?                | machine-specific geometry overrides                                             |

### Block fields

| Field     | Type                                  | Meaning                                              |
| --------- | ------------------------------------- | ---------------------------------------------------- |
| `classes` | string[]                              | literal class or Lua pattern, in window-rule grammar |
| `group`   | boolean                               | one Hyprland group containing only these classes     |
| `order`   | integer                               | left-to-right tile sequence                          |
| `share`   | number?                               | fraction of the tiled span this block holds          |
| `collect` | boolean                               | bring drifted members back to this workspace         |
| `guard`   | `"barred"` \| `"deny"`                | how a non-group block resists grouping               |
| `spawn`   | `{ class: string, command: string }`? | companion window lifecycle                           |

### Workspace selects its scene

A workspace's scene is its `default_name` entry in the store. The host's
`workspace_specs` bind ids and monitors; the scene document binds behavior to
the name. `Scene.active(ws)` returns the scene name for a workspace if one
exists, and `Scene.realize(name)` runs its layout.

There is no per-workspace indirection: `dofus` is both the workspace name and
the scene name. A mode admits the workspace; the workspace admits the scene.
This keeps the editor path single: changing the `dofus` scene changes the
dofus workspace everywhere.

### Dofus is a workspace scene

The `dofus` scene uses the same fields as every other scene. Its Dofus block
has `group = true` and a `zen-gaming-media` companion with `guard = "deny"`;
`barred` lists Steam and Ankama launcher classes. Nothing in the schema is
gaming-specific — the same contract serves `code`, `pokemon`, or any future
workspace.

### Machine-specific geometry

Geometry is fingerprint-based: a scene declares ratios (`share`) and flags
(`solo_frame`, `strays`), and the engine applies them within the monitor's work
area. Machine profiles refine only host data:

- `quantum-desktop` — ultrawide layouts may use dedicated regions, intentional
  gaps, and visible wallpaper. `workspace_specs` assigns the scene to a wide
  monitor; the engine places tiles across the full work area.
- `quantum-laptop` — smaller displays must fit or float windows without
  clipping, overlap, or desktop-sized geometry. A scene whose blocks would clip
  can set `strays = "float"` so unmatched windows float rather than resize the
  declared split.

The scene document never names pixels or monitor models. Machine-specific pixel
values live in `workspace_specs` and `conf/hosts/*.lua`, edited separately from
the scene contract.

### Bindings and moods

A scene may carry `bindings`: buffer-local trees that exist while the scene is
active, the same way a Neovim buffer brings its own mappings. These are admitted
in addition to the mode's bindings, not instead of them, and are withdrawn when
the user leaves the scene's workspace.

`moods` is a list of mood tags the scene matches. The active mood can therefore
select a scene without naming it directly in the mode declaration; the editor
uses this to preview or override a scene for a given mood.

## The scene is the layout

Registered with `hl.layout.register`: `recalculate(ctx)` receives the work area
and the tiled targets, and places each one. The compositor asks; the scene
answers.

This replaces a corrective loop that measured another layout's output and
dispatched fixes at it. What the inversion removes, structurally: settle and
verify timers, geometry digests, turn budgets, the focus-dance (positioning
dispatchers act on the focused window, so every correction had to steal and
restore focus), ordering via `movewindow` (at a monitor edge it moves the window
to the next monitor), and the event subscriptions an engine has to guess
at. Single-tile gaps and per-workspace layout options become branches in the
same function.

Grouping stays separate and declarative: a group is a compositor concept and
arrives at the layout as one target.

The engine's corrections are gated on the workspace running the scene layout:
the same declaration on dwindle or master — where another layout owns the
geometry — asks for nothing (`model.intent` checks `tiled_layout`; cycling
back re-realizes through the layout-cycle bind). The compiled group rules stay
layout-independent; the gate is the engine's, not the rules'.

## Engine layers

| File                      | Owns                                               |
| ------------------------- | -------------------------------------------------- |
| `hypr/scene/spec.lua`     | the declaration, normalized                        |
| `hypr/scene/compile.lua`  | declaration → static window rules, at config load  |
| `hypr/scene/snapshot.lua` | the compositor's state, flattened to plain tables  |
| `hypr/scene/registry.lua` | which windows a scene owns                         |
| `hypr/scene/model.lua`    | snapshot + spec → the one correction wanted (pure) |
| `hypr/scene/actuator.lua` | one correction → compositor calls                  |
| `hypr/scene/schedule.lua` | when acting is allowed at all                      |
| `hypr/events/scene.lua`   | wiring to Hyprland events                          |

`model.lua` touches no `hl` and no timers, so every arrangement decision is testable with fixtures — `tests/scene_model_spec.lua`. `tests/scene_spec.lua` covers the rest end to end.

## The three scheduling rules

1. **Only the visible scene is corrected.** Reaching a hidden workspace means focusing a window there, which carries the user with it and fires `workspace.active`, which arms the next scene. A scene behind the user is realized when they come back.
2. **Never act on a single reading.** Hyprland animates every correction; geometry sampled once is mid-flight. A pass acts only when two reads agree.
3. **Never repeat a correction that changed nothing.** Otherwise the pass oscillates. It ends instead, and the user's arrangement stands.

Turn-bounded on top of all three.

## Intent priority

`collect → evict → join → reorder → resize`. Causal, not cosmetic: collection decides which windows are in play, grouping decides how many tiles there are, and only then can order and share mean anything — both are measured in tiles.

One intent per pass, never a plan: each correction changes the geometry the next decision depends on.

## Inside engines (not config)

Hide: focus-dance, settle/verify timers, the `follow = false` on a collecting move, group-object vs dispatcher.

## Example

```lua
dofus = {
  blocks = {
    { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true,
      spawn = { class = "zen-gaming-media", command = "zen-twilight -P GamingMedia --name zen-gaming-media" } },
    { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
  },
  barred = { "steam_app_default", "steam_app_\\d+", "Ankama Launcher" },
  strays = "float",
  moods = { "gaming" },
},
code = {
  blocks = {
    { classes = { "Kitty-Main", "Proj-[A-Za-z0-9_-]+" }, group = true, order = 1, share = 0.67 },
    { classes = { "zen-twilight", "firefox-developer-edition" }, order = 2, share = 0.33 },
  },
  strays = "float",
  moods = { "work", "study" },
},
["obsidian-linear"] = {
  blocks = {
    { classes = { "md.obsidian.Obsidian" }, order = 1, share = 0.5 },
    { classes = { "linear" }, order = 2, share = 0.5 },
  },
  strays = "float",
  moods = { "work", "study" },
},
```
