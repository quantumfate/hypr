# Declared groups

**Status: contract.** Parts of it are wired and parts are not; each rule below
says which. It is the single description of what a project group and a log
group both are, because they are the same object with two front-ends.
Neighbours: [scenes.md](scenes.md) (the scene contract), [deck.md](deck.md)
(the column strip), [project-groups.md](project-groups.md) (the project
front-end), [logs.md](logs.md) (the log front-end),
[bin/Readme.md](../bin/Readme.md) (the helpers).

A **declared group** is a set of windows a document names, instantiated on the
desk as one Hyprland group, presented by a deck column as one thing.

```
document            ->  instance                 ->  presentation
.proj.toml          ->  Proj-hypr, 4 windows     ->  one thing on code's column
logs.toml           ->  Log-hypr, 3 windows      ->  one thing on logs' column
```

The document is the authority on **identity** and **order**. The compositor is
the authority on **placement**. Neither may decide the other's half, and the
rules below exist because they were doing exactly that.

## 1. Identity is declared, never observed

A window belongs to its declared group because its **class and block say so**
— `Proj-<name>` matched by the `code` scene's block for that project, stamped
`block:<scene>/<order>` by `hypr/scene/compile.lua` at open — not because
Hyprland has already folded it into a group.

This is the rule the desk was missing, and every symptom below came from it:

> A project's windows map one at a time. Grouping can only fold them once
> they are on one workspace; the deck parks whatever is not the shown thing
> within milliseconds of a window mapping. So the deck parked members two,
> three and four before grouping ever saw them, each as **its own thing** on
> the strip, and the group could never complete. Verified in the nested
> instance: every `Proj-*` window on `special:deck-hold`, the column empty,
> focus left on the browser beside it.

So **a deck column's things are block identities, not `HL.Group` handles**. A
declared group is one thing from its first window's first frame, before the
compositor has grouped anything. A window with no block identity (an ad-hoc
`Kitty-Main`, a stray) is a thing of its own, as before.

`HL.Group` remains the _presentation_ of a thing — the groupbar, the tab
order, `mod+j/k` — never its definition.

## 2. A thing moves whole

Parking and unparking act on a thing, never on a member. Every member of a
declared group moves in the same pass or none of them does.

A group whose members straddle two workspaces is not a supported state. It is
also not a theoretical one: moving one member to the hold leaves the group
intact and spanning both (spiked live — `group` stays non-nil on both sides,
`members` still reports the full set), and the compositor then crashes in
`Layout::CWindowTarget::assignToSpace` the next time anything touches that
group. That crash reached the desk as _"the project does not open as a
group"_.

Corollaries, all wired:

- A window still standing on a hold workspace is never handed to
  `HL.Group:add`/`:remove` (`hypr/events/scene.lua`). `unhold` asks for the
  move; the move lands after the pass.
- Moves decided inside `recalculate` are dispatched a tick later, outside it
  ([deck.md](deck.md), "Moves leave the layout pass").

## 3. Placement never moves focus

**Focus is the user's, and only a user gesture moves it.** Placing, parking,
unparking, grouping, ejecting and reordering are placement; none of them may
change which window — or which monitor — holds the keyboard.

This is not only about losing your place. Quickshell reads
`Hyprland.focusedMonitor` for `PanelBus.activeScreen`, and every widget that
anchors to the active screen — which-key included — follows it. A focus dance
on one monitor therefore draws the which-key overlay on the other, which is
what "widgets appear on the wrong monitor, seemingly at random" is.

Where placement genuinely displaces the focused window (parking the very
window that holds focus), **that column's own** shown member takes focus —
never a neighbour column, and so never another monitor. Handing it to the
first box of the first column instead is how focus used to jump sideways out
of a two-column deck.

## 4. Opening a thing shows it

`open` is one act with one visible result: the declared group stands on its
column, shown, with focus on its first declared window (or the role that was
asked for).

The sequence is fixed, and every step is the front-end's, not the engine's:

1. Spawn the missing windows of the declaration, in declared order — in a
   session of its own (`setsid`), because the caller is often the picker,
   whose window closes the instant it has a choice. A plain background job is
   a child of that window: the hangup killed the template after two windows
   and left the second one untagged, which is what "it doesn't open as a
   group" looked like on the desk
   (`tests/e2e/scenarios/98_project_picker_template.sh`).
2. Let them settle into their group — identity is already decided by rule 1,
   so this is presentation catching up, not a race to win.
3. Scroll the column to this thing.
4. Focus the requested window, once.

Nothing else is asked to move. A project opening must not scroll another
column, must not re-home a neighbour, and must not leave focus anywhere but
where step 4 put it.

## 5. Order is the declaration's

