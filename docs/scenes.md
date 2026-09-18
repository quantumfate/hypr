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

Today's gap: scenes have no bring-up/teardown or window-state behaviour yet.

## Declaration

Config is the only declaration. No per-feature merge, `barred`, or `spawn` code.

Scenes are keyed by workspace `default_name` (`code`, `dofus`). Workspace id is host data in `workspace_specs`.

## Scene sets: mode → scene → monitor

A mode names its active scene set outright in the hyprfocus declaration
(`modes.<id>.scenes: [{ name, monitor }]`, schema version 3). The workspaces a
mode admits are derived from that set: a scene's name is its workspace's
`default_name`. `monitor` is a host monitor **role** (`primary`, `secondary`),
never an output name; `conf/hosts/*.lua` maps roles to outputs.

Placement on mode entry (`hypr/hyprfocus/init.lua` `apply`): validate → binding
trees → restore → hold → withdraw → place. Placing moves each scene's workspace
to its role's output (`admit/scene_monitor`). The mode's role wins over the
host file's `workspace_specs[].monitor`, which is only the load-time default. A
role whose output is not connected falls back to primary
(`reason=monitor_missing`); `monitor.added` re-places the last applied desk, so
the scene moves back when the monitor returns. Every `workspace.active` also
re-places the applied desk quietly (only moves are logged), so a scene workspace
created after the apply, or before its output existed, still lands on its role's
output.

### Ignored monitors

A host may list `ignored_monitors` (`conf/hosts/quantum-desktop.lua`:
`{ "HDMI-A-1" }`, the case panel). An ignored output is connected but never a
target:

- `output_for` never resolves a role to it, so no scene is placed there.
- Shelves open on the primary when the focused monitor is ignored.
- `mod+h/l` never crosses onto it (`nav.usable_monitors`).
- The workspace row and `mod+TAB` act on the primary when focus is on it.
- A window that opens on, or moves to, a plain workspace of an ignored monitor
  moves (address-targeted) to the primary's active workspace. A special shown
  on an ignored monitor is shown on the primary instead. Both are logged as
  `admit/ignored_monitor` (`hypr/events/scene.lua`, pure decision
  `nav.off_ignored`).

Hyprland still keeps one workspace on the ignored output; nothing else goes
there.

### Reachability invariant

After every mode apply (`hypr/hyprfocus/init.lua`), every window must be on an
admitted workspace, on a shelf or another unmanaged workspace, or held with a
recorded origin the mode does not admit. `hold.unreachable` (pure) names each
violation, logged as `admit/unreachable` with `reason`:

| Reason         | Meaning                                                         |
| -------------- | --------------------------------------------------------------- |
| `withdrawn`    | on a managed workspace the mode withdrew                        |
| `no_origin`    | held with no record; moved to the primary's active workspace    |
| `not_restored` | held from a workspace the mode admits (restore should have run) |

The check projects the moves the apply dispatched over what the compositor
reports, because a dispatched move has not landed yet.

`apply` never nests. Its own moves raise `window.move_to_workspace`, which the
watcher converges on; a nested apply read the held-window record before the
outer one wrote it, and the outer write dropped the inner entries. That left
windows held with no origin. `apply` now refuses while it runs, and the watcher
skips its tick. `hold.hold` also overwrites a stale record for a window that
still stands on the workspace (reused address) instead of skipping it, and
prunes records for dead addresses.

### Workspace cycling

`mod+TAB` / `mod+shift+TAB` cycle the applied mode's scenes on the focused
monitor, in mode order, wrapping (`nav.cycle_workspace`). Specials and
unmanaged workspaces are never targets; from one of them the cycle enters at
the first (or last) scene.

### Validation (refuses the whole mode)

`resolve.validate` (Lua) and `validate` (`bin/,hyprfocus`) are pure and agree
through `tests/fixtures/hyprfocus/resolver`. A refusal is an
`admit/mode_refused` record carrying `mode`, `refusal` (token), `reason`
(token first), and for conflicts `class` and the two `scenes`. Nothing is
applied and the pointer is not written.

| Token             | Rule                                                             |
| ----------------- | ---------------------------------------------------------------- |
| `missing_scenes`  | mode has no `scenes` list (a pre-v3 store)                       |
| `hidden_required` | `neutral` is not `hidden: true`                                  |
| `unknown_scene`   | `scenes[].name` not in `base.scenes`                             |
| `unknown_monitor` | `monitor` is not a host role                                     |
| `duplicate_scene` | a scene listed twice in one mode                                 |
| `class_conflict`  | two listed scenes share a block `classes` string (textual match) |
| `scene_required`  | a `requires` edge names a `scene:` the mode does not list        |

