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

### Undeclared workspaces (LEO-382)

Hyprland gives each monitor a numbered workspace of its own at startup, so a
window that opens or moves before anything claims it can land on a plain
workspace `workspace_specs` never names — no scene, shelf or binding
addresses it, so it is otherwise stranded forever. The same treatment
ignored monitors get above extends to this case: a window on a plain
workspace not in `workspace_specs` moves, address-targeted, to that
monitor's declared workspace (the entry marked `default = true`, or the
first declared for that monitor when none is), falling back to the
primary's declared workspace when the monitor has none of its own or is
itself ignored (left to the ignored-monitor treatment instead, so the two
never dispatch competing moves for one event). A special is never a target.
Pure decision in `nav.off_undeclared` (`tests/nav_spec.lua`), executor
`keep_off_undeclared` in `hypr/events/scene.lua`, run at `window.open` and
`window.move_to_workspace` only — never a sweep. Unlike `collect`, which
must leave a member the user deliberately parked elsewhere alone, an
undeclared workspace is not reachable through the bound UI at all, so there
is no user intent this could fight.

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

`dofus` and `media` both use `zen-twilight-media` (the shared Media profile);
grouping and block matching are already scoped to a window's own workspace
(`hypr/scene/grouping.lua`), so this alone is not a conflict. What blinds a
block to a _specific_ window of the class — dofus's claimed browser vs
media's unpinned tile — is identity stamped at launch (LEO-364, LEO-412):
each block declares `classes = { "zen-twilight-media" }` plus a distinct
`slot` (`dofus/browser`, `media/...`); `hypr/scene/identify.lua` stamps
`slot:<slot>` on the first still-unslotted live window of that class on the
workspace, in block declaration order, once per
`window.open`/`window.move_to_workspace`. `pokemon` used to share the same
profile and did exactly this; it now names two profiles of its own
(`-P pokemon-left`/`-P pokemon-right`, classes
`zen-twilight-pokemon-left`/`-right` — see `conf/base.lua`), one per column,
so its slot blocks claim by class directly and no race remains there.

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

Retired for now: the mode was work with one workspace moved, which is not a
different desk. It is out of the declaration (both the seed and the store), so
the modes tree offers `work` and `gaming` only. Re-adding it is a mode entry;
no scene was removed with it.

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

The declaration a group instantiates, and the rules its windows travel by, are
[declared-groups.md](declared-groups.md); this section is the ordering half.

