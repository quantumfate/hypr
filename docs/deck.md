# Deck

**Status: wired, not yet adopted.** `hypr/scene/deck.lua` implements the pure
decision; `hypr/scene/deck_provider.lua` now registers it with the compositor
(`hl.layout.register("deck", ...)`, mirroring `hypr/scene/provider.lua`) and
dispatches the hold/return moves it reports; `hypr/scene/deck_scroll.lua`
holds the session-only scroll index; `hypr/lib/nav.lua`/`hypr/binds.lua` map
`mod+h/l` across columns and `mod+j/k` to scroll within one. Still true: no
real scene declares `layout = "deck"` — every workspace behaves exactly as it
did before this chunk. Read [scenes.md](scenes.md) and
[desktop-model.md](desktop-model.md) first; this widens both in place rather
than starting a third document. [columns.md](columns.md) widens this one in
turn: the duplicated share arithmetic and missing solo framing this document
flags in "Is this a second layout" below are exactly what that resolver
replaces.

## What `deck` adds over `scene`

The desk has exactly two workspace layouts. `scene` is one row of declared
blocks with fixed membership and no viewport: every matching window gets a
box, all of the time. `deck` is the other: one row of one to three
**columns**, each holding a **deck** of windows — a vertical stack the user
flips through one full window at a time, niri-style. A column never
partially shows a window and never shrinks one to fit; it shows exactly one
member at full column height, and scrolling changes _which_ member that is.

A scene chooses at most one of the two, explicitly, in its own declaration
(`layout = "scene" | "deck"`, defaulting to `scene`). This is a property of
the scene, not a global toggle — **Dofus keeps `layout = "scene"` and must
never gain flip/scroll behaviour**; its group-left, browser-right split is
exactly the fixed layout it has today. `code` is the first candidate for
`layout = "deck"` once terminal roles (LEO-308/311) exist to fill its
columns; nothing about this document wires that yet.

No horizontal scrolling and no more than one row, now or built toward later:
the desk is a physical constraint (one to three columns across one row),
not a policy that might grow. A later design may add horizontal scrolling
and per-monitor column counts; this contract does not anticipate it.

## Columns

A `deck` scene declares one to three columns, left to right by `order`,
each with a `share` (fraction of the row — the same arithmetic `scene`
already does for blocks; undeclared shares split evenly) and a
**subscription** (below) naming which windows fall into it.

```lua
code = {
  layout = "deck",
  columns = {
    { order = 1, share = 0.67, classes = { "Kitty%-Main", "Proj%-.*" } },
    { order = 2, share = 0.33, classes = { "zen%-twilight" } },
  },
},
```