`scene:` references in `requires`/`wants` are checked, never added: a scene set
is explicit. `barred` and `spawn.class` are not claims. Overlapping regexes
(`steam_app` vs `steam_app_\d+`) are not detected.

`dofus` and `pokemon` both use `zen-gaming-media`; grouping and block matching
are already scoped to a window's own workspace (`hypr/scene/grouping.lua`),
so this alone is not a conflict. What pokemon's own two media-browser blocks
need — telling its **left** `zen-gaming-media` window apart from its
**right** one — is identity stamped at launch (LEO-364): each block declares
`classes = { "zen-gaming-media" }` plus a distinct `slot` (`pokemon/chat`,
`pokemon/stream`); `hypr/scene/identify.lua` stamps `slot:<slot>` on the
first still-unslotted live window of that class on the workspace, in block
declaration order, once per `window.open`/`window.move_to_workspace`.

### Gaming

| Monitor   | Workspace     | Scene       | Split                      |
| --------- | ------------- | ----------- | -------------------------- |
| primary   | `dofus`       | dofus       | 0.67 group / 0.33 browser  |
| primary   | `pokemon`     | pokemon     | 0.30 emulator / 0.70 media |
| primary   | `steam-games` | steam-games | 1.00 fullscreen            |
| primary   | `proton`      | proton      | 0.50 mail / 0.50 pass      |
| secondary | `media`       | media       | 1.00 fullscreen            |

Signal, Vesktop, Steam, Lutris and the Ankama Launcher are shelves, not scenes
([shelves.md](shelves.md)).

### Work

| Monitor   | Workspace         | Scene           | Split                       |
| --------- | ----------------- | --------------- | --------------------------- |
| primary   | `code`            | code            | 0.67 group / 0.33 browser   |
| primary   | `obsidian-linear` | obsidian-linear | 0.50 obsidian / 0.50 linear |
| primary   | `proton`          | proton          | 0.50 mail / 0.50 pass       |
| secondary | `logs`            | logs            | tmux-managed                |

### Study

| Monitor   | Workspace         | Scene           | Split                       |
| --------- | ----------------- | --------------- | --------------------------- |
| primary   | `code`            | code            | 0.67 group / 0.33 browser   |
| secondary | `obsidian-linear` | obsidian-linear | 0.50 obsidian / 0.50 linear |
| primary   | `proton`          | proton          | 0.50 mail / 0.50 pass       |

### Neutral (hidden)

The recovery fallback, reached from a submap and never listed as a peer mode
(CLI `modes`, shell pickers skip `hidden`).

| Monitor   | Workspace | Scene  |
| --------- | --------- | ------ |
| primary   | `code`    | code   |
| primary   | `proton`  | proton |
| secondary | `logs`    | logs   |

`creative` and `misc` are retired: no host, mode or scene declares them.

### Source of truth

The declaration's `base.scenes` (`$QF_STORE/hyprfocus.json`) is the only scene table. `hypr/scene/spec.lua` normalizes it for geometry, compile and companions; `hypr/hyprfocus/` reads the same entries for scene bindings and mode validation. The shipped seed is quickshell `assets/hyprfocus.default.json`, installed with `,hyprfocus seed`.

- **Missing or unreadable declaration:** the scene engine is inert (no placement, no grouping), emits `admit/scenes_missing` and sends a notification.
- **Legacy `scenes.json`:** folded once on load by `hypr/scene/migrate.lua`. A scene still equal to the retired seed (compared by fingerprint) is dropped; an edited or unknown scene overwrites its `base.scenes` entry. The file is then renamed to `scenes.json.migrated` and `admit/scenes_migrated` is logged.
- `tests/hyprfocus_declaration_spec.lua` pins every `base.scenes` key to a `default_name` on every host and fails if a second scene table reader returns.

The full editor contract (members, gaps, layout options) widens this document in place — do not start a second one.

## Split

The two-tile split is a block's declared `share` (fraction of the workspace's tiled span, see `hypr/scene/spec.lua`). That is what the user declares. A resize loop may correct drift internally; it is not the config language.

## Group

`group = true` on a member match set means one Hyprland group containing **only** those classes.

