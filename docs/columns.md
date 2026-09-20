# Columns

**Status: architecture of record for the resolver, not yet implemented.**
This is the deliverable for the first step of "one column core": the
resolver's inputs, the precedence rule, the folding ladder, and resolved
outcomes for every real scene on every host profile, reviewed before any Lua
changes. Read [scenes.md](scenes.md) and [deck.md](deck.md) first; this
widens both in place, the same way deck.md widened scenes.md, rather than
starting a fourth document.

## Why

`deck.lua` already carries its own copy of the share arithmetic
`layout.lua` has, reuses `layout.lua`'s group collapsing, and has no solo
framing at all — a lone window in a deck column is framed differently from a
lone tile in a scene. A third layout would copy the same four things again:
shares, gaps and solo framing, group collapse, column order. Underneath that
duplication is a three-body problem with no home today: what a scene
intends, what a monitor can actually give, and what happens when they
disagree. It leaks into shares, solo framing, `machines` overrides and host
data at once. This document gives that disagreement one owner.

## The model, in one sentence

A scene declares columns as **roles** — an order of importance, a minimum
viable width, and optionally a fixed width and an alignment, never a
percentage — and **one resolver** fits those roles into whatever width the
monitor actually has, by priority. `scene` and `deck` are **not** two
layouts a workspace picks between. **Presentation is a property of a
column**, declared per role alongside priority and width: `stack` (every
member tiled in the column at once — today's `scene` behaviour) or `flip`
(one member visible at full column height, flipped through — today's `deck`
behaviour). The user's own framing: the code workspace's left column holds
the dynamic project class and scrolls vertically, the scene also declares a
browser column beside it, and "that can happen with every row in the
layout" — any column may flip, independently of its neighbours. A single
workspace can therefore mix a `flip` column and a `stack` column side by
side; nothing about the model forces every column on a workspace to agree.

**A column is a strip of things.** Whatever a column shows — all at once
under `stack`, one at a time under `flip` — it shows **things**, not bare
windows. A thing is a single window, or a whole Hyprland group collapsed to
one entry; a group's members are never counted or shown as separate things,
because the group already keeps its own groupbar and its own internal
navigation, unchanged (see [deck.md](deck.md), "A column holds things, not
windows," for the full statement — this document only needs the term
defined once, since `members` in this section's output shape is a list of
things, not a list of windows). A thing is determined either by **declared**
membership (a column's class pattern or subscription tag names it in) or by
being **derived** (Hyprland forming a group among a column's subscribed
windows is what turns several windows into one thing).

**Does a scene-level layout name survive?** No. `layout = "scene" | "deck"`
on the scene document is retired along with the two-layout split it
implied. There is one column core; a workspace simply has columns, and each
column's own `presentation` field says how it shows its members. A
"workspace" in the old sense — pick `scene` or pick `deck` — no longer
exists as a decision point; what used to be that choice is now made once
per column, not once per workspace. (A workspace whose every column happens
to present `stack` behaves exactly like an old `layout = "scene"` scene; one
whose every column presents `flip` behaves like an old `layout = "deck"`
scene with one-to-three columns — both are degenerate cases of the same
model, not two code paths.)

## 1. Resolver: inputs and outputs

### Inputs

| Input             | Shape                                                                                                                                                                | Comes from                     |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `roles`           | ordered list, `{ priority: integer, min_width: number, fixed_width: number?, align: "left"\|"center"\|"right", fold_into: integer?, presentation: "stack"\|"flip" }` | the scene declaration          |
| `available_width` | number, px                                                                                                                                                           | the monitor, live              |
| `gaps_in`         | number, px                                                                                                                                                           | resolved host/monitor geometry |
| `gaps_out`        | number, px (already resolved per side, symmetric for this arithmetic)                                                                                                | resolved host/monitor geometry |

A **role** is the unit the resolver reasons about. It is what a `scene`
block or a `deck` column already is, minus the one field that has to go:
`share`. `priority` reuses the existing `order` field — the same integer
that fixes left-to-right position today also fixes importance, so the
declaration gains no new axis. `min_width` is new: the narrowest box the
role can present its content in without becoming unreadable. `fixed_width`
is new and optional: a role may declare an exact width instead of taking a
share of the slack — it neither shrinks below nor grows past that number
(§3 covers how it interacts with folding and the remaining slack). `align`
is new: `"left" | "center" | "right"`, **default `"left"`**. It is a general
column property, not a per-scene exception — every role carries it, whether
or not the role ever declares a fixed width. `fold_into` is new and
optional: a role may name another role's `priority` as an explicit fold
target; absent, the target is the role with the next lower `priority`
number (the next one up in importance) that still stands after this pass —
see §3. `fold_into` is declared now even though no real scene in §4 needs a
non-adjacent fold target yet — every fold below lands on "the next one up"
by default, but the field exists so a scene can name somewhere else the day
one needs to, without a schema change to add it. `presentation` is new and
**not optional**: every role states `"stack"` or `"flip"`, no default,
because a column's presentation is exactly as much the author's intent as
its priority — an unstated presentation would be a silent behaviour choice
the resolver has no business making. `presentation` is otherwise inert to
everything else in this document: it participates in no arithmetic in §3,
changes no cost, width, or slack calculation, and is carried through to the
resolver's output purely as data for the presentation layer to read (§1's
"Outputs" below, and see "Folding across presentations" under §3).

Why `align` defaults to `"left"`: it is a no-op for the overwhelming
majority of columns. A role that only ever receives its `min_width` (no
slack) or is the single flexible column absorbing all the slack ends up
filling exactly the space it is given, with nothing left over to place —
alignment has nothing to do. The field only has visible effect on a
fixed-width column, and only when that column's declared width leaves space
neither it nor any other surviving column claims (§3). Left matches the
existing left-to-right reading order this document already assumes
everywhere else (`priority` is a left-to-right sequence, `gaps_out` already
anchors the row from the left today), so a column that says nothing keeps
behaving exactly like a plain `min_width` column always has.

`available_width` is never read from `workspace_specs` or a host file. It is
the live monitor's tiled span — `hl.get_monitors()`'s width, minus that
monitor's resolved `gaps_out` on both sides — the same number
`hypr/scene/provider.lua` already hands `layout.boxes` as `ctx.area`. The
resolver takes it as one scalar; it does not re-derive it from geometry.

### Outputs

A list of **resolved columns**, ordered by priority, each:

```lua
{
  priority = 1,             -- the surviving column's own (leader) priority
  width = 4468,              -- px, this column's share of available_width
  x_offset = 0,              -- px, leading edge relative to the row's own start (§3)
  presentation = "stack",    -- the leader's own declared presentation (see below)
  members = { 1 },           -- role priorities folded into this column, self included —
                              -- each role contributes the things its own subscription
                              -- names, not raw windows (see "A column is a strip of
                              -- things" above)
}
```

`x_offset` is new relative to a pure share model, and it is almost always
`0`: it only moves when `align` places a fixed-width column (or an
all-fixed surviving row) somewhere other than hard against the leading edge
of the space it was given — see §3. `presentation` on the resolved column
is always the **leader's** own declared value (the un-folded role that
survived, priority-wise) — never a mix, and never the folded members' own
declared presentations, which stop mattering the moment they fold (see
"Folding across presentations" below). The presentation layer reads
`presentation` and `members` together to decide how a column's occupants
are shown: `"stack"` places every one of `members`'s underlying blocks'
tiles at once, folded-in ones stacking vertically inside the column's
share exactly like today's `M.stack` for an ungrouped block's extra windows
— folding does not invent a second stacking rule. `"flip"` shows exactly
one of `members`'s underlying columns' decks at a time, reachable by
scrolling — flipping already crosses group boundaries the same way
scrolling crosses a stack's members, so a folded role's deck is just
another thing the scroll index walks through. Neither presentation
otherwise looks at `roles`, `priority`, `min_width`, `fixed_width`, or
`align` again once the resolver has run; sizing lives in exactly one place.

