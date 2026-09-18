# Flip

**Status: wired as a second layout, superseded by columns.md's model —
this document now describes the `flip` presentation, not a layout a scene
opts into.** `hypr/scene/deck.lua` implements the pure decision;
`hypr/scene/deck_provider.lua` registers it with the compositor
(`hl.layout.register("deck", ...)`, mirroring `hypr/scene/provider.lua`) and
dispatches the hold/return moves it reports; `hypr/scene/deck_scroll.lua`
holds the session-only scroll index; `hypr/lib/nav.lua`/`hypr/binds.lua` map
`mod+h/l` across columns and `mod+j/k` to scroll within one. That code
predates the decision this document now records and still speaks of `deck`
as a scene-level `layout` choice; [columns.md](columns.md)'s §12 is the
concrete map for turning it into the `flip` presentation module described
below. Still true of the live desk: no real scene declares `layout =
"deck"` — every workspace behaves exactly as it did before any of this
landed. Read [scenes.md](scenes.md) and [columns.md](columns.md) first —
columns.md is the architecture of record for what a column is and how it is
sized; this document only describes what happens _inside_ a column whose
declared `presentation` is `flip`.

## `flip` is a presentation, not a layout

Retired framing, kept here so the history is legible: this document used
to describe "the desk's two workspace layouts," `scene` and `deck`, chosen
once per workspace. That is wrong per the user's decision (columns.md's
model statement): **presentation is a property of a column**, not of a
scene or a workspace. A scene declares columns (roles, in columns.md's
vocabulary); each column declares its own `presentation`, `"stack"` or
`"flip"`, independently of every other column in the same row. A workspace
with a `flip` project column and a `stack` browser column beside it is
not a hybrid or an edge case — it is the ordinary shape the model expects,
because nothing above the column ever chose "deck" or "scene" for the
whole row.

What follows is unchanged by that correction except in name: everything
this document says about a "deck column" is a column whose `presentation`
is `flip`, sized by columns.md's resolver exactly like any `stack` column,
never by a `share` this document used to define independently.

## What `flip` adds over `stack`

`stack` (`hypr/scene/layout.lua`, soon `stack.lua` per columns.md §12) is
one row of columns with fixed membership and no viewport: every window
subscribed to a column gets a box, all of the time, stacked vertically if
there is more than one. `flip` is the other presentation: a column showing
one member at a time, flipped through vertically, niri-style. A column
never partially shows a window and never shrinks one to fit; it shows
exactly one member at full column height, and scrolling changes _which_
member that is.

A column's `presentation` is declared per role in the scene's column
declaration (columns.md §1), never a global toggle and never inherited from
a sibling column — **Dofus's columns present `stack` and must never gain
flip/scroll behaviour**; its group-left, browser-right split is exactly the
fixed presentation it has today. `code`'s project column is the first real
`flip` column, once terminal roles (LEO-308/311) exist to fill it with more
than one project's windows (columns.md §11); nothing about this document
wires that yet.

No horizontal scrolling and no more than one row, now or built toward
later, per column: a physical constraint (a column is a vertical strip),
not a policy that might grow. A later design may add horizontal scrolling
within a flip column; this contract does not anticipate it.

## Membership is a subscription, not a class list

Three ways a window ends up in a `flip` column's deck, all through the same
matching function (`M.column_for`) — this is column membership in general,
not something specific to `flip`; a `stack` column subscribes the same way:

1. **A class subscribes.** A pattern on a column is the same
   literal-or-Lua-pattern grammar a `stack` column's classes already use
   (`hypr/scene/spec.lua`'s `class_matches`). Any window of that class joins
   the column; this is how a class opts into flipping without a per-window
   decision every time it opens.
2. **A window declares itself in.** A column names a subscription identity
   (today `deck = "<name>"`; columns.md §11 discusses the project-identity
   successor); a window carrying the matching Hyprland tag joins that
   column regardless of its class. This reuses the identity-stamping
   mechanism a `stack` column's `slot` already relies on (LEO-364,
   `hypr/scene/identify.lua`) rather than inventing a second one — a project
   terminal or a companion window can be tagged into a specific column at
   launch without its class alone being enough to say which one.
