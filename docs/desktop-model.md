# Desktop model

The intent this desk is built toward. **Status: target model.** Parts of it
are implemented, most are not; [lifecycle.md](lifecycle.md)
records what runs today, stage by stage. When this document and older text in
`AGENTS.md`, [scenes.md](scenes.md) or `system-config/docs/bindings.md`
disagree, this document states the intent and the older text is the defect.

## Why

The desk exists to limit exposure to distraction and to carry object
permanence and working memory for its user. Work and play almost always use
the same set of windows; bringing them into place by hand is the friction this
removes. The system decides, deterministically, what is on each workspace, how
it looks, what may open, and what may interrupt.

## Focus mode

A focus mode is a domain the user is placed in, not a menu of options. It
controls exactly four things:

1. **Theme** — palette pair and accent.
2. **Active scenes** — the set of scenes this mode brings up.
3. **Monitor per scene** — where each scene lands. Monitor names are host
   data (`conf/hosts/*.lua`); the mode maps scenes onto host monitor roles. A host's `ignored_monitors` are never a target ([scenes.md](scenes.md#ignored-monitors)).
4. **Lifecycle** — on entry and exit it calls each scene's bring-up and
   teardown interface. It does not arrange windows itself.

Later: permissions (what may launch) and notification routing per mode.

The modes a user picks between are `work`, `study` and `gaming`. **Login
always enters `work`**, unless the pointer names a timed mode that is still
running (`until` in the future), in which case that mode resumes as itself
and keeps its own `previous` — a stale/expired timed pointer, a missing
store, and a pointer naming an unknown mode all boot to `work` (never to
`previous`; that fallback is only for expiry reached while the desk is
already running, see "Pointer" below). `hypr/hyprfocus/boot.lua` is this
decision, applied once by `hyprland.start` (`hypr/events/start.lua`) via
`M.boot`. Work blocking media/game launches from login is accepted
behaviour, not a gap.

`neutral` is a hidden fallback for recovery (scenes: `code`, `proton`,
`logs`; validated like every mode), reachable from a submap, not a peer
choice and never a default or expiry fallback.

### Pointer

`focus.json` is the pointer: `{ mode, until, source, set_at, previous }`.
`previous` is written only when a mode is entered with an `until` — it holds
the mode active at that moment. If that mode was itself timed and still
unexpired, `previous` is set to _its_ `previous` instead (the chain always
collapses to an open-ended mode, never to another timed one). Setting an
open-ended mode (no `until`) clears `previous`.