A declared group's tab order is the order the document lists its windows in —
`nvim, yazi, zsh, run` — not the order they happened to map in. The adapter
that decides this is `hypr/scene/group_adapters.lua`'s project adapter, keyed
on the `slot:<role>` tag; the physical group is sorted to match and the
walk order is rewritten from the physical group, so the groupbar and `mod+j/k`
are one list ([scenes.md](scenes.md), "Group adapters").

`mod+j` walks UP that order, toward the first tab, and `mod+k` walks down it
— the opposite of the tile-stepping `j`/`k` outside a group (user decision,
2026-09-24), pinned in `tests/e2e/scenarios/98_project_picker_template.sh`.

The order is not drawn by the compositor: the groupbar is off, because
Hyprland reserves its height inside the group's own box and every
group/ungroup therefore resized the tile — and the bar's isles, which follow
the published tile geometry, jumped with it. The tab strip is a quickshell
isle instead (`bar.projects`).

Role tags land after the windows map (kitty maps async; `,proj.sh` stamps the
role afterwards), so the order is re-decided whenever a member is focused —
the event a late tag arrives behind.

## 6. The strip is a widget, not a decoration

Which tabs a group holds and which one is active is drawn by quickshell
(`modules/bar/ProjectTabs.qml`, in the `bar.projects` isle), not by the
compositor. A scene anchors that isle over the column it describes:

```json
"docks": { "bar.projects": { "at": "top-right", "of": "column:1" } }
```

A **column**, not a block: the strip shows one thing at a time, so
`block:<order>` names a box only while that block's window is the visible one
— an isle anchored to a block docked when an ad-hoc terminal happened to be
on screen and rested wherever it liked the rest of the time. The column is
there in every pass (`hypr/scene/dock_publish.lua`'s targets).

Widgets are **opt-in**: a scene's `docks` map is the whole truth about what
its screen carries. An entry places an isle, and absent means absent for
every scene-owned widget — only the three isles every bar has
(`bar.workspaces`, `bar.center`, `bar.clock`) rest by default when a scene
says nothing. A widget therefore describes the workspace its own screen is
standing in, never whatever holds the keyboard on another one.

The groupbar is off for the reason under rule 5. The widget reads the
compositor for its model, so a tab exists exactly as long as its window does,
and clicking one focuses that window.

## 7. A prompt is never a member

The pickers and the confirm dialog wear their group's class prefix
(`Proj-picker`, `Proj-confirm`, `Log-picker`), so every rule keyed on that
prefix catches them too. Two rules make them prompts rather than members, and
`conf/base.lua`'s `declared_group_prompts` is the single list all of them read:

- **They take their own focus.** The no-steal rule that keeps a spawning
  template from dragging the keyboard around would otherwise open a prompt you
  cannot type into.
- **They are `group = "barred"`.** `auto_group` swallows whatever opens beside
  a group, whatever its class, and the executor's answer to a foreigner inside
  a block's group is to EJECT it — an `HL.Group:remove`, which re-assigns the
  window's space and is the call that breaks a formation. Live evidence
  (2026-09-24): `arrange.group_eject` naming `Proj-picker` and `Proj-confirm`
  on the `code` scene, minutes after "opening a second project broke it
  again". Barring the class means the swallow never happens, so no eject is
  ever needed.

This does not reproduce in the harness — the picker floats there and
`auto_group` leaves it alone — so the rules themselves are pinned instead
(`tests/windowrules_targets_spec.lua`).

## 8. The group ends with its last window

A declared group is the instantiation of its document, derived from the
windows that exist. It is never a remembered membership set: closing the last
window ends the group, and reopening is a deliberate gesture. Both front-ends
say this already ([logs.md](logs.md) decisions, `,proj.sh`'s own header).

## Front-ends

Everything above is the engine. A front-end declares windows and asks for
them; it owns no placement logic of its own.

|          | project                           | log                              |
| -------- | --------------------------------- | -------------------------------- |
| document | `.proj.toml` + the projects store | `logs.toml` + the log catalogue  |
| class    | `Proj-<name>`                     | `Log-<name>`                     |
| role tag | `slot:<role>`                     | `slot:<source>`                  |
| scene    | `code`                            | `logs`                           |
| helper   | `bin/,proj.sh`                    | `bin/,logs.sh` (not yet written) |

The shared suffix is the only link between a project and its log group, and
it is one-way: the `code` deck pushes, the `logs` deck never does
([logs.md](logs.md), "Direction: the code scene drives").

## Verification

The harness sees all of this except float geometry, so it is asserted in the
nested instance, not by hand:

1. A project opens on a deck scene as one whole group, nothing of it parked
   apart (`tests/e2e/scenarios/97_project_group_deck.sh`).
2. A second project opens beside the first as its own whole group; the first
   stays whole.
3. Exactly one thing stands on the column, it is the one just opened, and
   focus is on it.
4. The focused **monitor** is the same before and after an open, a scroll and
   a park.
5. The physical group order is the declaration's order, and `mod+j/k` walks
   that same list (`95_project_group.sh`).
