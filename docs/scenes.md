# Scenes

Declarative window manager. The document is the interface. Engines execute it.

## What a scene owns

The target model is [desktop-model.md](desktop-model.md) and the window lifecycle contract is [lifecycle.md](lifecycle.md); this document
describes the scene engine as it runs today and is being brought in line with
it. Where they disagree, desktop-model.md is the intent.

A scene is a plug-in unit mapped to one workspace. It owns which windows
belong there, how they sit (it is the layout), what it brings up and tears
down, how it reacts when windows open or close, and its mode-scoped binding
tree. A **focus mode** decides which scenes are active, on which monitor, the
theme, and calls their bring-up and teardown. A mode does not arrange windows
and does not own binding trees.

The engine as a whole is `hyprfocus`; its cross-repo architecture lives in the
sibling `system-config` repo.

| Question                          | Answered by                        |
| --------------------------------- | ---------------------------------- |
| is this scene/workspace active?   | mode                               |
| on which monitor?                 | mode (monitor roles are host data) |
| which windows belong, how placed? | scene                              |
| what happens on open/close?       | scene                              |
| mode-scoped binds                 | scene (merged across a mode)       |
| contextual binds                  | focused window, never the scene    |
| theme                             | mode                               |

Today's gap: modes still admit workspaces by name rather than scene sets, and
scenes have no bring-up/teardown or window-state behaviour.

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

`group = true` on a member match set means one Hyprland group containing **only** those classes. The declaration is compiled to static rules; join and eviction are **not executed today**.

`hypr/scene/compile.lua` emits `set always` on the match and the `barred`/`deny` guard on every other class that can land on the workspace, at config load. Do not use Hyprland `lock` — it rejects later same-class members.

The corrective engine that used to derive a block's dominant group each pass, fold stragglers into it, and eject foreigners `auto_group` swallowed (`schedule.lua` + `model.lua` + `actuator.lua`, `HL.Group:add`/`:remove`) is retired (LEO-261). Group membership becomes **open-time rules**, scoped to the scene's workspace by tags (LEO-354); until that lands, a block that `auto_group` splits, or a foreigner it swallows, is not corrected.

**Grouping is scoped to the scene's own workspace, not the class globally** ([lifecycle.md](lifecycle.md) D2). A class shared by two scenes — `Kitty-Main` in `code`, say, opened again on an unrelated workspace — must group only where its scene runs. `compile.lua` compiles each block class to two rules: first a tagging rule, matched on `class` _and_ `onworkspace = "name:<scene>"`, that stamps the Hyprland tags `scene:<name>` and `block:<name>/<order>`; then the group rule itself, matched on the `block:<name>/<order>` tag rather than the bare class. A window of that class elsewhere never receives the tag, so it never reaches the group rule. `onworkspace` is Hyprland's window-rule _matcher_ for "currently on this workspace" — plain `workspace` in a `match` table is the _effect_ that assigns a window to a workspace, not a matcher, and would silently match nothing.

Grouping is decided **once**, by the scene. Do not also write a `group` key in `windowrules.lua` for a class a block names; the compiler emits it.

## Guard

`guard` on a non-group member: `barred` (default) keeps `auto_group` from swallowing it; `deny` also refuses a deliberate toggle, for a tile whose job is to be a fixed region beside a group.

`barred` at scene level lists classes that legitimately open on the workspace without belonging to any block — a game, a launcher overlay. Scope is the same as `Group` above: `compile.lua` tags a barred class only when it opens on the scene's own workspace (`scene:<name>`), then bars on that tag — so a barred class does not reach across scenes either.

## Collect

`collect = true` on a member: declares that a window which drifted to another workspace should come home. **Not executed today** — the corrective engine that read this flag (`schedule.lua` + `model.lua` + `actuator.lua`) is retired (LEO-261). Collection becomes a **route decision** instead (LEO-353): the routing step sends a member's window to its scene's workspace at open/move time, rather than a pass that watches for drift and moves it back.