Effective mode: `mode` if `until` is unset or not yet passed; otherwise
`previous` if the pointer carries one; otherwise `work`. Both the Lua
resolver (`hypr/hyprfocus/init.lua`'s `M.effective_mode`) and the Python CLI
(`bin/,hyprfocus`'s `effective_mode`) implement this identically, pinned by
shared fixtures under `tests/fixtures/hyprfocus/pointer/`.

## Scene

A scene is a plug-in unit that maps to one workspace. It owns:

- **Claims** — which windows belong to it (class, title, role).
- **Layout** — the scene is its own registered layout. Workspaces use `scene`
  or `columns` (at least two columns, each scrolling vertically); not dwindle,
  master or monocle.
- **Bring-up / teardown** — what it launches so the usual windows are in place
  without manual work, and how it releases them. Bring-up launches missing
  apps only on mode entry; a scene binding "complete the scene" relaunches
  what is missing mid-mode. Teardown happens only on a mode switch, for
  scenes the new mode does not include, and **closes** the scene's
  applications to free resources. Close is a cooperative request; a window
  that survives it (an unsaved-changes dialog, a scene veto) is a **veto**:
  the window is held and reported, never killed.
- **Drawers** — apps a scene depends on but that must not take a tile
  (Ankama launcher, Lutris, Steam, Signal, Vesktop). They are a distinct kind
  of resource living on engine-managed special workspaces that slide in over
  the scene, may run in the background, and may carry a launch command. A
  drawer is either **global** or **assigned to scenes** and then never
  reachable outside them. Every drawer gets the same reserved default binding
  inside the owning scope's submap, so drawers behave consistently across
  scopes. A locked scene still admits its drawers. The first implementation
  is **shelves** ([shelves.md](shelves.md)): one `shelf` submap, one key per
  app, with mode-admitted keys for Steam, Lutris and the Ankama Launcher.
- **Window-state behaviour** — what happens when a window opens or closes:
  - a scene may **lock** its layout so no additional window may join (Dofus:
    the Dofus group left, `zen-gaming-media` right, never disturbed);
  - a scene may define a **variant** of itself for a new window state (same
    workspace, different layout), or hand the workspace to **another named
    scene**;
  - a window may be **moved to a hold area** while another is needed and
    **return** when that one closes;
  - a window with no defined behaviour **floats**.
- **Mode-scoped bindings** — its binding tree (see below).

A class may be claimed by several scenes as long as no two of them are active
in the same mode. Two active scenes in one mode claiming the same class is a
declaration error, refused when the mode is validated.

### Window identity

Apps set their own class; the compositor cannot rewrite it. Two windows of the
same class are told apart by **identity stamped at launch**: the engine
launches the window, records its pid, address and `stable_id`, and assigns a
tag (`hl.dsp.window.tag`, e.g. `slot:pokemon/chat`). Scene claims may match on
that tag as well as `initial_class` and title. This replaces separate app
profiles per window.

**Verified live (LEO-364):** a tag added to an already-mapped window does
**not** retroactively fire a compile-time Hyprland rule matched on that tag —
a `float`/`group`/`workspace` rule keyed on `match.tag` never sees a window
that already satisfies it once the tag lands after open, the same timing
fact "Hyprland primitives" in AGENTS.md documents for LEO-369's tag→group
rule chain. Repro: nested Hyprland (`tests/e2e/hq`), a `window_rule` matched
on `tag = "spike:mark"` with a `float = true` effect, one window spawned
before the tag existed, then `hl.dispatch(hl.dsp.window.tag(...))` on the
already-mapped window — it stayed tiled. A control window matched on `class`
at open time floated correctly, confirming the rule mechanism itself works
and the gap is specifically post-map tag additions. Consequence: identity
tags are consumed by **runtime Lua reading `w.tags` synchronously in the same
event pass** (`hypr/scene/identify.lua`, wired into `window.open` /
`window.move_to_workspace` before routing), never by a static rule chained
off the tag — the same pattern grouping.lua and strays.lua already use for
their own runtime decisions.

### Transitions

Arrival is never intent by itself; only declared edges change a workspace.
Two kinds, both supported from the start:

- **Variant** — same scene, different layout (claims, bindings and drawers
  unchanged).
- **Hand-off** — the workspace switches to another named scene: its claims,
  layout, lock, bindings and drawers apply. Windows stay; a declared return
  edge switches back when the trigger window closes.

A window moved in by hand never fires an edge. When a declared slot is taken by
a newer window of the same kind, the older one is held and returns when the
newer closes; scrolling through the slot updates recency.

## Bindings

Three classes. They differ by **what makes them available**, not by where they
are defined.

| Class        | Available when                                                                  | Owned by                                                                                                                                                                        |
| ------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| System-level | always                                                                          | the compositor core: exits, escape hatches, compositor and window controls, system-centric actions. Not individual Quickshell widgets that belong to another module or service. |
| Contextual   | a matching window is **focused**                                                | an application adapter: common actions across applications, driving the app's API or CLI, assisted by Quickshell. **Unrelated to scenes.**                                      |
| Mode-scoped  | the owning scene is active in the current mode **and its workspace is focused** | the **scene**. Trees of the mode's scenes merge; conflicts are a validation error, not a runtime surprise.                                                                      |

Focus must never jump somewhere the user did not direct it.

### Which-key and submaps

Structured like Neovim:

- Holding the main modifier for more than 1.5 s opens which-key and cascades
  to an atomic one-off action or a repeatable one.
- `SUPER+Space` is the leader for domain-specific trees and also opens
  which-key.
- Which-key renders only keys that execute in the current context, by
  construction.

## Quickshell

Workspaces are managed in the background; Quickshell presents them.

- Each scene identifier maps to an icon (a Dofus egg on `dofus`, a Poké Ball on
  `pokemon`).
- The workspace widget shows the **order** of workspaces per monitor.
- Navigation keys address the engine's ordered structure of active workspaces
  and of windows within a workspace (counted left to right), per monitor, so a
  window is reached by position instead of searched for. Implemented:
  `mod+h/l` moves across tiles in the scene layout's own order (a group is one
  tile), continuing onto the adjacent monitor's edge tile past the last one —
  or, when the adjacent monitor has no scene workspace focused (or that scene
  has no tiles), focusing the monitor itself. It works from an empty
  workspace too (no active window to read a tile off), and the opposite key
  always returns (LEO-380): the whole decision is one pure function,
  `hypr/lib/nav.lua` `M.decide` (`tests/nav_spec.lua`), given both monitors'
  tiles and the active window's address (or nil); `hypr/binds.lua`'s
  `focus_tile` gathers that state and dispatches the action. Off a scene
  workspace, `mod+h/l` first tries the layout's own directional focus
  (`focus_left`/`focus_right`); if that left the active window unchanged —
  nothing that way on this monitor — it crosses to the adjacent monitor the
  same way, so a `scrolling` workspace at a monitor's edge does not strand
  focus there.
  Entering a group tile (crossing into it with `mod+h/l`, or landing on it as
  a monitor's edge tile) focuses its most recently focused member, not
  reliably its first: Hyprland's Lua binding never exposes `focusHistoryID`
  on the windows `hl.get_windows()` returns, so the executor
  (`hypr/events/scene.lua`) tracks it itself on `window.active` via
  `hypr/scene/group_adapters.lua`'s `record_focus`, keyed by group like the
  existing join-order tracking. Each adapter can override the choice with its
  own `enter(members, ctx) -> address?` (nil defers to the fallback); the
  default adapter's `enter` returns the recorded member, and Dofus keeps that
  default — team order has no obvious reason to prefer a different entry
  member. `hypr/lib/nav.lua`'s `tile_order` stays pure: it takes the entry
  address a caller already decided (`opts.enter`) and only places it first
  (`group_entry_order`), falling back to arrival order with no `opts`, no
  adapter override, or nothing recorded yet.
  `mod+j/k` moves within the focused tile: on a group, next/prev in that
  group's **adapter** order, wrapping, focusing by address — the same
  registry keyed by class picks the adapter (Dofus: team roster order from
  `hypr/services/dofus/team.lua`; everything else: a stable join-order list,
  updated as members join/leave (`hypr/events/scene.lua`), falling back to
  arrival order); on a stacked non-group block, next/prev window in that
  block (no wrap). A stale `hypr/services/dofus/dofus.lua` bind used to
  register `mod+h/l` before `hypr/binds.lua` ever loads and silently
  shadowed it for every Dofus session (Hyprland keeps the first registration
  for a chord) — retired in favor of the one decision above.
  `mod+shift+h/l` swaps a tile with its neighbour
  (session-only, `hypr/scene/order.lua` — never written to the scene
  declaration); `mod+shift+j/k` moves the focused window forward/back within
  its group. The workspace row (`config.host.workspaces.workspace_keys`)
  focuses/moves-to the Nth scene of the active mode's scene list on the
  focused monitor, resolved at press time from the applied desk
  (`hypr/hyprfocus/init.lua` `applied_desk`/`output_for`); pure ordering,
  neighbour and Nth-on-monitor decisions live in `hypr/lib/nav.lua`
  (`tests/nav_spec.lua`), bind handlers in `hypr/binds.lua` are thin. `mod+TAB` / `mod+shift+TAB` cycle the same per-monitor scene list in mode order, wrapping.
- The bar's side insets mirror each monitor's base tiled outer gap (LEO-340),
  published to the `geometry` store by `conf/host.lua`'s `build()` and read
  off resolved geometry, not a layout-specific option — workspace layouts are
  `scene` or `columns` only. This is the base gap only: the transient solo
  widen (the scene layout's own `solo_extra` framing a lone tile) is a
  per-workspace correction, not part of a monitor's resting geometry, so the
  bar never follows it.
- The same `build()` also publishes the monitor role map (LEO-368):
  `geometry`'s `roles` key, `{ primary: "<output>", secondary: "<output>" }`,
  built from the host's `primary_monitor`/`secondary_monitor` and which
  outputs are actually connected and not ignored (`hl.get_monitors()` through
  `hypr/lib/nav.lua`'s `usable_monitors`) — an unconnected or ignored output
  is omitted, never defaulted to primary (that fallback is placement's job,
  `hypr/hyprfocus/init.lua`'s `output_for`, not a published fact). Outputs are
  not always enumerated yet when the config first loads (the nested e2e host
  hits this every boot), so `monitor.added`/`monitor.removed` re-publish the
  role map alone once connectivity is known or changes; the gaps map never
  needs this, since it is resolved from `workspace_specs`, not live monitors.
  The bar's `roleForScreen` (quickshell `modules/bar/WorkspaceSwitch.js`)
  reads this map directly instead of guessing a screen's role from the gaps
  map's key order.

## Observability

Every lifecycle decision (identify, route, admit, arrange, interact, leave)
emits one structured log event with a trace per window. See
[lifecycle.md](lifecycle.md).