**Timing fact, spiked live (LEO-369):** a static rule cannot express this. A window rule chained off another rule's _effect_ — tag on `class` + `workspace` inside `match`, then group on that tag — never fires: the tagging rule's own `workspace` match is not true yet when the window opens, so its tag effect lands _after_ open, and a rule matched on that tag never sees a window that already satisfies it. This is exactly what `compile.lua` used to emit, so no scene block ever grouped from it, and the `barred`/`deny` guard chained the same way never fired either. `match.workspace` tests where the window already is; it is not a promise about when a load-time rule's effects land relative to open.

Grouping is decided at **runtime** instead, once per `window.open`/`window.move_to_workspace`, by `hypr/scene/grouping.lua` (pure: given a landed window, the scene spec and the live windows, it returns `seed` / `join` / `eject` / `none`) and its executor in `hypr/events/scene.lua`, through the live `HL.Group` object interface the spike verified: `hl.dispatch(hl.dsp.group.toggle({ window = "address:"..a }))` seeds a group without moving focus; `window.group:add(other)`/`:remove(other)` join and eject. No loop, no timer: one decision per event. Do not use Hyprland `lock` — it rejects later same-class members.

The group already holding the most of a block's tiles wins, derived fresh from the live windows on every event rather than remembered — the same rule the retired corrective engine (`schedule.lua` + `model.lua` + `actuator.lua`, LEO-261) used, so a block `auto_group` splits in two still converges on one. `auto_group` can still swallow a foreign window into a block's group; the executor ejects it on that foreigner's own open/move event.

**Grouping is scoped to the scene's own workspace, not the class globally** ([lifecycle.md](lifecycle.md) D2). A class shared by two scenes — `Kitty-Main` in `code`, say, opened again on an unrelated workspace — must group only where its scene runs. `hypr/scene/grouping.lua` reads a window's block through `spec_lib.block_for(spec, class)` where `spec` is the scene owning the window's own workspace, so a class matching a block on a different scene never enters that scene's grouping decision. `compile.lua` still compiles each block class to two **identity** tagging rules, matched on `class` _and_ `workspace = "name:<scene>"` inside `match`, stamping `scene:<name>` and `block:<name>/<order>` (one tag per rule: the `tag` effect takes a single tag, and `"+a +b"` stamps one tag literally named `a +b`) — useful identity for logging and other readers, but nothing chains a group rule off them any more, per the timing fact above.

Grouping is decided **once**, by the scene. Do not also write a `group` key in `windowrules.lua` for a class a block names; the runtime decision reads the declaration directly.

**Bar style and reservation:** Hyprland styles the groupbar globally (`group.groupbar` in `hypr/conf.lua`), not per group, so there is one slim style for every group: 18px tall, small readable text, the focused member's title inside, no gradients. Colours come from the active palette's roles, resolved and pushed by `hypr/themes/colors.lua#apply_colors` alongside the border colours — active/inactive/locked variants and their text colours re-apply on every palette or accent change, the same call that repaints borders. Hyprland reserves the bar's height **inside** the group's own box; the scene layout (`hypr/scene/layout.lua`) gives every member of a group the same box it would give one ungrouped tile of that block — it does not know about or add a second reservation for the bar, and neighbouring tiles never shift because of it. Verified live in the nested e2e (`tests/e2e/hq`): a 3-member group's window box and an ungrouped tile's box on the same monitor share the same outer rectangle; only the group's content is inset from the top by the bar's height.

### Group adapters