Ownership was earned by **mapping into the scene**, never by matching its classes — otherwise a terminal you deliberately moved elsewhere gets dragged back. A dormant scene (no member home) collected nothing, and a member parked on a special workspace was hidden on purpose. LEO-353's route decision keeps that distinction.

## Companions

`spawn` on a member: open the companion when the first match maps; close it when the last leaves. Example: `zen-gaming-media` beside the Dofus group.

## Bindings

Scene and member `bindings` tags are buffer-local. Which-key already filters `workspace › class › group › layout`. The groupbar is the active-member strip; the persistent bar is status, not a taskbar.

## Runtime (Lua)

```lua
Scene.active(ws)
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

### Strays: `"slot"` executes, `"float"` centers

`strays` used to be parsed and ignored — a `"float"` scene's unmatched windows
still ate into the declared split. It is executed now, in `hypr/scene/layout.lua`:

- `"slot"` (default): a stray divides whatever the declared blocks leave, same
  as before.
- `"float"`: strays are pulled out before shares are computed at all, so the
  declared blocks keep exactly their geometry no matter what else is open —
  the point of the flag for a fixed capture region.

A Hyprland layout provider has no non-dispatch primitive to toggle a window's
`floating` field from `recalculate` — `HL.LayoutTarget` offers only `place`
and `set_box`, and the dispatcher path (`hl.dispatch.window.float`) acts on
the _focused_ window, which this engine avoids on principle (see "Hyprland
primitives" in `AGENTS.md`). So a floated stray still gets exactly one box —
centered over the declared layout's area at half its size, each additional
floated stray nudged so they do not exactly overlap — rather than truly
floating. `layout.float_box` computes it; `layout.stack` (below) is unrelated.

### Every window of a block gets placed

A non-group block used to place only its first tile; the rest were silently
dropped. Now the block's declared `share` is split vertically among all of
its windows: equal heights, `gaps_in` between them, the last one taking
whatever rounding left — the same "last slot takes the remainder" rule the
horizontal split already used. A `group = true` block is unaffected: its
members still collapse to one Hyprland group occupying one box.

### Ambiguous classes: first-match, not silent

`spec.block_for` is first-match by declaration order — deterministic, but a
class declared in two blocks of the same scene means the second block can
never fill from that class. `spec.block_candidates(spec, class)` returns
every matching block so a caller can see and log the ambiguity (the follow-up
issue wires this to `identify.ambiguous`); `spec.ambiguous_classes(spec)` is a
static validator over the declaration itself, listing every class entry
claimed by more than one block. The shipped defaults have exactly one:
`zen-gaming-media` in the `pokemon` scene's flanking media blocks (by design —
the same class fills both the left and right slot).

### Workspace selects its scene

A workspace's scene is its `default_name` entry in the store. The host's
`workspace_specs` bind ids and monitors; the scene document binds behavior to
the name. `Scene.active(ws)` returns the scene name for a workspace if one
exists; the layout runs from the registered provider, not a call this module
makes.

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

This replaced a corrective loop that measured another layout's output and
dispatched fixes at it (`hypr/scene/schedule.lua` + `model.lua` +
`actuator.lua`, retired in LEO-261 — see "Hyprland primitives" in
`AGENTS.md`). Arrange is now the layout provider's alone: it never dispatches,
and needs no event subscription, settle/verify timers, turn budget, or
focus-dance. Single-tile gaps and per-workspace layout options become
branches in the same function.

Grouping stays separate and declarative: a group is a compositor concept and
arrives at the layout as one target.

The layout only runs on the workspace running the scene layout: the same
declaration on dwindle or master — where another layout owns the geometry —
is inert there, because nothing asks the scene layout provider to place
anything on a workspace it does not own. The compiled group rules stay
layout-independent.

## Engine layers

| File                     | Owns                                              |
| ------------------------ | ------------------------------------------------- |
| `hypr/scene/spec.lua`    | the declaration, normalized                       |
| `hypr/scene/compile.lua` | declaration → static window rules, at config load |
| `hypr/events/scene.lua`  | wiring to Hyprland events                         |

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