3. **Unrelated windows are grouped by hand.** A column's classes may list
   several unrelated classes explicitly — Obsidian with Linear, say — the
   same way a `stack` column already allows more than one class. "By hand"
   means the scene author writes both classes into the column; there is no
   live drag-to-group interaction in this contract.

A window matching no column's subscription is not part of any column at
all — unlike a `stack` column's stray handling, `flip` has no catch-all. A
scene that wants an overflow bucket declares a column for it explicitly.

The tag-declared route (2) is a self-declaration a window can only carry if
something stamped it — the tag vocabulary itself (which project → which
column) is terminal-role work, still Backlog (LEO-308/311) at the time this
document was last revised, and is exactly the gap columns.md §11 flags for
"one column = one project." This contract only defines how the `flip`
module reads the tag once it exists; it does not invent a naming scheme for
it.

## Flipping (scrolling)

Within a `flip` column, membership order is arrival order — the same "join
list" `hypr/scene/group_adapters.lua`'s default adapter already keeps for a
group's `mod+j/k` order, not re-derived a second way. A **group** inside a
flip column (an ordinary Hyprland-grouped set of windows) collapses to one
flip entry, exactly like a `stack` column's `collapse_groups`: flipping past
a group shows or hides all of its members together, and its groupbar still
distinguishes them the way it does today. A `stack` role folded into a
`flip` column (columns.md §3, "Folding across presentations") collapses to
one flip entry the same way — the fold does not invent a second grouping
rule either.