Which member `mod+j/k` steps to next/prev inside a group is a separate decision from membership: `hypr/scene/group_adapters.lua` is a registry keyed by class, each entry a pure `order(members, ctx) -> addresses`. Dofus orders by the team roster (`hypr/services/dofus/common.lua`'s `team()`); the default adapter orders by a stable join list the executor (`hypr/events/scene.lua`) updates on `seed`/`join`/`eject`/`window.close`, falling back to `group.members` order for a group nothing has recorded yet. A project's class (`Proj-<name>`) takes a template adapter instead: its members sit in the declared tab order (nvim, yazi, zsh, run), with an on-demand scope after them. The physical group is sorted into the adapter's order and the record is rewritten from it -- on every seed, join, and focus of a member -- so the groupbar and the walk order are one list. Sorting once at seed time is not enough: a project is grouped before its `slot:` tags land (kitty maps async, `,proj.sh` stamps the role after), so the order is re-decided when a member is focused, which is the event a late tag arrives behind. A member out of place is removed and re-added at its index (`HL.Group:add`'s 1-based insertion index); the `move_window` dispatcher is not usable for this -- it acts on focus. `hypr/binds.lua`'s `focus_in_group` reads the adapter for the focused window's class, wraps at either end, and focuses by address — see [desktop-model.md](desktop-model.md#quickshell) for the bind-level contract and `tests/group_adapters_spec.lua` for the adapter specs.

## Guard

`guard` on a non-group member (`"barred"` default, `"deny"`) is declaration metadata; nothing reads it at runtime yet — the executor above only groups/ejects for `group = true` blocks. A non-group block's own class is simply never a group-block match, so it is never folded in or ejected by the executor either.

`barred` at scene level lists classes that legitimately open on the workspace without belonging to any block — a game, a launcher overlay. `compile.lua` still stamps a `barred:<name>` identity tag (scoped to the scene's own workspace, same as above) so a reader can recognize a deliberately unblocked class, but — per the timing fact above — no rule chains a group effect off it; a barred class reaching the block's group is instead the executor's `eject` case, the same path a plain foreigner takes.

## Re-homing (LEO-353)

A window claimed by one of a scene's blocks — its class matches, and, for a
`slot` block, it already carries that slot's tag — is re-homed to that
scene's workspace **unconditionally**, whenever it opens and whenever a mode
applies. This replaced `collect`, a per-block opt-in flag the retired
corrective engine (`schedule.lua` + `model.lua` + `actuator.lua`, LEO-261)
used to read and nothing since ever executed: the flag is gone from the
schema. A claimed window left on the wrong workspace was always a bug, never
a preference a block author needed to opt into — `proton-mail`, a project
terminal and a stray each drifted onto `obsidian-linear` under `work` for
exactly this reason before LEO-353.

Only a scene **active in the current mode** ever claims a window this way — a
scene the mode does not admit never pulls a window off wherever it stands.
Ownership is earned by **mapping into an active scene**, never by matching a
class alone: a class no active scene's block claims is left exactly where it
is (still subject to grouping/stray-float on its own workspace, unchanged).
A window on a special workspace (a shelf drawer, the engine's own hold area)
is never touched — that workspace's owner, not this decision, decides its
fate.

The decision is pure (`hypr/scene/home.lua`), executed address-targeted with
`follow = false` — never a focus-dance, never a loop or timer — from two call
sites: `hypr/events/scene.lua`'s `window.open` handler (before grouping/
stray-float run, so a window about to leave is never arranged into the
workspace it is leaving) and `hypr/hyprfocus/init.lua`'s mode `apply`, after
placement, so a claimed window already standing on the wrong workspace when a
mode is entered is swept home too. A window moved to another workspace **by
hand** (`window.move_to_workspace` from a deliberate drag or bind) does not
re-fire this decision — the same "arrival is never intent by itself" rule
transitions already follow (see desktop-model.md) — so a window you moved
away stays where you put it until the next open or mode apply.

A slot-tagged window is claimed only by the scene that declares that exact
slot (`home.claim` reads the tag, the same `class:slot` keying the resolver
uses): a bare block never swallows another scene's claimed window — media's
`zen-twilight-media` tile cannot take dofus's slotted one, and a window
whose slot scene is inactive stays put (context survives a reload). Tagless
windows keep the ordinary class-wide search.

## Companions

`spawn` on a member: open the companion when the first match maps; close it when the last leaves. Only a scene the **running mode admits** converges its companions: a withdrawn scene's spawn used to fire anyway, opening its browser onto whatever workspace was focused — the code scene's `zen-twilight` landing on dofus as a floating stray. And never **while a mode apply is mid-shuffle**: the apply parks and restores members in phases, and a convergence racing it judged presence against the outgoing mode's admitted set — which closed this same browser while its members were merely being parked on the holding place. The per-event convergence is suspended for the apply's duration; the apply reconverges every admitted scene once its phases are done, so a companion whose members come back comes back with them, deterministically at the end of the shuffle. A profile is one instance and an instance is one WM_CLASS (`--name` applies only to the launch that STARTS the profile), so two scenes sharing one profile can only tell their windows apart by a slot tag stamped in a race the mapping order decides: give a scene that needs its own window its own profile. `pokemon` did share the Media profile and used slots for exactly that reason; it now names two profiles of its own (`-P pokemon-left`/`-P pokemon-right`), so its flanking blocks claim by class and no race remains. A hand-opened window of the class is never part of this: no armed intent, no claim.

A member the deck has scrolled out of view still counts as a member: it
stands on the deck's hold, not on the scene's workspace, and reading it as
gone made a scroll look like the last member leaving — which closed the
companion, and scrolling back spawned another.

A parked window of the companion class is **adopted**, not duplicated. A
launcher sharing one profile hands back the window it already has rather than
opening a second one when that window is parked out of sight (verified live:
a second `--new-window` against the shared zen profile, whose only window sat
on a special workspace, opened nothing). So when the mode's holding place
already holds one of the class, the scene takes it over — slot stamped, hold
record released — instead of asking for a spawn that would never arrive. The
scene it was held for is withdrawn by definition, and its own convergence
opens one when a mode admits it again: by then this window stands on a
visible workspace, where a second one does open.

`max_spawns` (default 1) caps how many of the companion class the engine
keeps alive while the block has members. The count is derived from live
windows on the scene's workspace — never remembered — so a reload or a
compositor restart changes nothing, and the cap fills one spawn per
convergence: each spawned window's own open event re-converges the next, and
the single in-flight pending marker admits one spawn at a time, so a burst of
events converges to exactly `max_spawns` and never overshoots. The guarantee
is "the engine never creates more than n", not "no more than n can exist": a
window of the class opened by hand counts toward the cap but is never closed
by it — the close branch belongs to member presence, and a derived count
cannot tell the engine's spawns from the user's. Whatever the cap, the last
member leaving closes every companion. An out-of-range `max_spawns` (0,
negative, fractional) falls back to 1 in `hypr/scene/spec.lua`, the same
shape as a half-declared spawn being dropped: a bad value never refuses the
whole scene.

`auto_start` (default false) on a spawn keeps the companion alive whenever the
running mode admits the scene, even before the member window has opened and
after the last member has closed. The companion is spawned onto the scene's
workspace as soon as the scene becomes active, and it is only closed when the
scene is withdrawn (not while the scene is merely empty). Use it when the scene
expects the companion to be present by default — for example, Dofus's browser
profile, where the game client should always land to the left of an already-open
browser tile.

Launch intent rides the same pending marker (LEO-412). The spawn executor
arms one marker per decision — keyed `workspace:class`, one spawn in flight —
and `arm_launch` (a scene binding like pokemon's left/right keys) arms the same
key for a user-initiated launch. Whoever answers the launch, the open step
claims it (consuming the marker, stamping the launching scene's first free
slot via `hypr/scene/identify.lua` `assign_for`) before `home` sends it to
its scene — so a pin rule such as `+media-browser` never strands a claimed
window, while a window with no armed intent is claimed by nothing and keeps
whatever open/home logic decides for it.

## Docks

A scene says where each quickshell isle sits. `docks` is a map keyed by isle
id — quickshell's registry, documented in that repo's `modules/bar/Readme.md`,
so the ids are a contract between the two:

```lua
docks = {
  ["bar.workspaces"] = { at = "top-left", of = "block:1",
                         fallback = { at = "top-left", of = "screen" } },
  ["bar.center"]     = { at = "top-center", of = "screen" },
  ["dofus.roster"]   = { at = "bottom-left", of = "block:1" },
  ["bar.clock"]      = false,
}
```

A block's `order` is part of its **identity**, not just its sort key: the
compile emits it into the tag every window of that block wears
(`block:<scene>/<order>`), and the dock publisher keys its targets by it. Two
consequences. A dock must name the order the block actually carries —
`dofus`'s game block is `order = 0`, so its isles anchor to `block:0`; naming
`block:1` resolves to nothing and the isle rests forever, looking exactly like
docking switched off (live, 2026-09-25; `hypr/scene/spec.lua` now traces
`admit.dock_dropped` for a dock naming an order the scene does not declare).
And renumbering a block under a running desk **orphans its live windows**:
they keep the tag naming the old order, stop matching any declared block, and
the stray policy moves them onto whatever scene is focused — a Dofus client
walked onto the code scene that way. Renumber only across a reload, or don't.

- `of` — what the isle anchors to: `screen`, `block:<order>`,
  `column:<order>` (a deck's column), `slot:<slot>` or `class:<class>`. On a
  **deck**, anchor to the **column**: the strip shows one thing at a time, so
  `block:<order>` names a box only while that block's window is the visible
  one, and an isle anchored to a block docks only when that thing happens to
  be on screen. A target this grammar does not know is dropped at parse time
  with an `admit.dock_dropped` trace — the scene keeps its other docks, and a
  scene whose every dock was dropped publishes nothing at all, which looks
  exactly like docking being switched off.
- `fallback` — a dock spec of the same shape, tried when the one above it
  resolves to nothing. It is for an isle with a SECOND real target, not a
  blanket screen escape: giving every isle `{ of = "screen" }` put two isles
  on one screen anchor the moment their blocks went away, and since one spot
  takes one isle, the loser rested while its neighbour stood in the gap — two
  isles on one workspace in two different failure modes, and both of them
  moving on every window event (live, 2026-09-24: "when isles have nothing to
  anchor they run around like headless chickens"). A scene with no live
  windows rests its whole bar on purpose: resting is the bar's own row, the
  one place that does not move. Every isle's FIRST choice is claimed before
  any isle walks a fallback, so a fallback can never take the region an isle
  with a live window asked for.
- **Opt-in**: an isle appears on a scene's screen only where that scene names
  it. The three isles every bar carries (`bar.workspaces`, `bar.center`,
  `bar.clock`) rest where they always did when a scene says nothing; every
  other isle — the project strip, the Dofus roster — is absent unless
  declared. `false` withholds one explicitly.
- `at` — the nine-grid: `top-left` `top-center` `top-right` `middle-left`
  `center` `middle-right` `bottom-left` `bottom-center` `bottom-right`, plus
  the four side-leading corners `left-top` `left-bottom` `right-top`
  `right-bottom`. A nine-grid corner docks to the horizontal edge it names and
  aligns along it; a side-leading corner docks to the **side** gutter and
  aligns to the window's top or bottom — "in the left gutter, at the bottom",
  which the nine-grid alone cannot say.
- `of` — `screen`, `block:<order>`, `slot:<slot>` or `class:<class>`. Block,
  slot and class name a tile the layout placed this pass; a block with no live
  window names nothing, which is what makes its dock collapse.
- `orientation` — `horizontal` or `vertical`; defaults from the edge (a side
  gutter stacks its content, a top or bottom gutter lays it in a row).
- `fallback` — a dock spec of the same shape, chainable.
- `false` — this scene withholds the isle; it publishes `hidden`, which is not
  the same as resting.

A dock sits **outside** its target, in the gutter between that edge and the
screen's, never between two windows. The dominant axis is the anchor's first
word, switched to the other one when the named gutter faces another window and
the other faces the screen. The second word aligns the isle along the edge.
The corner touching the window is its growth corner: an isle grows away from
the window, never into it. Standoff from the window is the scene's `gaps_in`,
so the isle follows its block on both axes — a scene with a deeper gap carries
the isle with it.

The gutter is **measured**, not derived from the gap ladder: the publishing
pass holds both boxes and the compositor's own geometry is the only answer to
"where is the edge I am lining up with" (a placed box and the window standing
in it differ by the border and inner gap). The whole gutter is published, not
the gutter less the standoff.

`of = "screen"` is the one target with no window to hug: that isle stands on
the monitor's own edge and grows inward, over the band measured to the nearest
tile — the declared outer gap is 12px on the secondary against a 54px isle,
which is no band at all.

When a dock cannot be honoured — the target is absent, or both candidate
gutters face another window — it steps down the declared `fallback` chain and,
when that is empty, rests: the isle's own default position. **An isle only ever
deviates from resting through its own declaration.** There is no implicit
"same anchor on `screen`" rung: without one, two isles on the same workspace
cannot end up in different failure modes (one hugging a live window gutter,
its neighbour squeezed flush into the screen gap) — the inconsistency the old
ladder produced. A scene with no live windows therefore rests every
block-anchored isle; an isle declared directly against `of = "screen"` is not
a fallback and still docks — it asked for the screen frame on purpose. The
shipped scenes declare no screen fallbacks: isles dock to the block they name,
or rest. Two isles claiming one region resolve in two passes: every isle's
first choice claims before any isle walks a fallback (an isle whose declared
window is live outranks a neighbour that has already lost its own), and within
a pass the sorted isle id breaks the tie — the first keeps it, the second
walks its own ladder. So a second window opening beside the first
never inherits the first's dock, and the association stays legible.

`hypr/lib/dock.lua` decides all of this as arithmetic over the boxes the
layout just placed. `hypr/scene/dock_publish.lua` writes the result to the
`geometry` store (`docks.<monitor>.<isle id>` = `{ region, anchor, grow,
align, edge, orientation, state }`, monitor-local — `align` says which part of
the isle the anchor point is, `edge` which gutter it stands in, so the consumer
knows which end of the region the window is at) from the tail of a layout pass — both
the scene and deck providers — and only when the resolved map changed. That
tail is read-only by construction: it places nothing and dispatches nothing,
so a dock can never move the tile it hangs off. A scene edit drops the
write-suppressor (`dock_publish.invalidate()`, from `hypr/scene/spec.lua`'s
re-read), so an edited declaration re-publishes without a reload.

Quickshell sizes each isle, aligns its growth corner to the published anchor,
clamps it inside the published region, and warns once if it does not fit.
Nothing is ever drawn off screen.

## Areas

Where a _surface_ — a popup, a panel, anything quickshell opens over a scene
rather than docking to its frame — is allowed to sit, so it can never overlap
a bar. It replaced the per-workspace resolved-gap publish
(`geometry.workspaces`) that fed quickshell's retired `bar_follows_scene_gaps`:
a surface asks for real coordinates instead of a gap number, and a resting bar
depends only on its monitor.

Published to the `geometry` store, monitor-local, as `areas.<monitor>`:

```json
{
  "scene": "code",
  "work":    { "top_left": {"x":16,"y":58}, "top_right": {"x":5104,"y":58},
               "bottom_left": {"x":16,"y":1424}, "bottom_right": {"x":5104,"y":1424} },
  "columns": { "1": { "top_left": …, "top_right": …, "bottom_left": …, "bottom_right": … },
               "2": { … } }
}
```

- **`work`** is the area a surface may occupy at large: the monitor less the
  bar's reserved strip (`ctx.area`, what the compositor hands the layout
  provider — already outside the reserve) less the scene's own outer gap
  (`hypr/scene/layout.lua`'s `M.inner_area`). Because both subtractions
  happen before `work` is measured, a surface placed inside it can never
  overlap a bar or sit outside the scene's own frame.
- **`columns`** is the rect of the **window** standing in each column, keyed
  by its declared `order` (a JSON object, so the key is a string) — the space
  a surface may span. Not the layout's placed box: that is a request the
  compositor shrinks by its inner gap and border, and a surface lined up with
  it sat off the window's edge by tens of pixels. A scene declares no column
  concept of its own, so it is keyed by **block** order instead. A deck scene
  keys by its **deck column** order and publishes every column whether or not
  it currently shows a member (a column is a place, docs/deck.md): the shown
  window's rect where there is one, the column's layout box
  (`hypr/scene/deck.lua`'s `M.column_boxes`) where it is empty.

Published from the same read-only tail of the layout pass that publishes
docks (`hypr/scene/provider.lua`, `hypr/scene/deck_provider.lua`), cached per
monitor+scene the same way (`hypr/scene/area_publish.lua` mirrors
`dock_publish.lua`: written only when the resolved map changed, swept when a
monitor stops showing a scene, invalidated on a declaration re-read).
Unlike docks, an area publishes for **every** scene, not only ones declaring
isles — a surface needs somewhere to sit even on a scene with no docks. On
workspace arrival, before any real layout pass has run, `work` publishes
against the monitor's bare frame (or, for a deck, the column boxes still
resolve — they need no tile).

A scene may declare where a surface goes, the way it declares docks:

```lua
surfaces = {
  ["notifications"] = { of = "column:last", scale = 0.5, align = "right" },
}
```

`of` is `"work"`, `"column:<order>"`, `"column:first"`, or `"column:last"`;
`scale` is the fraction (0–1] of the area's width the surface takes;
`align`/`valign` place it inside the area (`left|right|center` /
`top|bottom|center`). **hypr does not read `surfaces` at all** — it is
declaration-only, validated by nothing here (an unknown scene key is simply
not copied into the normalized spec; nothing in `hypr/scene/spec.lua`
rejects it). Quickshell resolves it (`services/SurfacePlacement.js`,
`quickshell` repo) against the published `areas` map to compute the
surface's actual box.

## Bindings

Scene and member `bindings` tags are buffer-local. Which-key already filters `workspace › class › group › layout`. The groupbar is the active-member strip; the persistent bar is status, not a taskbar.

## Runtime (Lua)

```lua
Scene.active(ws)
Scene.tile(name, match)
```

One engine for all scenes:

- `dofus` — Dofus group + claimed `zen-twilight-media` right
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

| Field                    | Type                  | Meaning                                                                                            |
| ------------------------ | --------------------- | -------------------------------------------------------------------------------------------------- |
| `name`                   | string                | workspace `default_name` (`code`, `dofus`). This is the key; ids are host data.                    |
| `blocks`                 | Block[]               | the ordered tiles of the scene                                                                     |
| `barred`                 | string[]              | classes that may land here but must never join a group                                             |
| `strays`                 | `"slot"` \| `"float"` | how unmatched tiled windows are treated                                                            |
| `solo_frame`             | boolean?              | opt-out of centring a lone tile at its paired width (LEO-421; default on)                          |
| `bindings`               | string[]?             | binding trees this scene admits while active                                                       |
| `moods`                  | string[]?             | mood tags that select this scene when the mode does not                                            |
| `machines`               | table?                | machine-specific geometry overrides                                                                |
| `gaps_in`                | number?               | scene-declared inner gap (LEO-397); wins over the host workspace-spec                              |
|                          |                       | and the global `general:gaps_in` where set                                                         |
| `gaps_out`               | number? \| CssGap?    | scene-declared outer gap, same precedence as `gaps_in`                                             |
|                          |                       | Halving a scene's VISIBLE margin takes both rungs: the workspace rule's own `gaps_out` (host       |
|                          |                       | workspace-spec, `conf/hosts/*.lua`) is stripped from the work area before the layout runs, so a    |
|                          |                       | scene-only edit cannot shrink past it — `reference` and `media` declare the halved numbers in both |
|                          |                       | places. The rule's half needs a `hyprctl reload`; the scene's half lands on the next layout pass.  |
|                          |                       | A workspace's own gaps never redefine its monitor's resting gap (`geometry.monitor_gaps` reads the |
|                          |                       | profile).                                                                                          |
| `bar_follows_scene_gaps` | boolean?              | retired: ignored. A resting bar depends only on its monitor; surfaces are placed in `areas`.       |

### Block fields

| Field     | Type                                                                             | Meaning                                                                                                  |
| --------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `classes` | string[]                                                                         | literal class or Lua pattern, in window-rule grammar                                                     |
| `group`   | boolean                                                                          | one Hyprland group containing only these classes                                                         |
| `order`   | integer                                                                          | left-to-right tile sequence                                                                              |
| `share`   | number?                                                                          | fraction of the tiled span this block holds                                                              |
| `guard`   | `"barred"` \| `"deny"`                                                           | how a non-group block resists grouping                                                                   |
| `spawn`   | `{ class: string, command: string, max_spawns?: number, auto_start?: boolean }`? | companion window lifecycle; `max_spawns` (default 1) caps how many of                                    |
|           |                                                                                  | `class` the engine keeps alive while members stand, and `auto_start` keeps it alive whenever the scene   |
|           |                                                                                  | is active, even with no member present — the engine never creates more than n and never closes what      |
|           |                                                                                  | it did not spawn                                                                                         |
| `slot`    | string?                                                                          | identity suffix (LEO-364): claims a `classes` window only once it carries the Hyprland tag `slot:<slot>` |

### Solo centring (LEO-421)

A scene whose only present tile is one of several declared blocks (its
partner has not spawned, or has closed) is centred at the width it would
have held with that partner present — `hypr/scene/layout.lua`'s
`paired_fraction` runs the same share arithmetic as a full house, over the
scene's whole `blocks` declaration, and takes the lone tile's share of it.
Half the shortfall between that width and the full work area becomes an
equal outer gap on the left and right; vertical gaps are untouched. A scene
with only one declared block has no partner to centre against, so its lone
tile simply fills the panel, same as before. This never applies on a
secondary monitor (`is_primary` in `Scene.LayoutOpts`, read off
`config.host`) — there is no ultrawide width there to compensate for — and
`solo_frame = false` opts a scene out of it entirely, same as always.

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
no focus-dance, no loop — then, one tick later, resizes it to a fraction of its
monitor (`strays.fit_size`) and centers it, so a floated tile does not keep the
whole screen's box or sit half off it. It logs `arrange`/`stray_float`. A
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
distinct `slot`s disambiguate it live. The shared profiles today pair dofus
and media via one `zen-twilight-media` entry each, single-claimed per scene;
pokemon used to declare the class in both flanking blocks and no longer does
(it names a distinct profile per column — see `conf/base.lua`). A block with
`slot` set is excluded from `block_candidates`/`block_for` until the window
carries the Hyprland tag `slot:<slot>` (`spec.slot_candidates(spec, class)`
returns the declared pool regardless); `hypr/scene/identify.lua` is what
stamps it (LEO-364, "Window identity" in desktop-model.md).

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
has `group = true` and a `zen-twilight-media` companion (the shared Media
profile) with `guard = "deny"`, claimed by launch intent to the
`dofus/browser` slot;
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

A workspace does not choose between two layouts. Per [columns.md](columns.md),
the column core is the only layout: a scene declares its columns as roles
(priority, minimum width, optional fixed width and alignment, optional fold
target), one resolver fits those roles into whatever width the monitor
actually gives, and each resolved column declares its own **presentation**
— `stack` (every member tiled at once, today's behaviour, described above)
or `flip` (one member visible at full column height, flipped through —
[deck.md](deck.md)). Presentation is a property of a column, not of the
scene or the workspace: Dofus's columns present `stack` and never scroll;
`code`'s project column is meant to present `flip` beside a `stack` browser
column, once terminal roles exist to fill it (columns.md §11). There is no
scene-level `layout` field any more — see columns.md for the contract,
still a document and not yet wired past the pure resolver module.

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
    { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67,
      spawn = { class = "zen-twilight-media", command = "zen-twilight -P Media --name zen-twilight-media --new-window" } },
    { classes = { "zen-twilight-media" }, order = 2, share = 0.33, slot = "dofus/browser", guard = "deny" },
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
