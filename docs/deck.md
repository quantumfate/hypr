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

## A column holds things, not windows

**A thing is what a strip holds.** It is either a single window, or a whole
Hyprland group collapsed to one entry — never a bare member of a group. A
thing is determined one of two ways:

- **Declared**: an explicit class pattern or self-declared tag names which
  things join a column (the three subscription mechanisms below).
- **Derived**: when Hyprland forms a group among a column's subscribed
  windows, the group itself is the thing from that point on — it counts as
  **one** entry in the strip, never as N. The group keeps its own groupbar
  and its own internal navigation exactly as it does today
  ([scenes.md](scenes.md)'s "Group" and "Group adapters" sections,
  unchanged by anything in this document): `mod+j/k` inside a focused group
  still walks the group's members through its adapter, the same call it
  makes on a `stack` column. A `flip` column never reaches inside a group
  to flip its members individually — the group is indivisible from the
  strip's point of view, exactly as a folded `stack` role becomes one
  flip-reachable entry (columns.md §3, "Folding across presentations").

So a `flip` column's strip is a list of things — some single windows, some
whole groups — and the column shows exactly one thing at full column
height. Scrolling changes which thing is visible; it never reaches inside
the visible thing. What happens _inside_ a thing (a group's own
`mod+j/k` order, its groupbar, which member it remembers) is entirely
unchanged by this document and stays exactly as [scenes.md](scenes.md)
already describes — flip only ever operates one level up, on the strip of
things, not on a thing's own internals.

## What `flip` adds over `stack`