A column with no windows currently subscribed is empty and gets no box (the
row's remaining columns take its place, same as `scene`'s fractions
renormalizing around what's present — see `hypr/scene/deck.lua`'s
`fractions`). Whether an empty column should hold its declared width instead
(so the row doesn't visibly reflow when a deck empties) is an open question
for the next chunk, not decided here.

## Membership is a subscription, not a class list

Three ways a window ends up in a column's deck, all through the same
matching function (`M.column_for`):

1. **A class subscribes.** `classes` on a column is the same
   literal-or-Lua-pattern grammar `scene` blocks already use
   (`hypr/scene/spec.lua`'s `class_matches`). Any window of that class joins
   the column's deck; this is how a class opts into scrolling without a
   per-window decision every time it opens.
2. **A window declares itself in.** A column names a `deck = "<name>"`
   identity; a window carrying the Hyprland tag `deck:<name>` joins that
   column regardless of its class. This reuses the identity-stamping
   mechanism a scene block's `slot` already relies on (LEO-364,
   `hypr/scene/identify.lua`) rather than inventing a second one — a project
   terminal or a companion window can be tagged into a specific column at
   launch without its class alone being enough to say which one.
3. **Unrelated windows are grouped by hand.** A column's `classes` may list
   several unrelated classes explicitly — Obsidian with Linear, say — the
   same way a `scene` block already allows more than one class in one
   block. "By hand" means the scene author writes both classes into the
   column; there is no live drag-to-group interaction in this contract.

A window matching no column's subscription is not part of the deck at all —
unlike `scene`'s stray handling, `deck` has no catch-all. A `deck` scene
that wants an overflow bucket declares a column for it explicitly.

The deck-tag route (2) is a self-declaration a window can only carry if
something stamped it — the tag vocabulary itself (which project → which
column) is terminal-role work, still Backlog (LEO-308/311) at the time this
chunk was written. This contract only defines how `deck.lua` reads the tag
once it exists; it does not invent a naming scheme for it.

## Scrolling

Within a column, membership order is arrival order — the same "join list"
`hypr/scene/group_adapters.lua`'s default adapter already keeps for a
group's `mod+j/k` order, not re-derived a second way. A **group** inside a
deck (an ordinary `scene` group — Hyprland's own grouped windows) collapses
to one deck entry, exactly like `scene`'s `collapse_groups`: scrolling past
a group shows or hides all of its members together, and its groupbar still
distinguishes them the way it does today.

A per-workspace, per-column **scroll index** (1-based, which member is
visible) is the only state `deck` adds, and it is session-only — the same
lifetime as `hypr/scene/order.lua`'s tile-swap override, never persisted,
dropped on reload. `M.clamp_scroll` re-derives a valid index every pass
against the column's current member count, so a window closing mid-column
can never strand the scroll position past the end (mirrors the reachability
guarantees the rest of the scene engine already gives — see
[desktop-model.md](desktop-model.md#transitions), "scrolling through the
slot updates recency").

**Recency**: desktop-model.md's Transitions section says scrolling through a
declared slot updates recency the way a hand-off's return edge does. This
contract does not yet decide what "recency" means for a deck column beyond
naming the open question — it is deferred to the chunk that wires the
provider and its state, since recency is about _when_ the scroll index
changes, not the pure arithmetic of where a box goes once it has.

## Why hidden windows are HELD, not placed off-screen

The natural-looking implementation places every deck member's box, moving
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

**Fallback adopted instead**: a deck's non-visible windows are not laid out
at all. `M.boxes` returns two things — boxes for the members currently
visible, and a flat list of addresses to **hold**: windows that must leave
the workspace's tiled set entirely, the same mechanism
`hypr/lib/minimize.lua` and `hypr/hyprfocus/hold.lua` already use (a special
workspace, e.g. `special:deck-hold`, or a per-scene hold area consistent
with desktop-model.md's "hold area" concept). Scrolling then means: move the
newly-visible window back onto the workspace, move the previously-visible
one to hold, and let `recalculate` place whatever is left — an ordinary
dispatch on `window.move`, not a geometry trick, and it is the **executor's**
job, not this module's: `M.boxes` only reports which addresses need to move,
never dispatches. That wiring — the hold workspace, the move on scroll, and
the bind that changes the scroll index — is explicitly out of scope for this
chunk (see "Next chunk" below).

## Navigation

Reuses the existing decision entirely; nothing new is invented for `deck`:

- `mod+h/l` moves across **columns** — the same tile-order decision
  `hypr/lib/nav.lua`'s `M.decide` already makes for `scene` blocks, since a
  deck column is a tile exactly like a block or a group is. Crossing into a
  column focuses its currently visible member (whatever the scroll index
  already names), the same way entering a group tile focuses its recorded
  member (LEO-380).
- `mod+j/k` moves **within** a column's deck, adapted to scrolling: instead
  of `hypr/lib/nav.lua`'s `M.window_neighbor` just changing focus among a
  stacked block's already-visible windows, it changes the column's scroll
  index by one (clamped, no wrap — same as `window_neighbor`'s edge
  behaviour today) and the newly-visible window is what receives focus.
  Inside a collapsed group entry, `mod+j/k` keeps stepping the group's own
  adapter order first (unchanged); only crossing the group's own boundary
  advances the column's scroll index.
- `mod+shift+h/l` and `mod+shift+j/k` are unassigned for `deck` in this
  contract — swapping column order or reordering a deck's stack are not
  decided here. Left to the wiring chunk once there is a concrete use for
  reordering a deck (`hypr/scene/order.lua`'s override may or may not be the
  right session-state shape for it).

None of the above is implemented yet: `hypr/lib/nav.lua` is unchanged by
this chunk. This section records the intended mapping for the chunk that
does wire binds.

## Is this a second layout, or does `scene` already do half the job?

Assessed, not resolved. `scene` and `deck` already share real machinery:
`hypr/scene/deck.lua` requires `hypr/scene/layout.lua` for `collapse_groups`
rather than reimplementing it, and `fractions`/the inner-area arithmetic are
line-for-line the same shape. Three things stop `deck` from being a branch
inside `layout.boxes` instead of a sibling module:

1. **Membership model.** A `scene` block's set is "every window this class
   matches, all shown, stacked if there's more than one." A `deck` column's
   set is "every window this class (or tag) matches, exactly one shown."
   These are different questions asked of the same match function
   (`block_for` vs `column_for`), not a flag on one function — one produces
   an all-of list, the other a which-one index.
2. **Visibility is stateful.** `scene` has no notion of "currently shown
   member" — every match gets a box, always. `deck` needs a scroll index
   per column, persisted across recalculates (session-only, but still
   state a pure `layout.boxes` call today never carries). Folding it in
   would mean every `scene` caller starts passing a `scroll` table it never
   uses.
3. **The hold contract is new.** `scene`'s pure function has no concept of
   "decide this window leaves the workspace" — every tile it is handed gets
   a box, full stop (`strays.lua`'s float decision is a _different_,
   open-time-only mechanism, not something `layout.boxes` decides). `deck`
   returning a hold list is a second return value `scene` callers have no
   use for and would have to ignore.

None of these make a merge impossible, only premature: the honest reading is
that `deck` reuses `scene`'s geometry primitives (gaps arithmetic, group
collapse, share normalization) already, through a plain `require`, and the
two-return (`boxes`, `hold`) is the actual new shape `scene` does not have a
slot for. If a future scene ever wants declared blocks that also scroll,
that is the moment to look again at merging the two into one function with
a `mode` per block rather than two sibling registrations — not before,
since nothing today asks for it.

## Bound

`hypr/scene/deck.lua`'s `M.MIN_COLUMNS = 1`, `M.MAX_COLUMNS = 3`. A
declaration naming more than three columns is silently truncated by
`M.boxes` (arithmetic, not validation — see "Every window of a block gets
placed" in scenes.md for the same non-refusing posture); a real editor-side
validator belongs with the rest of `resolve.validate`'s checks, not here.

## Wiring (this chunk)

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
  to walk — a column is a tile, same as a `scene` block or group, so
  `mod+h/l` needed no new decision, only a new way to build the tile list.
  Each tile also carries `plain` (arrival order, untouched) and `column`
  (its order), which `hypr/binds.lua`'s `mod+j/k` deck branch uses with the
  existing `M.window_neighbor` to compute the next visible member, store the
  new index, move it home, and focus it — the executor's job per "Why hidden
  windows are HELD" above, not a second navigation path.
- `mod+shift+h/l` and `mod+shift+j/k` stay unassigned for a deck scene, as
  this document already said — `hypr/binds.lua`'s swap/move-in-group
  handlers now check `deck.applies(scene)` and no-op rather than
  misinterpreting a deck's `columns` as `scene`'s `blocks`.
- `hypr/scene/spec.lua`'s `normalize` gained two additive fields —
  `layout` (`"scene"` default, `"deck"` opt-in) and `columns` (the same
  shallow order/share/classes/deck normalization `blocks` already gets) —
  the minimum schema support needed for a scene to describe a deck at all.
  No existing scene declares either, so every declared workspace's resolved
  spec is byte-for-byte what it was before this chunk.
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
  both admit `deck-test` for this reason, and a real scene adopting `deck`
  will need the same.

## Next chunk

- `layout = "deck"` on an actual scene (`code`, once LEO-308/311 land) and
  the `columns` declaration replacing its current fixed blocks.
- Structured logging events (`arrange`/`deck_scroll`, `arrange`/`deck_hold`)
  once LEO-352 lands a writer; until then the executor still only dispatches
  the moves `deck.lua`'s pure functions decide.
- `mod+shift+h/l`/`mod+shift+j/k` for a deck (column reorder / stack
  reorder) — still not decided.
- The two open questions this document already named: whether an empty
  column keeps its declared width, and what "recency" means for a scrolled
  column (desktop-model.md's Transitions section).