This is the only new shape either layout gains. Everything else —
`collapse_groups`, `sequence`, `entry_key`/`reorder`, `M.stack`, the group
member-fanout in `boxes` — stays exactly as it is today, called with the
resolver's widths and offsets instead of `fractions`' shares.

## 2. Precedence

**Host < monitor < scene intent.** Concretely:

- **Host** supplies only fallback numbers nothing more specific overrides:
  `default_gaps` in `conf/base.lua` (the one place gap numbers are declared),
  and a `geometry_profiles` entry's `gaps_by_monitor` keyed by fingerprint,
  not by hostname (`hypr/lib/profile.lua`).
  Host data never states a width — `conf/hosts/*.lua` has never named a
  resolution, only monitor roles and outputs. This is the weakest voice
  because it is a guess made at declaration time about a machine that might
  change tomorrow.
- **Monitor** is `hl.get_monitors()`'s live width for the resolved output,
  read every `recalculate` (the same "read from the compositor rather than
  cached" rule `hypr/scene/provider.lua`'s `gaps()` already follows for
  `gaps_in`/`gaps_out`). This beats the host's fallback the instant a real
  monitor is attached, because the host's number was never anything but a
  guess.
- **Scene intent** — the role list — beats both. The resolver bends a
  scene's stated priority, minimums and fixed widths only when
  `available_width` genuinely cannot carry them (§3's ladder), never
  because a host file or a monitor profile says so. A host file has no
  field left that changes how a scene's columns size themselves; it can
  change the pixels the monitor reports through nothing (a host cannot lie
  about a live monitor) and it can change gaps, which is the only geometry
  a host or profile still owns.

Everything not stated is assumed: a role with no `fold_into` folds to its
priority-neighbour; a role with no `fixed_width` is flexible; a role with no
`align` behaves as `"left"`; a scene with no roles at all (`logs`, today)
has no resolver decision to make and the whole available width is one
implicit column, exactly as an empty `blocks` list already behaves.

## 3. The folding ladder

Given `roles` sorted by `priority` (1 = most important) and
`available_width` W:

1. Start with every role as its own candidate column. Each role's
   **effective width** is its `fixed_width` if declared, otherwise its
   `min_width` — a fixed-width role never asks for less than its declared
   number, so the ladder treats it exactly like a `min_width` role whose
   floor happens to equal its ceiling too.
2. Cost of N surviving columns = `sum(effective_width) + gaps_in * (N - 1)`.
3. If cost ≤ W, stop: every role gets its own column.
4. If cost > W, fold the **lowest-priority surviving role** into its fold
   target (declared `fold_into`, or absent that, the surviving role with the
   next-higher priority — "the next one up"). The folded role's members
   become part of the target column, reachable by flipping (`deck`) or
   stacked within the target's share (`scene`). Recompute cost with one
   fewer surviving column and repeat from step 2.
5. Stop folding when either the remaining set fits (step 3) or exactly one
   column remains.

**When even the one remaining column is below its own effective width** — a
role whose `min_width` (or `fixed_width`) exceeds W entirely, on a panel
narrower than the content was ever declared to need — the resolver does not
refuse and does not clip the workspace to nothing: the one surviving column
takes the whole of `available_width` anyway, whether or not that number was
declared fixed. There is nowhere left to fold to; giving it less than the
whole width would waste space fixing nothing, and giving it negative or
zero width is not an option a layout can place a window in. A fixed-width
role that cannot even fit alone stops being fixed at that point — its
declared number was a ceiling only while the screen could afford it; below
that, it degrades exactly like an ordinary `min_width` role would. This is
still a degenerate case, not a designed one (§9).

**Distribution once the surviving set is fixed**: every surviving column
gets exactly its effective width (its `fixed_width` when declared, else its
`min_width` — a folded-in target's own effective width does not grow to
absorb its folded members' minimums, because a folded role presents as a
stack/flip inside the target's existing share, not a wider box). The
remaining width — `available_width - cost` — is the **slack**, and it goes
entirely to the single highest-priority surviving column that does **not**
declare a `fixed_width`. This is the literal reading of the model's own
worked example ("5120 ultrawide — three columns; slack goes to the highest
priority") extended by one clause: slack goes to the highest-priority
column that can actually grow. A fixed-width column never grows past its
declared number no matter how high its priority — that is the entire point
of declaring one — so priority for slack purposes is computed only over the
flexible survivors.

**Folding across presentations.** A fold never asks the target to change its
own presentation, and it never asks the folded role to keep its own: **the
target's presentation governs every one of its members, folded-in ones
included.** Concretely:

- A `stack` column folding into another `stack` column is what §1 already
  describes: the folded role's tiles join the target's stack, one more
  block-worth of windows dividing the same share vertically.
- A `stack` column folding into a `flip` column: its tiles stop being
  simultaneously visible. They become one more thing the target's scroll
  index walks through — a folded-in stack of N windows is either flattened
  into N individually-reachable flip entries, or kept as one flip entry
  that itself shows all N stacked (equivalent to a `stack`-presented member
  nested one level inside a `flip` column) — this document takes the
  second reading, because it requires no new grouping rule: a folded
  `stack` role's members collapse to one flip-reachable entry the same way
  a Hyprland group already collapses to one deck entry (`deck.lua`'s
  `collapse_groups` reuse, unchanged). Scrolling to that entry shows every
  one of its stacked windows at once, in the same vertical split `M.stack`
  already computes for an ungrouped block's extra windows — the entry's box
  is the flip column's full width and height, and the stack renders inside
  it exactly as it would inside a standalone `stack` column of that width.
- A `flip` column folding into a `stack` column: the folded role's members
  lose their one-at-a-time framing and become simultaneously-tiled members
  of the target's stack, exactly like any other stack member. Nothing
  about "which one was visible" survives the fold — a flip column that
  folds away shows all of its members at once from that point on, the same
  as if they had always been separate stack entries. Any session-only
  scroll index the folded role had is simply not read; it is not an error,
  it is dead state until the fold reverses (the monitor widens again, the
  role gets its own column back), at which point the flip presentation
  resumes and the old index is still there to resume from — `clamp_scroll`
  already tolerates a stale index either way.
- A `flip` column folding into another `flip` column is exactly §1's
  existing description: the folded column's deck becomes one more thing
  the target's scroll index walks through, indistinguishable from the
  target's own original members once folded.

In every case the rule is one sentence: **a folded column's members join
the target column, and the target's presentation governs them.** The
folded role's own `presentation` is not consulted again once it has
folded — it is inert data on a role that no longer has its own column,
kept only so the fold can reverse cleanly when width returns.

**If every surviving column is fixed-width**, there is no flexible
recipient at all, and the slack goes unclaimed by any column's own box: the
whole row of resolved columns — each exactly its own effective width, laid
out left to right with `gaps_in` between them — is narrower than
`available_width`. That leftover is where `align` earns its keep, read off
the highest-priority surviving column: `align = "left"` (the default) packs
the row against the leading edge and leaves the leftover trailing after the
last column; `"right"` packs the row against the trailing edge, leftover
leading; `"center"` splits the leftover evenly on both sides of the row.
This is also the rule for a single fixed-width column that survives alone
(the common real case, §4's `dofus` laptop row): with nothing else to size
against, its own `align` decides whether it hugs the near edge, the far
edge, or sits centred in whatever width it did not ask for.

## 4. Worked outcomes, every real scene, all three profiles

Three real widths, computed once and reused for every scene below:

| Profile           | Output | Panel width                                                                                                                                      | Profile gaps                                    | `available_width` (`W`) | `gaps_in` |
| ----------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- | ----------------------- | --------- |
| Desktop primary   | DP-1   | 5120                                                                                                                                             | `desk-dual` primary: `gaps_out={12,80,72,80}`   | `5120 - 80*2 = 4960`    | 60        |
| Desktop secondary | DP-2   | 2560                                                                                                                                             | `desk-dual` secondary: `gaps_out={12,64,64,64}` | `2560 - 64*2 = 2432`    | 48        |
| Laptop            | eDP-1  | 1920×1200 (`tests/scene_layout_spec.lua`'s fixture work area; `conf/hosts/quantum-laptop.lua` states no literal resolution — see the note below) | `laptop-solo`: `gaps_out={12,48,48,48}`         | `1920 - 48*2 = 1824`    | 40        |

`conf/hosts/quantum-laptop.lua` never states a pixel size — geometry is
fingerprinted from live monitors (`hypr/lib/profile.lua`), never read off a
host file, which is the precedence rule in §2 working as intended. Stated
plainly, since it matters for every number below: **1920×1200 is an
assumption this document makes, not a measured fact.** 1920 is the only
concrete laptop width the repository states anywhere (`tests/host_geometry_publish_spec.lua`,
`tests/host_roles_publish_spec.lua`, `tests/profile_spec.lua` all pin it),
but none of them pin a height; 1200 is inferred from the one place a height
is pinned at all (`tests/scene_layout_spec.lua:398`'s fixture work area),
not independently confirmed against the real panel. If the laptop's actual
panel is a different aspect ratio, every laptop number in this section
needs re-deriving from the real height, not just the width.

The laptop's `secondary_monitor` (`HDMI-A-1`) is assumed disconnected below —
the ordinary "laptop alone" case. Every scene whose `workspace_specs` entry
names `monitor = "secondary"` (`obsidian-linear`, `media`, `logs`) then
resolves to the primary output by the existing fallback
(`hypr/hyprfocus/init.lua`'s `output_for`), so its resolver row below runs
against the laptop's `eDP-1` width like every other scene's.

**Correction note**: an earlier revision of the worked-outcome tables below
was computed against stale, pre-scale-up gap numbers (`gaps_in` 12/6/4 and,
for DP-2/Laptop, `available_width` 2532/1904) rather than the canonical
inputs table immediately above — the gap work that landed since widened
`default_gaps` and every `geometry_profiles` entry in `conf/base.lua`
roughly 5x. The tables below are recomputed against the canonical table's
real numbers (`gaps_in` 60/48/40, `available_width` 4960/2432/1824),
matching `hypr/scene/columns.lua`'s implementation of §1-§3 as pinned by
`tests/columns_spec.lua`. Every DP-1 row for a lone always-full column
(`steam-games`, `media`, `logs`) is unchanged, because that number never
depended on `gaps_in` and DP-1's `available_width` did not change; every
other cell changed by some amount, and where a fold newly appears or
disappears it is called out in the scene's own prose below — none do:
every scene folds in the same places it folded before, only with different
pixel counts, and nothing that used to fit on the ultrawide now folds.

Every column below presents `stack` (none of the eight declares `flip` on
any column yet — `flip` has no live column, per deck.md, now "flip.md" in
spirit though the file keeps its name). **Presentation does not change the
arithmetic**: the resolver's cost, fold, and slack-distribution rules in
§1–§3 never read `presentation` — it is carried through as inert data on
the resolved output, consulted only by the presentation layer after sizing
is already decided. So every row below stands exactly as computed whether
its column ends up `stack` or `flip`; this pass rechecked that claim by
inspection of `hypr/scene/columns.lua` (`presentation` does not exist as a
field the module reads anywhere in `resolve`, `cost`, `fold_one`, or the
distribution loop) rather than recomputing any number, and confirms it: no
number in any table below changes when a column's presentation changes.
`min_width`/`fixed_width` values below are this document's proposal, not
yet declared anywhere — they are the numbers the model asks a scene author
to add where `share` used to be, chosen here to match each block's existing
`share` weighting (or, for `dofus`, the width the user said they like
today) and to exercise the ladder somewhere real, per §9.

### `dofus` (roles: 1 Dofus group `fixed_width=3400`, `align=left`; 2 `zen-twilight-media` companion `min_width=480`)

The user's decision: Dofus keeps its current wide first column at a fixed
size, aligned left, because the user likes that width — not because
anything needs protecting. **OBS is unwired**: no layout rule in this model
exists to guard a capture crop any more, and Dofus's `fixed_width` is not
standing in for one. Screen-recording geometry, if it ever needs guarantees
this resolver does not give it, gets its own abstraction later; this
document does not define one.

| Profile | Resolved columns                              | Folded                                                                                                                                                                           |
| ------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DP-1    | 1: 3400px (fixed, left) · 2: 1500px           | none — cost of two (3400+480+60=3940) fits under W (4960); slack 1020 goes to the companion (the only flexible column)                                                           |
| DP-2    | 1: 2432px (clamped from fixed 3400, all of W) | 2 (companion) → 1 (group) — two-column cost (3928) exceeds W (2432); folded to one, but 3400 alone still exceeds 2432, so the degenerate clamp of §3 gives Dofus all of W anyway |
| Laptop  | 1: 1824px (clamped from fixed 3400, all of W) | 2 (companion) → 1 (group) — same shape as DP-2: two columns cost 3920 against W 1824, and 3400 alone still exceeds 1824                                                          |

**Wider gaps changed the numbers, not the shape**: DP-1 still gives Dofus
its full fixed width with the companion absorbing the (now smaller) slack;
DP-2 and the laptop still land in the degenerate clamp, because 3400px
alone was already wider than either panel's `W` under the old gaps and
stays wider now that gaps grew. Nothing here newly folds or newly stops
folding.

`align` never actually changes a number in this table: on DP-1 the
companion is flexible and absorbs the slack, so there is no unclaimed
leftover for `align` to place; on DP-2 and the laptop the fixed width
itself exceeds `W`, so the degenerate clamp consumes all of it and again
leaves nothing unclaimed. The field is declared, and does the work
described in §3, only for a hypothetical width between roughly 3400px and
3892px — wide enough to hold Dofus's fixed column alone but not wide enough
to also hold the companion — which none of the three real profiles above
land in. It is documented here anyway because a fourth profile (or a
`fixed_width` chosen differently) could land exactly there, and the model
needs to say what happens when it does.

### `pokemon` (roles: 1 emulator `min_width=700`, 2 chat slot `min_width=600`, 3 stream slot `min_width=600`)

| Profile | Resolved columns                | Folded                                                         |
| ------- | ------------------------------- | -------------------------------------------------------------- |
| DP-1    | 1: 3640px · 2: 600px · 3: 600px | none                                                           |
| DP-2    | 1: 1136px · 2: 600px · 3: 600px | none                                                           |
| Laptop  | 1: 1184px · 2: 600px            | 3 (stream) → 2 (chat) — three columns cost 1980 against W 1824 |

No role here declares a `fixed_width`, so the shape of this table is
unchanged by the `align`/`fixed_width` decisions this document folds in —
it exercises only the ladder, same as before. The numbers themselves do
move with the wider gaps: the laptop still folds (three columns now cost
1980 against a W of 1824, both different from the old 1908/1904), and
DP-1/DP-2 still keep all three columns, just with a smaller slack going to
the emulator column.

### `steam-games` (roles: 1 fullscreen `min_width=800`)

| Profile | Resolved columns | Folded                      |
| ------- | ---------------- | --------------------------- |
| DP-1    | 1: 4960px        | n/a — one role, never folds |
| DP-2    | 1: 2432px        | n/a                         |
| Laptop  | 1: 1824px        | n/a                         |

With solo framing retired, a lone flexible column simply absorbs all the
slack and fills `available_width` — the column is the sole flexible
survivor, so distribution in §3 hands it everything. That is what a
fullscreen game or video actually wants, and it needs no field declared to
get it; the old model's inconsistency (a lone column getting an arbitrary
decorative margin by default) is gone because there is no margin left to
apply.

### `media` (roles: 1 fullscreen `min_width=800`)

Same shape as `steam-games` — one always-full column, same numbers
(4960/2432/1824), for the same reason.

### `code` (roles: 1 editor group `min_width=1200`, 2 browser `min_width=800`)

| Profile | Resolved columns     | Folded                                                                                                                                           |
| ------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| DP-1    | 1: 4100px · 2: 800px | none                                                                                                                                             |
| DP-2    | 1: 1584px · 2: 800px | none                                                                                                                                             |
| Laptop  | 1: 1824px            | 2 (browser) → 1 (editor) — two columns cost 2040 against W 1824; the sole flexible survivor then absorbs all remaining slack (1200 + 624 = 1824) |

This is the model's own worked example (`editor ≥1200, browser ≥800`) run
against the real numbers instead of illustrative ones, and it reproduces the
stated outcome exactly: three tiers of nothing needed here (the real `code`
scene has two blocks, not the issue's illustrative three), ultrawide gives
the slack to the editor, and the laptop folds everything into one column
that then fills the whole panel — no solo margin subtracted, unlike the
version of this table under the retired model. The wider gaps do not change
the shape here, only the pixels: the laptop still folds, because 1200+800
plus even a 40px gap already exceeds 1824.

**Presentation for this scene, per the user's decision (§11 works this out
in full): the editor column presents `flip`, the browser column presents
`stack`.** None of the three numbers in the table above move for that
reason — presentation is not an input to this table's arithmetic (see the
note opening this section). What changes is only what happens _inside_ the
editor's box: instead of every project's windows tiling there at once, one
project's windows show at a time, flipped through. On the laptop row, where
editor and browser fold into one column, that one surviving column's
presentation is the editor's own (`flip`, since editor is the
higher-priority survivor and folding always takes the target's — here,
the sole survivor's — presentation, §3): the browser's tiles join the
flip as one more flip-reachable entry, shown as a stack-of-one inside that
entry per "Folding across presentations" in §3.

### `obsidian-linear` (roles: 1 Obsidian `min_width=900`, 2 Linear `min_width=700`)

| Profile | Resolved columns     | Folded                                                                |
| ------- | -------------------- | --------------------------------------------------------------------- |
| DP-1    | 1: 4200px · 2: 700px | none                                                                  |
| DP-2    | 1: 1684px · 2: 700px | none                                                                  |
| Laptop  | 1: 1084px · 2: 700px | none — two columns cost 1640 against W 1824, fits with 184px to spare |

Deliberately does **not** fold on the laptop, unlike `code` and `dofus`:
1600×1200-class panels are exactly where two readable panes of text still
fit side by side, which the ladder should not fold away just because it can.
That margin is now much tighter than the pre-scale-up numbers suggested —
184px of slack instead of 300px — because the wider `gaps_in` (40 vs the
stale 4) eats into it directly; it still clears the ladder's cutoff, but
it is worth watching if `min_width` for either block grows later.

### `proton` (roles: 1 mail `min_width=700`, 2 Pass companion `min_width=420`)

| Profile | Resolved columns     | Folded                          |
| ------- | -------------------- | ------------------------------- |
| DP-1    | 1: 4480px · 2: 420px | none                            |
| DP-2    | 1: 1964px · 2: 420px | none                            |
| Laptop  | 1: 1364px · 2: 420px | none — cost 1160 against W 1824 |

Never folds on any real profile — mail and a password manager are both
comfortably narrow, so this scene never exercises the ladder at all. Worth
keeping as the "boring" control case: not every scene needs to.

### `logs` (no `blocks` declared — tmux-managed)

No roles, so no resolver decision: an empty role list is the same "one
implicit column, the whole width" the resolver already gives an empty
`blocks` list today. All three profiles: one column, the full
`available_width` — 4960/2432/1824px, identical arithmetic to
`steam-games`/`media` above, for the same reason (no margin left to
subtract from a lone column). tmux owns the actual internal splits; the
resolver's output here is a box tmux draws inside, not a decision about
what's inside it.

## 5. What the retired/kept fields become

| Field                                | Fate                                         | Why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------ | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `blocks[].share` / `columns[].share` | **Retired.**                                 | Replaced by `min_width` + the priority already carried by `order`. A percentage could not express "never below this" or "give slack to the most important thing first" without a second, redundant field; a minimum can, and is the only number `fractions`/the new resolver actually needs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `machines`                           | **Retired.**                                 | No scene in the live declaration (`assets/hyprfocus.default.json`) sets it today — grep confirms zero uses. Its entire purpose was a per-host escape hatch for a sizing rule that could not otherwise see the monitor; the resolver reads the monitor directly (§2), so the escape hatch has nothing left to hatch out of.                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `solo_frame` / `SOLO_EXTRA`          | **Retired.**                                 | Solo framing existed to stop a lone column stretching across an ultrawide, by widening `gaps_out` around it — a decorative correction bolted onto gaps rather than the column's own declared intent, and one `deck` never got a copy of (§4's `steam-games`/`media`/`logs` rows show the actual behaviour change: a lone column now simply fills its available width). A `min_width` plus an optional `fixed_width` and `align` say the same thing directly, on the column that means it, without a hidden engine constant (`SOLO_EXTRA`, 180px) nobody could see from the declaration. Neither field nor constant survives into the resolver.                                                                                                                         |
| `strays`                             | **Collapses to a single `float: boolean?`.** | `"slot"` was already "an unmatched tiled window divides whatever the declared blocks leave" — that is now simply what happens to an untracked window: it joins the lowest-priority resolved column as an extra member, the same stacking `M.stack` already gives an ungrouped block's extra windows, no separate field needed to say so. `"float"` stays exactly as `hypr/scene/strays.lua` has it today — an open-time decision the resolver does not own or affect, unrelated to sizing. With `"slot"` carrying no configuration of its own, the field's only remaining job is a yes/no: does an untracked window float, or does it join the tiled ladder? A string with one live value is a boolean wearing a costume, so the schema bump collapses `strays: "slot" | "float"`to`float: boolean?`, default unset (falsy) meaning today's `"slot"` behaviour. |
| `fixed_width`                        | **New.**                                     | Lets a role opt out of receiving slack and declare an exact width instead — Dofus is the first user (§4). Interacts with the ladder and distribution exactly as §3 describes: it is the role's effective width for cost purposes, it never grows past its declared number, and it degrades to an ordinary floor if even it alone cannot fit.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `align`                              | **New.**                                     | General column property, default `"left"` (§1 explains the default). Only visibly changes a resolved layout when a fixed-width column (or an all-fixed surviving row) leaves width no column claims — §3, §4's `dofus` table.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `fold_into`                          | **New, declared now.**                       | Optional explicit fold target, on spec ahead of a real user, per the user's own decision — no scene in §4 needs one yet; every fold below lands on "the next one up" by default.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `presentation`                       | **New, replaces `layout`.**                  | `"stack" \| "flip"`, required, declared per role/column rather than once per scene. Retires the scene-level `layout = "scene" \| "deck"` field entirely (§0/the model statement) — a workspace no longer picks one of two layouts; each of its columns picks how it shows its own members. Carries through folding unchanged on the surviving (target) column and is otherwise inert to every arithmetic rule in §1–§3 (§4's opening note verifies this against `columns.lua`).                                                                                                                                                                                                                                                                                        |
| `layout` (scene-level)               | **Retired.**                                 | Was `"scene" \| "deck"` on the scene document (deck.md's opt-in). A scene no longer chooses a layout; it declares roles, each with its own `presentation`. `deck.applies(scene)` and every caller that branches on `scene.layout` lose their reason to exist (§12).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

## 6. Navigation and keybinds

Unchanged in shape, narrower in what they read. `hypr/lib/nav.lua`'s
`M.decide`, `M.tile_order`, `M.neighbor_tile`, `M.edge_tile` already treat "a
tile" as an opaque left-to-right sequence entry — they do not care today
whether a tile is a block, a group, or a stray, and they will not care
tomorrow whether it is one role or several folded together. `mod+h/l`
selects a resolved column; `mod+j/k` moves within it — within a folded
column that means stepping through its stacked members
(`scene`) or its combined deck (`deck`), the same "next/prev inside this
tile" decision `M.window_neighbor` already makes for a stacked block's extra
windows today. **Folding changes a column's membership, never what the keys
mean**: crossing into a folded column still focuses its current member the
same way crossing into a group tile does (LEO-380's `opts.enter`); nothing
in `nav.lua` needs to learn the word "fold." The resolver hands both layouts
a `members` list (§1) precisely so the existing sequencing code keeps
working unmodified — the same reason `deck.lua` already reuses
`layout.lua`'s `collapse_groups` instead of re-deriving it.

## 7. Making a fold visible

A window that used to have its own column and now shares one with something
else needs to not feel lost. Two existing surfaces carry this, neither new:

- **The bar's workspace strip** (`modules/bar/WorkspaceSwitch.js`,
  desktop-model.md's Quickshell section) already shows per-monitor workspace
  order; the same strip is where a resolved column's label would carry a
  fold marker — e.g. the column's usual identifier plus a compact "+N"
  badge naming how many roles are folded into it, so a glance at the bar
  says "this column is carrying more than it usually does" without opening
  anything.
- **Which-key**, which already filters `workspace › class › group ›
layout` to only what executes in the current context
  (desktop-model.md's Bindings section), is where the detail lives: a
  folded column's which-key entry names what it's carrying — "Browser
  (chat folded in)" rather than just "Browser" — the same place a user
  already looks to see what a key does before pressing it, so this needs no
  new UI surface, only a more specific label on a column whose `members`
  list has more than one entry.

Neither is wired by this document — this is the contract, per AGENTS.md's
"leave the engine untouched" posture for a chunk that is a document first.

## 8. Migration note (not performed here)

The scene declaration lives in `quickshell`'s `assets/hyprfocus.default.json`
(currently `"version": 5`) and would need a version bump — `6` — for the
resolver to have anything to read. Per scene, the change is mechanical and
uniform: every `blocks[].share` (and, once `deck` ships a real scene,
`columns[].share`) is replaced by `blocks[].min_width`, with `blocks[].fixed_width`
and `blocks[].align` available where a role wants them; `order` keeps its
existing meaning and gains the second one (§1); `machines` is dropped from
the schema (§5 — nothing currently populates it, so dropping it changes no
live behaviour); `solo_frame` is dropped (§5 — its effect is gone, not
replaced field-for-field); `strays` narrows from a two-value string to
`float: boolean?` (§5). Concretely, for every scene in the live declaration:

| Scene             | `share`/`solo_frame` fields removed | Fields added (this document's proposal, §4)                            |
| ----------------- | ----------------------------------- | ---------------------------------------------------------------------- |
| `dofus`           | 2 `share`, 1 `solo_frame`           | `min_width=480` (companion), `fixed_width=3400` + `align=left` (group) |
| `pokemon`         | 3 `share`                           | 3 `min_width` (700, 600, 600)                                          |
| `steam-games`     | 1 `share`                           | 1 `min_width` (800)                                                    |
| `media`           | 1 `share`                           | 1 `min_width` (800)                                                    |
| `code`            | 2 `share`                           | 2 `min_width` (1200, 800)                                              |
| `obsidian-linear` | 2 `share`                           | 2 `min_width` (900, 700)                                               |
| `proton`          | 2 `share`                           | 2 `min_width` (700, 420)                                               |
| `logs`            | 0                                   | 0 (no blocks declared)                                                 |

This chunk does **not** edit `assets/hyprfocus.default.json`, the store
schema, `hypr/scene/spec.lua`'s normalizer, or any Lua module — that is the
next chunk in the issue's own shape-of-work list ("the resolver as a pure
module with specs"), gated on this document being reviewed first.

## 9. Open questions

1. **Fixed-capture scenes beyond `fixed_width`.** OBS is unwired, and
   `dofus`'s `fixed_width` in §4 is declared because the user likes that
   width, not to protect a capture crop — no layout rule in this model
   exists for that purpose any more. If screen-recording geometry later
   needs a stronger guarantee than "this column's width never changes size"
   — an exact on-screen _position_, say, immune to gap or monitor changes —
   that is a capture concern, not a column-sizing one, and would need its
   own abstraction, out of scope here. Is "declare a `fixed_width`" enough
   for what capture will eventually need, or is a genuinely separate
   mechanism inevitable regardless of how this resolver ships?
2. **Does a lone column ever want to declare anything at all?** `steam-games`,
   `media`, and `logs` all now fill `available_width` automatically with
   zero fields declared (§4) — no more choosing a decorative default the
   way `solo_frame` used to require. Is "declare nothing, get full width"
   the right default forever, or will some future lone-column scene want a
   `fixed_width` + centred `align` on purpose (a deliberately framed single
   window, chosen rather than defaulted)? Nothing in §4 needs that today, so
   nothing here forces the question, but the vocabulary already supports it
   if one shows up.

## 10. Architecture of record

With the decisions folded in above, this document is the architecture of
record for the resolver: a column's declared vocabulary is exactly
priority (via `order`), minimum width, optional fixed width, alignment, and
optional fold target — the resolver owns everything else (gaps, slack
distribution, folding, solo behaviour, stray placement in the tiled
ladder). Nothing here is provisional pending a different model; disagreement
about the shape of the contract belongs in the issue, not in a future
rewrite of this file. Only the two questions in §9 are genuinely open, and
neither blocks starting the next chunk.

What the next chunk implements, in the order the issue's own shape-of-work
lists:

1. **The resolver as a pure module with specs** — the ladder, distribution,
   and alignment arithmetic in §1–§3, replacing the duplicated share
   arithmetic in `layout.lua` and `deck.lua`. **Done** (`hypr/scene/columns.lua`,
   `tests/columns_spec.lua`), ahead of the `presentation` field this revision
   adds — the module has no `presentation` concept yet; §12 says what closes
   that gap.
2. **`stack` and `flip` become presentations a column declares, read off
   resolved columns** — solo framing's old job disappears with it; both
   presentations read `members` and `x_offset` and otherwise keep their
   existing rendering. This is the point at which the scene-level `layout`
   field is actually deleted from the schema, not just documented as gone.
3. **Navigation and keybinds read resolved columns** — §6, unchanged in
   shape, narrower in what it reads.
4. **`flip` gets wired to the compositor per column** — only after the
   first three land, per the issue's own ordering. §12 gives the concrete
   file-level shape of this step.

## 11. The code workspace: a strip of projects, one column

The user's own worked example, made concrete, and corrected to the
strip-of-things model (§0's definition): a column is not a slot for one
project, it is **a strip that can hold several projects' things**, showing
one at a time when it presents `flip`. `code` today (§4) declares two
roles: an editor group and a browser. The decision this document folds in
changes what those two roles mean, not their widths:

- **What a project is, as a thing.** A project is one launch's worth of
  windows — its terminal(s), its editor, whatever else it opens — grouped
  into a single Hyprland group the moment more than one of them exists
  (the tmux-replacement work, LEO-311, separately: one group holds a
  project's kitty windows and destroys itself when the last closes). That
  group is exactly a "thing" per this document's §0 definition: derived,
  not declared, the instant Hyprland forms it, and indivisible from the
  project column's point of view from then on. A project with only one
  window open is still a thing — a thing of one, the degenerate case every
  `stack` column's ungrouped tile already handles the same way.
- **The project column presents `flip` and holds a strip, not a slot.**
  Several projects' things can be open at once, each one a separate entry
  in the column's arrival-order strip; `flip` shows exactly one project's
  things at full column height, and scrolling moves to the next project in
  the strip (deck.md's "Flipping (scrolling)", animated the way niri
  scrolls, per that document's correction).
- **The browser column presents `stack`**, beside it, unchanged from
  today's `code` — a companion browser is not a thing you flip through, it
  is a thing that sits next to whatever project is currently flipped in.

This is exactly the shape the model's "any column may flip" claim exists
to make ordinary: two adjacent columns in the same row, each with its own
presentation, sized by the same resolver, folding by the same ladder — §4's
`code` table already stands (its opening note re-confirms the arithmetic),
only the project column's _contents_ now flip between projects instead of
stacking a single project's windows (today's `code` scene has no
multi-project concept at all — the flip column, holding a strip of
project-things, is what makes "more than one project open at once"
representable without widening the column).

**"One column = one project" was the wrong reading; the right one is "one
column holds every open project, one visible at a time."** The user's own
words: a column holds things, "defined by an algorithm or explicitly
declared." Read literally, "one column = one project" never meant a column
is retired and rebuilt per project — it meant the reverse of what the
phrase suggests: **one column is where a project lives**, for however many
projects the strip currently holds, each one a thing the column's scroll
index walks through. Concretely, without hard-coding a single project:

- A column's membership is already a **subscription**, not a fixed list —
  deck.md's three mechanisms (class pattern, a self-declared `deck:<name>`
  tag reusing the LEO-364 identity-stamp, or hand-grouped classes) are the
  right primitive, unmodified. "Which projects populate the strip" is not a
  new membership mechanism; it is however many separate **things** the
  existing subscription mechanism happens to admit at once — the strip's
  length is just however many projects are currently open, not a number
  the column declares.
- What is missing is a **project identity**, analogous to a scene's
  `slot`: today's `slot:<slot>` tag names a fixed string chosen at scene
  declaration time (`pokemon/chat`, `pokemon/stream`). A project column
  instead needs a tag whose value is chosen **per launch**, from whatever
  project the terminal/editor was opened against (a directory name, a repo
  slug — this document does not decide which), and every window belonging
  to that same launch needs to carry the _same_ value so Hyprland's own
  grouping (which is what turns a launch's windows into one thing) and the
  column's subscription (`deck:<column-name>` today, or its successor field
  once `layout`/`deck` naming is retired per §12) can each do their part —
  grouping making the launch one thing, the subscription admitting that
  thing into the strip — without the column declaration ever naming a
  specific project.
- Concretely, this needs from the identity/tag work (LEO-364's
  `hypr/scene/identify.lua` and whatever terminal-role work LEO-308/311
  eventually land): a stamping rule keyed on **which project a window was
  launched for**, not only on **which slot in a scene** it fills — the two
  are different axes today (`slot` disambiguates _within_ one block's
  class; a project tag needs to disambiguate _across_ however many
  concurrent projects a flip column's strip ever holds at once) and nothing
  in `identify.lua` currently reads or assigns the second axis. Flagged
  here because it blocks "a column holds every open project" specifically,
  not because it blocks anything in this document's own model: the
  resolver and the fold ladder do not care what a column's things' tags
  mean, only that `column_for`-equivalent matching can group them into the
  strip.
- Until that identity work lands, a project column is declared the way
  deck.md's example already shows: an explicit `classes` list naming the
  project's terminal/editor classes by hand, admitting whichever concretely
  named projects happen to be running into the strip — functionally
  correct for a small, known set of projects, just not yet "any project,
  automatically."
- **Fall-through applies here directly** (deck.md's "Fall-through" section):
  when a project's last window closes (its group destroys itself per
  LEO-311), that thing leaves the strip; whichever project thing is next in
  arrival order falls into the visible slot, and focus does not follow it —
  the user is left wherever Hyprland's own close-focus rule puts them, not
  silently dropped into a different project's windows because that
  project's thing now happens to be what the column shows. If the project
  that closed was the strip's last thing, the column shows an empty box,
  its width unchanged, until the next project opens.

## 12. What the already-merged code becomes

Concrete, because the next chunk implements from this. Five files exist
today from the `deck` chunk that landed before this revision; none of them
yet know about `presentation` as a column property, because they predate
this decision. What each becomes:

| File                           | Fate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hypr/scene/layout.lua`        | **Becomes the `stack` presentation module, folded into the column core's caller.** Its pure geometry (`collapse_groups`, `sequence`, `M.stack`'s vertical split, `M.reorder`/`entry_key`) is exactly right and stays; what it loses is the sizing it currently does itself (`fractions`, `SOLO_EXTRA`/`solo_frame`) — that arithmetic is `columns.lua`'s job now, called once per workspace, not once per scene. Renamed `hypr/scene/stack.lua` to name what it actually is once `scene` is no longer the only presentation; its public surface (`M.boxes(scene_or_column, tiles, area, opts)`) takes a resolved column's `width`/`x_offset` instead of computing its own share.                                                                                                                                                                                                                                                                                                                                                                      |
| `hypr/scene/deck.lua`          | **Becomes the `flip` presentation module: `hypr/scene/flip.lua`.** Its scroll-clamping, group-collapse-into-one-flip-entry, and hold-list-reporting logic (`M.boxes`'s two return values) are exactly the `"flip"` half of the column core and stay almost verbatim; what it loses is `fractions`/column-width normalization (§1's `width`/`x_offset` replace it) and the 1–3-column bound as a _layout_ concept — a flip presentation now sizes whatever single column the resolver handed it, not a whole row it owns alone. Gains nothing new for fall-through: `M.clamp_scroll` already re-derives a valid index against the current thing count every pass, which is the entire mechanism deck.md's "Fall-through" section needs — a closed thing's disappearance is just one fewer thing in the list the next `recalculate` sees, and the module never dispatches a focus change, only box/hold decisions, so "focus does not follow" costs this module nothing to satisfy: it was already true because `flip.lua` has no focus opinion at all. |
| `hypr/scene/deck_provider.lua` | **Merges into one provider that reads presentation per column.** There is no longer a separate `hl.layout.register("deck", ...)` beside `hl.layout.register("scene", ...)` — one registration (name TBD, likely just `hl.layout.register("columns", ...)` or kept as `"scene"` for compatibility, an open point for the implementing chunk) resolves a workspace's columns once via `columns.resolve`, then for each resolved column calls `stack.boxes` or `flip.boxes` depending on that column's `presentation`, merging both modules' box lists and dispatching `flip.lua`'s hold list exactly as `deck_provider.lua` does today. `HOLD`/`special:deck-hold` and the move-home dispatch pattern carry over unchanged.                                                                                                                                                                                                                                                                                                                             |
| `hypr/scene/deck_scroll.lua`   | **Stays, renamed `hypr/scene/scroll.lua`.** Its shape (session-only index keyed by scene name then column order, never `$QF_STORE`) is presentation-agnostic already — it does not care that today only `deck`-layout scenes ever read it; once any column on any workspace can be `flip`, the same per-column keying already works unmodified. Only the name changes, to stop implying it is deck-specific.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `hypr/scene/provider.lua`      | **Merges into the same single provider `deck_provider.lua` becomes.** Its own `recalculate`, `spec_gaps`/`gaps` fallback-ladder, `scene_for`, `window_tile`/`tiles_of` stay as the shared window-gathering half every column needs regardless of presentation; its `layout.boxes` call is replaced by `columns.resolve` + the per-column `stack.boxes`/`flip.boxes` dispatch above. This file (or its merged successor) is the one that survives under the registered name; `deck_provider.lua`'s file disappears once merged in.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

Net shape: **five files become three** — one resolver (`columns.lua`,
already landed), one provider (the merge of `provider.lua` +
`deck_provider.lua`), and two presentation modules (`stack.lua` from
`layout.lua`, `flip.lua` from `deck.lua`), plus the renamed `scroll.lua`.
`hypr/lib/nav.lua`'s `deck_tile_order` and `hypr/binds.lua`'s deck branch
(§6) stop checking `deck.applies(scene)` — a scene has no `layout` field to
check any more — and instead ask a resolved column its own `presentation`
to decide which binding does what. Per deck.md's "Navigation" correction:
`mod+j/k` never checks `presentation` for _whether to scroll_ — it always
steps within the focused thing (a group's adapter order, unchanged, on any
presentation) — the only thing it reads `presentation` for, going forward,
is which decision function to call (`stack`'s `window_neighbor` vs a
group's `order`, already the same call today). Scrolling a `flip` column's
strip is `mod+ctrl+j/k`'s own branch, gated on `presentation == "flip"`,
calling `flip.lua`'s scroll-index step and the same two `window.move`
dispatches `deck_provider.lua` issues today (unchanged by the merge,
animated per `windowsMove` per deck.md); `mod+shift+j/k` (group reorder)
moves into the group submap and stops being a root chord, per the same
correction. `hypr/scene/spec.lua`'s schema loses `layout` and gains
`presentation` per role (§8's migration table, superseded by `presentation`
replacing what would have been a `columns[].layout` compromise). None of
this is performed here — this section is the concrete map, not the diff.