A per-workspace, per-column **scroll index** (1-based, which member is
visible) is the only state `flip` adds, and it is session-only — the same
lifetime as `hypr/scene/order.lua`'s tile-swap override, never persisted,
dropped on reload. `M.clamp_scroll` re-derives a valid index every pass
against the column's current member count, so a window closing mid-column
can never strand the scroll position past the end (mirrors the reachability
guarantees the rest of the scene engine already gives — see
[desktop-model.md](desktop-model.md#transitions), "scrolling through the
slot updates recency"). A `flip` column that folds into another column
(columns.md §3) keeps its own scroll index as dead state until the fold
reverses; the target column's own index is what governs while the fold
stands.

**Recency**: desktop-model.md's Transitions section says scrolling through a
declared slot updates recency the way a hand-off's return edge does. This
contract does not yet decide what "recency" means for a `flip` column
beyond naming the open question — it is deferred to the chunk that wires
the provider and its state, since recency is about _when_ the scroll index
changes, not the pure arithmetic of where a box goes once it has.

## Why hidden windows are HELD, not placed off-screen

The natural-looking implementation places every column member's box, moving
the non-visible ones a full column-height below the visible area, and lets
the compositor clip them. **Spiked live in the nested e2e instance
(LEO-349) and it does not hold**: two ordinary tiled windows were given to a
custom-registered layout, whose `recalculate` placed the first at the top of
the work area and the second a full work-area height below it via
`target:place`. Hyprland did not honour the second box — the window's
reported geometry was neither the requested off-screen position nor stable;
it was silently restacked inside the visible area instead (observed at
`y = first.y + gaps`, `h` shrunk to fit two windows in one visible strip —
not the layout's request at all). The risk AGENTS.md's "Hyprland primitives"
warns about — "placing a window past the monitor edge may fight Hyprland's
clipping or monitor reassignment" — is real for this compositor build; a
tiled target's box is not honoured once it falls outside the work area.

**Fallback adopted instead**: a `flip` column's non-visible windows are not
laid out at all. `M.boxes` returns two things — boxes for the members
currently visible, and a flat list of addresses to **hold**: windows that
must leave the workspace's tiled set entirely, the same mechanism
`hypr/lib/minimize.lua` and `hypr/hyprfocus/hold.lua` already use (a special
workspace, e.g. `special:deck-hold`, or a per-scene hold area consistent
with desktop-model.md's "hold area" concept). Flipping then means: move the
newly-visible window back onto the workspace, move the previously-visible
one to hold, and let `recalculate` place whatever is left — an ordinary
dispatch on `window.move`, not a geometry trick, and it is the **executor's**
job, not this module's: `M.boxes` only reports which addresses need to move,
never dispatches. That wiring — the hold workspace, the move on scroll, and
the bind that changes the scroll index — is the provider chunk's job (see
columns.md §12 for its merged shape), not this module's.

## Navigation

Reuses the existing decision entirely; nothing new is invented for `flip`:

- `mod+h/l` moves across **columns** — the same tile-order decision
  `hypr/lib/nav.lua`'s `M.decide` already makes for a `stack` column, since
  every resolved column is a tile regardless of its presentation. Crossing
  into a `flip` column focuses its currently visible member (whatever the
  scroll index already names), the same way entering a group tile focuses
  its recorded member (LEO-380).
- `mod+j/k` moves **within** a column, adapted per its `presentation`:
  inside a `stack` column it changes focus among already-visible windows
  (`hypr/lib/nav.lua`'s `M.window_neighbor`, unchanged); inside a `flip`
  column it changes the column's scroll index by one (clamped, no wrap —
  same edge behaviour as `window_neighbor`) and the newly-visible window is
  what receives focus. Inside a collapsed group entry, `mod+j/k` keeps
  stepping the group's own adapter order first (unchanged); only crossing
  the group's own boundary advances the column's scroll index. Once
  `presentation` is a resolved-column field (columns.md §1), this becomes
  one branch read off the focused column's own `presentation`, not a
  scene-level check.
- `mod+shift+h/l` and `mod+shift+j/k` are unassigned for a `flip` column in
  this contract — swapping column order or reordering a column's stack are
  not decided here. Left to the wiring chunk once there is a concrete use
  for reordering a flip column (`hypr/scene/order.lua`'s override may or
  may not be the right session-state shape for it).

None of the above is implemented yet: `hypr/lib/nav.lua` is unchanged by
this chunk. This section records the intended mapping for the chunk that
does wire binds.

## Bound

`M.MIN_COLUMNS = 1`, `M.MAX_COLUMNS = 3` in the current `hypr/scene/deck.lua`
were a whole-row bound from when `deck` was a second layout owning its own
row of columns. Under the column-core model, a `flip` column is sized and
counted by the same resolver every column goes through (columns.md §1-§3);
there is no longer a separate 1–3 bound belonging to `flip` alone — the
resolver's own folding ladder is what keeps a row's column count sane. This
constant is retired along with the rest of `deck.lua`'s row-level
arithmetic per columns.md §12; nothing in the resolver replaces it with an
equivalent cap, because the ladder already prevents an unbounded column
count from ever surviving on a real monitor width.

## Wiring (as it stands, pre-column-core)

The following describes the code that landed before this revision and is
still true of the live desk; columns.md §12 is what changes it, not yet
performed:

- `hypr/scene/deck_provider.lua` registers `hl.layout.register("deck", ...)`.
  Its `recalculate` gathers every window anywhere that subscribes to the
  scene's columns (`hl.get_windows()` filtered through `deck.column_for` —
  not `workspace_tiles`, since a held member has already left the
  workspace), calls `deck.boxes`, places the returned boxes on live
  `ctx.targets`, and dispatches the rest: a box whose address is not among
  `ctx.targets` gets a `window.move` home (it was held or freshly scrolled
  to); every held address still tiled here gets moved to `HOLD`.
- The hold area is one shared special workspace, `special:deck-hold`
  (`deck_provider.HOLD`) — never declared, so no mode can admit or withdraw
  it, the same shape `hypr/hyprfocus/hold.lua`'s `HELD` uses. Per-scene
  holding was the open question this document left; one shared area was
  simpler and nothing today needs the split.
- `hypr/scene/deck_scroll.lua` is the session-only scroll index, keyed by
  scene name then column order, mirroring `hypr/scene/order.lua` exactly
  (never touches `$QF_STORE`, dropped on reload).
- `hypr/lib/nav.lua`'s `M.deck_tile_order(spec, tiles, scroll)` turns a
  deck's columns into `Nav.Tile`s the existing `M.decide` already knows how
  to walk — a column is a tile, same as a `stack` block or group, so
  `mod+h/l` needed no new decision, only a new way to build the tile list.
  Each tile also carries `plain` (arrival order, untouched) and `column`
  (its order), which `hypr/binds.lua`'s `mod+j/k` deck branch uses with the
  existing `M.window_neighbor` to compute the next visible member, store the
  new index, move it home, and focus it — the executor's job per "Why hidden
  windows are HELD" above, not a second navigation path.
- `mod+shift+h/l` and `mod+shift+j/k` stay unassigned for a deck scene, as
  this document already said — `hypr/binds.lua`'s swap/move-in-group
  handlers now check `deck.applies(scene)` and no-op rather than
  misinterpreting a deck's `columns` as a `stack` scene's `blocks`. Once
  presentation is per-column (columns.md §12), this check becomes "is the
  focused column's presentation `flip`," not a scene-level flag.
- `hypr/scene/spec.lua`'s `normalize` gained two additive fields —
  `layout` (`"scene"` default, `"deck"` opt-in) and `columns` (the same
  shallow order/share/classes/deck normalization blocks already gets) —
  the minimum schema support needed for a scene to describe a deck at all.
  Per columns.md §5/§12, `layout` is retired outright and `presentation`
  moves onto each role instead; this normalization step is what the next
  schema chunk replaces.
- Live-verified in the nested e2e instance (`tests/e2e/scenarios/90_deck.sh`,
  a sandboxed fixture scene only — `tests/e2e/fixtures/hyprfocus.json`'s
  `deck-test`, `conf/hosts/e2e.lua`'s workspace 4): three windows placed on a
  one-column deck leave exactly one tiled on the workspace and two on
  `special:deck-hold`; flipping (`mod+j/k`'s bind body, driven via `hc eval`
  the same way `60_navigation.sh` does — `hq key` does not fire this
  config's Lua-closure binds in this sandbox) changes which one is tiled,
  the other two stay held, and focus lands on exactly the window the flip
  asked for, never a stray jump. A workspace whose scene is never admitted
  by any mode never gets its `layout = "lua:deck"` workspace rule enabled
  (`hypr/hyprfocus/workspaces.lua`'s `M.admit` disables every rule the
  active mode does not name at boot) — the fixture's `neutral`/`work` modes
  both admit `deck-test` for this reason, and a real scene adopting `flip`
  will need the same, per column rather than per scene, once the merge
  lands.

## Next chunk

- The merge columns.md §12 describes: `hypr/scene/deck.lua` →
  `hypr/scene/flip.lua`, `hypr/scene/layout.lua` → `hypr/scene/stack.lua`,
  the two providers merging into one that reads `presentation` per
  resolved column, `deck_scroll.lua` → `scroll.lua`.
- `presentation = "flip"` on an actual column (`code`'s project column,
  once LEO-308/311 land) replacing today's fixed blocks.
- Structured logging events (`arrange`/`flip_scroll`, `arrange`/`flip_hold`)
  once LEO-352 lands a writer; until then the executor still only dispatches
  the moves the pure functions decide.
- `mod+shift+h/l`/`mod+shift+j/k` for a `flip` column (column reorder / stack
  reorder) — still not decided.
- The two open questions this document already named: whether an empty
  column keeps its declared width, and what "recency" means for a scrolled
  column (desktop-model.md's Transitions section).
- The project-identity gap columns.md §11 flags: a per-launch project tag,
  distinct from a scene's fixed `slot`, needed before "one column = one
  project" can claim windows without a scene author naming a class list by
  hand.