`stack` (`hypr/scene/layout.lua`, soon `stack.lua` per columns.md §12) is
one row of columns with fixed membership and no viewport: every window
subscribed to a column gets a box, all of the time, stacked vertically if
there is more than one. `flip` is the other presentation: **a strip of
things; the viewport shows exactly one thing, at full size.** A column
never partially shows a window and never shrinks one to fit; it shows
exactly one thing (a single window, or a whole collapsed group — "A column
holds things, not windows" above) at full column height, and scrolling
changes _which_ thing that is. The niri comparison is precise: a `flip`
column scrolls vertically the way a niri workspace scrolls horizontally —
one full-size occupant at a time, never a partial one clipped at the edge.

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

Three ways a window ends up in a `flip` column's deck — that is, becomes
part of one of the column's **things**, declared or derived per "A column
holds things, not windows" above — all through the same matching function
(`M.column_for`): this is column membership in general, not something
specific to `flip`; a `stack` column subscribes the same way. Subscription
names windows; whether those windows end up as one thing or several is then
decided by whether Hyprland groups them (derived), not by the subscription
itself.

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

Within a `flip` column, thing order is arrival order — the same "join
list" `hypr/scene/group_adapters.lua`'s default adapter already keeps for a
group's `mod+j/k` order, not re-derived a second way. A **group** inside a
flip column (an ordinary Hyprland-grouped set of windows) is one thing
(above), exactly like a `stack` column's `collapse_groups`: flipping past a
group shows or hides all of its members together, and its groupbar still
distinguishes them the way it does today. A `stack` role folded into a
`flip` column (columns.md §3, "Folding across presentations") collapses to
one thing the same way — the fold does not invent a second grouping rule
either.

A per-workspace, per-column **scroll index** (1-based, which thing is
visible) is the only state `flip` adds, and it is session-only — the same
lifetime as `hypr/scene/order.lua`'s tile-swap override, never persisted,
dropped on reload. `M.clamp_scroll` re-derives a valid index every pass
against the column's current thing count, so a window closing mid-column
can never strand the scroll position past the end (mirrors the reachability
guarantees the rest of the scene engine already gives — see
[desktop-model.md](desktop-model.md#transitions), "scrolling through the
slot updates recency"). A `flip` column that folds into another column
(columns.md §3) keeps its own scroll index as dead state until the fold
reverses; the target column's own index is what governs while the fold
stands.

### The slide is animated, like niri

Flipping is not a cut: the newly-visible thing slides into the column and
the previously-visible one slides out, the same "one strip, one occupant
sliding through" feel niri gives horizontal scrolling, turned vertical. The
motion does not need a bespoke animation of its own to get this: flipping
is executed as an ordinary `window.move` dispatch (see "Why hidden windows
are HELD" below) — moving the newly-visible thing onto the workspace and
the outgoing one onto the hold workspace — and Hyprland's existing
`windowsMove` animation leaf (`hypr/animations.lua`, `speed = 4`, default
bezier) already animates every window move on this desk, this one included.
The slide is therefore free: nothing in the `flip` module or its provider
schedules or times an animation, because the compositor already does that
for the dispatch it issues.

**Instant modes snap** by reading the same signal every other motion on
this desk already reads, not a second one invented for scrolling: AGENTS.md
lists motion as one of the properties a focus mode governs, and this desk
already has a working example of turning it off for one operation —
`hypr/services/alttab/alttab.lua` and `hypr/services/dofus/team.lua` both
wrap a move in `hl.config({ animations = { enabled = false } })` /
`{ enabled = true } }` to make that one move instant without touching any
other animation leaf. A mode whose motion setting says "no animation" makes
a flip's `window.move` land instantly for exactly the same reason those two
callers' moves do — there is one global animations switch, not a
per-feature one, so `flip` never needs its own "should this slide" check;
it dispatches the same way regardless, and the mode's own motion setting
(wherever it toggles that switch) decides whether the compositor honours
the `windowsMove` bezier or not.

**Where the motion lives, given non-visible things are parked off the
workspace**: entirely in the two ordinary `window.move` dispatches the
provider issues on a flip (the newly-visible thing home, the
previously-visible thing to hold — "Why hidden windows are HELD" below).
The compositor places windows; it does not place a "scroll," so there is no
separate off-workspace slide to animate — the thing moving to
`special:deck-hold` visibly slides there via the same `windowsMove` leaf
before it disappears from the workspace's tiled set, and the thing moving
home slides into the column's box the same way. Nothing about parking a
thing off-workspace bypasses the animation; it is a `window.move` like any
other; only its destination (a special workspace) is unusual.

### Fall-through: the visible thing disappears

When the thing currently visible in a `flip` column closes (or otherwise
leaves the column's subscription), the next thing in the strip — the
survivor immediately after it in arrival order, or the one immediately
before if none follows — takes the now-empty slot. This is a fall-through
scan of the arrival-order list, not a scroll: `M.clamp_scroll` already
holds this guarantee (a closed thing can never strand the index past the
end); a closed thing that is not at the end simply removes itself from the
list, and the same index now names whatever thing slid up into it.

**Focus does not follow.** Nothing about a thing falling into the visible
slot steals the keyboard. Hyprland's own close-focus behaviour decides
where focus actually goes when a window closes (typically the window that
was focused before it, or another member of the same former group) — that
is unrelated to and unaffected by which thing the column now happens to
show. A user scrolled to project B, closed a window inside project B's
thing, and project C's thing falls into view: focus stays wherever
Hyprland's own close handling put it, most likely still inside project B's
remaining windows if any are left, never silently redirected into project
C because its thing is now what is visible. This is deliberate, not an
oversight: a column's visible slot is a display fact, not a claim on the
user's attention, the same distinction desktop-model.md already draws
between "on screen" and "focused" for held/hidden members elsewhere in the
scene engine.

**If the strip is then empty** — the closed thing was the column's last —
the column shows nothing: an empty box, its width and position unchanged
(columns.md's resolver does not react to a column's live occupancy, only to
its declared role), waiting for the next window that subscribes to it. This
is the same "empty column keeps its declared width" position §9 already
left open in columns.md, read literally: nothing here forces the column to
collapse, fold, or borrow a neighbour's space just because it is
momentarily empty.

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

**Correction to an earlier revision of this document**: `mod+j/k` scrolling
a `flip` column was the prior design. The user's clarification supersedes
it — what is _inside_ a thing does not change, full stop, and a group's
`mod+j/k` is inside a thing. `mod+j/k` therefore keeps its existing meaning
on every column, `flip` included; scrolling the strip gets its own pair.

- `mod+h/l` moves across **columns** — the same tile-order decision
  `hypr/lib/nav.lua`'s `M.decide` already makes for a `stack` column, since
  every resolved column is a tile regardless of its presentation. Crossing
  into a `flip` column focuses its currently visible thing (whatever the
  scroll index already names) — if that thing is a group, the group's own
  recorded/adapter-picked member, the same way entering a group tile
  focuses its recorded member on a `stack` column today (LEO-380). No
  change from before this revision.
- `mod+j/k` moves **within a thing**, unchanged by `presentation` and
  unchanged by this document: inside a `stack` column it changes focus
  among already-visible windows (`hypr/lib/nav.lua`'s `M.window_neighbor`);
  inside a `flip` column's visible thing, if that thing is a group,
  `mod+j/k` steps the group's own adapter order — exactly the existing
  `focus_in_group` binding `hypr/binds.lua` already has for a `stack`
  column's group, called against the same class, unmodified. If the
  visible thing is a single window, `mod+j/k` is a no-op, the same as it
  is today for an ungrouped `stack` tile with one window. **`mod+j/k` never
  advances a `flip` column's scroll index** — that is the whole point of
  this correction: what is inside a thing stays exactly the way it
  currently is, and scrolling the strip is a different action with a
  different chord.
- **Scrolling the strip: `mod+ctrl+j/k`** (`config.main_mod .. " + " ..
config.primary_mod .. " + j/k"`, i.e. `SUPER+CTRL+J/K`) is the proposed
  new pair, flagged for veto since the user delegated the choice. Checked
  against `hypr/binds.lua`: `SUPER+CTRL` is otherwise only used inside
  submap-local entries (`project` submap's `p`, `d`), never as a
  `submap_universal` root chord, and `SUPER+ALT+J/K` is already claimed by
  the resize submap's directional entries — `SUPER+CTRL+J/K` collides with
  neither. Moves the scroll index by one (clamped, no wrap — the same edge
  behaviour `M.window_neighbor` already gives every other "next/prev, no
  wrap" decision on this desk) and dispatches the two `window.move`s
  "Flipping (scrolling)" describes; a no-op on a `stack` column, mirroring
  how `mod+shift+h/l`'s swap is already a no-op off a scene layout.
- `mod+shift+h/l` stays a no-op for a `flip` column, as before — swapping
  column order is not decided here.
- **`mod+shift+j/k` moves into the group submap.** Today's
  `move_in_group` (`hypr/binds.lua`, "move the focused window forward/back
  within its group") already only ever does something to a grouped window
  and no-ops otherwise; the user's decision folds it into the existing
  `group` reordering surface (`hypr/scene/group_adapters.lua`'s territory)
  as a submap entry rather than a bare top-level chord, freeing
  `SUPER+SHIFT+J/K` at the root. This is a keybind-wiring change, out of
  scope for this document (docs-only, no Lua touched here) — recorded so
  the wiring chunk implements exactly this, not a fresh decision.

None of the above is implemented yet: `hypr/lib/nav.lua` and
`hypr/binds.lua` are unchanged by this chunk. This section records the
intended mapping for the chunk that does wire binds.

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

**Superseded by this revision**: the `mod+j/k` deck branch described just
above — scrolling on `mod+j/k` — is the pre-correction wiring and is what
the "Navigation" section above now overrides. Nothing in this bullet list
has actually changed (docs-only chunk, no Lua touched), so the live desk
still behaves exactly as this section describes; the wiring chunk that
implements the "Navigation" section's `mod+ctrl+j/k` pair is what retires
this bullet's `mod+j/k` behaviour, not this document by itself.

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
- Wire `mod+ctrl+j/k` to scroll the strip and retire the `mod+j/k` deck
  branch, per the "Navigation" section's correction above.
- Move `mod+shift+j/k` (move-in-group) into the group submap, freeing the
  root chord, per the same section — `mod+shift+h/l` for a `flip` column
  (column reorder) is still not decided.
- The two open questions this document already named: whether an empty
  column keeps its declared width (this revision's "If the strip is then
  empty" answers this: yes, unconditionally), and what "recency" means for
  a scrolled column (desktop-model.md's Transitions section) — still open.
- The project-identity gap columns.md §11 flags: a per-launch project tag,
  distinct from a scene's fixed `slot`, needed before "one column = one
  project" can claim windows without a scene author naming a class list by
  hand.

## Extensibility: adding a fourth presentation later

The seam the user asked for — "a scalable module where we can add more
layouts on top later" — already exists in outline from columns.md §1's
output contract; this section makes it concrete for `flip` specifically, so
a third presentation is cheap to add.

**What a presentation module implements**, against the merged provider
(columns.md §12) rather than against the compositor directly:

```lua
-- hypr/scene/<name>.lua
M.applies(column)              -- true when this module should render `column`
M.boxes(column, tiles, area, opts)
  -- column:  a resolved column from columns.lua (`width`, `x_offset`, `members`)
  -- tiles:   the live windows subscribed to this column's members
  -- area:    the workspace's work area (gaps already applied)
  -- returns: box list for `ctx.targets`, plus an optional hold list
  --          (addresses that must leave the workspace's tiled set —
  --          `flip`'s second return value; `stack` returns none)
```

The merged provider (columns.md §12's `provider.lua`) dispatches to a
resolved column's own module by its `presentation` field — adding a fourth
presentation means adding one more branch there and one more value the
schema's `presentation` enum accepts; nothing about `columns.lua`,
`nav.lua`, or the schema's `roles` vocabulary (priority, `min_width`,
`fixed_width`, `align`, `fold_into`) changes to add it.

**What a layout author must NOT re-implement**, because the resolver and
the shared primitives already own it and a new presentation module reads
their output instead of recomputing it:

- **Arithmetic and gaps** — `columns.lua`'s `resolve` already produced
  `width`/`x_offset`; a presentation module never computes a share, a cost,
  or a gap itself (columns.md §1's closing paragraph: "sizing lives in
  exactly one place").
- **Folding** — a folded role's contents arrive already merged into
  `members`; a presentation module never asks "was this folded," only "what
  do my members contain now" (columns.md §3, "Folding across
  presentations": the target's presentation governs every member,
  automatically).
- **Group collapse** — `collapse_groups` (today in `layout.lua`, staying in
  `stack.lua` per columns.md §12) is the one place a Hyprland group becomes
  a single thing; `flip.lua` calls it rather than re-deriving it, and a
  fourth presentation does the same.
- **Ordering** — arrival order (`hypr/scene/group_adapters.lua`'s default
  join list) is the one sequencing rule every presentation reads; a new
  presentation does not invent its own thing-order.

What a presentation module _does_ own, and is the only genuinely new
surface a fourth layout adds: its own presentation-specific session state
(the way `flip` alone needs a scroll index — a hypothetical grid
presentation might need a 2D cursor instead) and its own `M.boxes` framing
of `members` inside the column's given `width`/`x_offset` (the way `flip`
shows one at a time and `stack` shows all of them vertically split). That
is deliberately the entire cost of a fourth layout: one module implementing
`applies`/`boxes`, one schema enum value, one provider branch — everything
upstream of the column (sizing, folding, gaps, group identity, ordering)
is already shared and untouched.