Which member `mod+j/k` steps to next/prev inside a group is a separate decision from membership: `hypr/scene/group_adapters.lua` is a registry keyed by class, each entry a pure `order(members, ctx) -> addresses`. Dofus orders by the team roster (`hypr/services/dofus/common.lua`'s `team()`); the default adapter orders by a stable join list the executor (`hypr/events/scene.lua`) updates on `seed`/`join`/`eject`/`window.close`, falling back to `group.members` order for a group nothing has recorded yet. `hypr/binds.lua`'s `focus_in_group` reads the adapter for the focused window's class, wraps at either end, and focuses by address — see [desktop-model.md](desktop-model.md#quickshell) for the bind-level contract and `tests/group_adapters_spec.lua` for the adapter specs.

## Guard

`guard` on a non-group member (`"barred"` default, `"deny"`) is declaration metadata; nothing reads it at runtime yet — the executor above only groups/ejects for `group = true` blocks. A non-group block's own class is simply never a group-block match, so it is never folded in or ejected by the executor either.

`barred` at scene level lists classes that legitimately open on the workspace without belonging to any block — a game, a launcher overlay. `compile.lua` still stamps a `barred:<name>` identity tag (scoped to the scene's own workspace, same as above) so a reader can recognize a deliberately unblocked class, but — per the timing fact above — no rule chains a group effect off it; a barred class reaching the block's group is instead the executor's `eject` case, the same path a plain foreigner takes.

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

| Field     | Type                                  | Meaning                                                                                                  |
| --------- | ------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `classes` | string[]                              | literal class or Lua pattern, in window-rule grammar                                                     |
| `group`   | boolean                               | one Hyprland group containing only these classes                                                         |
| `order`   | integer                               | left-to-right tile sequence                                                                              |
| `share`   | number?                               | fraction of the tiled span this block holds                                                              |
| `collect` | boolean                               | bring drifted members back to this workspace                                                             |
| `guard`   | `"barred"` \| `"deny"`                | how a non-group block resists grouping                                                                   |
| `spawn`   | `{ class: string, command: string }`? | companion window lifecycle                                                                               |
| `slot`    | string?                               | identity suffix (LEO-364): claims a `classes` window only once it carries the Hyprland tag `slot:<slot>` |

### Strays: `"slot"` executes, `"float"` floats for real (LEO-367)

- `"slot"` (default): a stray divides whatever the declared blocks leave,
  computed in `hypr/scene/layout.lua`.
- `"float"`: a stray is floated for real, decided at **open time** — the same
  pattern grouping uses (see "Group" above), for the same reason: a
  compile-time rule matched on `workspace` inside `match` is not true yet
  when the window opens (AGENTS.md "Hyprland primitives", LEO-369), so a
  static `float = true` rule chained off it never fires.

`hypr/scene/strays.lua` (pure) decides: a window that lands on a
`strays = "float"` scene's workspace, whose class matches no block, is not in
`barred`, and is not already floating → `float`. Its executor in
`hypr/events/scene.lua`, on `window.open`/`window.move_to_workspace`,
dispatches `hl.dsp.window.float({ window = "address:"..a })` — address-targeted,
no focus-dance, no loop, no timer — and logs `arrange`/`stray_float`. A
`barred` class or a block member is left exactly as it is; the same
reasoning as `grouping.lua`'s eject case does not apply here, since a stray
that already floats has nothing to correct.

Once that dispatch lands, the window is floating and Hyprland stops offering
it to the scene layout's `recalculate` as a tiled target at all — the layout
has no float branch left (`layout.float_box` and the centered-box fallback it
used to give a floated stray are gone). The one moment a `strays = "float"`
scene's stray can still be seen tiled is between its own open event and that
dispatch landing; `layout.lua` treats it exactly like a `"slot"` stray for
that moment, since it is not floating yet. `layout.stack` (below) is
unrelated.

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
never fill from that class **on class alone**. `spec.block_candidates(spec,
class, tags)` returns every matching block so a caller can see and log the
ambiguity (the follow-up issue wires this to `identify.ambiguous`);
`spec.ambiguous_classes(spec)` is a static validator over the declaration
itself, listing every class entry claimed by more than one block — this stays
a class-only check, so it still flags a shared `classes` entry even when
distinct `slot`s disambiguate it live. The shipped defaults have exactly one:
`zen-gaming-media` in the `pokemon` scene's flanking media blocks (by design —
the same class fills both the left and right slot). A block with `slot` set
is excluded from `block_candidates`/`block_for` until the window carries the
Hyprland tag `slot:<slot>` (`spec.slot_candidates(spec, class)` returns the
declared pool regardless); `hypr/scene/identify.lua` is what stamps it
(LEO-364, "Window identity" in desktop-model.md).

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
declaration on scrolling — where another layout owns the geometry — is inert
there, because nothing asks the scene layout provider to place anything on a
workspace it does not own. The runtime group decision stays layout-independent.

`mod+shift+h/l` (tile swap, LEO-344) asks the provider for a different order
without touching the declaration: `hypr/scene/order.lua` holds a session-only
key-order override per scene name (never persisted, never `$QF_STORE`), and
`hypr/scene/layout.lua`'s `M.reorder` applies it to the sequenced entries
before the split is computed. A restart or config reload drops it back to
declared order.

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
