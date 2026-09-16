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
   data (`conf/hosts/*.lua`); the mode maps scenes onto host monitor roles.
4. **Lifecycle** — on entry and exit it calls each scene's bring-up and
   teardown interface. It does not arrange windows itself.

Later: permissions (what may launch) and notification routing per mode.

`neutral` is a hidden fallback for recovery, reachable from a submap, not a
peer choice.

## Scene

A scene is a plug-in unit that maps to one workspace. It owns:

- **Claims** — which windows belong to it (class, title, role).
- **Layout** — the scene is its own registered layout. Workspaces use `scene`
  or `columns` (at least two columns, each scrolling vertically); not dwindle,
  master or monocle.
- **Bring-up / teardown** — what it launches so the usual windows are in place
  without manual work, and how it releases them.
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

### Open design question

When a window arrives that another scene would claim, is that arrival intent —
should the workspace evolve into that scene? A naive rule makes scene
definitions recursive (scene A on open of X becomes B, B on close of X becomes
A, B on open of Y …). The transition model must stay finite and inspectable.
Undecided.

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
  window is reached by position instead of searched for.
- The bar's side insets mirror each monitor's base tiled outer gap (LEO-340),
  published to the `geometry` store by `conf/host.lua`'s `build()` and read
  off resolved geometry, not a layout-specific option — workspace layouts are
  headed to `scene`/`columns` only. This is the base gap only: the transient
  solo widen (`hypr/events/solo_gaps.lua` framing a lone tile) is a
  per-workspace correction, not part of a monitor's resting geometry, so the
  bar never follows it.

## Observability

Every lifecycle decision (identify, route, admit, arrange, interact, leave)
emits one structured log event with a trace per window. See
[lifecycle.md](lifecycle.md).
