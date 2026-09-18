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
monitor actually has, by priority; `scene` and `deck` become two ways of
presenting whatever the resolver decided.

## 1. Resolver: inputs and outputs

### Inputs

| Input             | Shape                                                                                                                                 | Comes from                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `roles`           | ordered list, `{ priority: integer, min_width: number, fixed_width: number?, align: "left"\|"center"\|"right", fold_into: integer? }` | the scene declaration          |
| `available_width` | number, px                                                                                                                            | the monitor, live              |
| `gaps_in`         | number, px                                                                                                                            | resolved host/monitor geometry |
| `gaps_out`        | number, px (already resolved per side, symmetric for this arithmetic)                                                                 | resolved host/monitor geometry |

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
one needs to, without a schema change to add it.

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
  priority = 1,          -- the surviving column's own priority
  width = 4468,           -- px, this column's share of available_width
  x_offset = 0,           -- px, leading edge relative to the row's own start (§3)
  members = { 1 },        -- role priorities folded into this column, self included
}
```

`x_offset` is new relative to a pure share model, and it is almost always
`0`: it only moves when `align` places a fixed-width column (or an
all-fixed surviving row) somewhere other than hard against the leading edge
of the space it was given — see §3. `scene` reads `members` to decide which
of a column's underlying blocks' tiles get placed (a folded-in block's
windows stack vertically inside the column's share, exactly like today's
`M.stack` for an ungrouped block's extra windows — folding does not invent
a second stacking rule). `deck` reads `members` to decide which underlying
columns' decks are reachable by flipping inside that one physical column —
flipping already crosses group boundaries the same way scrolling crosses a
stack's members, so a folded role's deck is just another thing the scroll
index walks through. Neither layout otherwise looks at `roles`, `priority`,
`min_width`, `fixed_width`, or `align` again once the resolver has run;
sizing lives in exactly one place.

This is the only new shape either layout gains. Everything else —
`collapse_groups`, `sequence`, `entry_key`/`reorder`, `M.stack`, the group
member-fanout in `boxes` — stays exactly as it is today, called with the
resolver's widths and offsets instead of `fractions`' shares.

## 2. Precedence

**Host < monitor < scene intent.** Concretely:

- **Host** supplies only fallback numbers nothing more specific overrides:
  `DEFAULT_GAPS_OUT` in `conf/host.lua`, and a `geometry_profiles` entry's
  `gaps_by_monitor` keyed by fingerprint, not by hostname (`hypr/lib/profile.lua`).
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

| Profile           | Output | Panel width                                                                                                                                      | Profile gaps                                 | `available_width` (`W`) | `gaps_in` |
| ----------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------- | ----------------------- | --------- |
| Desktop primary   | DP-1   | 5120                                                                                                                                             | `desk-dual` primary: `gaps_out={8,80,80,80}` | `5120 - 80*2 = 4960`    | 12        |
| Desktop secondary | DP-2   | 2560                                                                                                                                             | `desk-dual` secondary: `gaps_out=14`         | `2560 - 14*2 = 2532`    | 6         |
| Laptop            | eDP-1  | 1920×1200 (`tests/scene_layout_spec.lua`'s fixture work area; `conf/hosts/quantum-laptop.lua` states no literal resolution — see the note below) | `laptop-solo`: `gaps_out=8`                  | `1920 - 8*2 = 1904`     | 4         |

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

Every scene below is `layout = "scene"` (none of the eight declares
`layout = "deck"` yet — `deck` has no wired scene, per deck.md). The
resolver's arithmetic is identical either way; only which windows a column
shows differs. `min_width`/`fixed_width` values below are this document's
proposal, not yet declared anywhere — they are the numbers the model asks a
scene author to add where `share` used to be, chosen here to match each
block's existing `share` weighting (or, for `dofus`, the width the user
said they like today) and to exercise the ladder somewhere real, per §9.

### `dofus` (roles: 1 Dofus group `fixed_width=3400`, `align=left`; 2 `zen-gaming-media` companion `min_width=480`)

The user's decision: Dofus keeps its current wide first column at a fixed
size, aligned left, because the user likes that width — not because
anything needs protecting. **OBS is unwired**: no layout rule in this model
exists to guard a capture crop any more, and Dofus's `fixed_width` is not
standing in for one. Screen-recording geometry, if it ever needs guarantees
this resolver does not give it, gets its own abstraction later; this
document does not define one.

| Profile | Resolved columns                              | Folded                                                                                                                                                                           |
| ------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DP-1    | 1: 3400px (fixed, left) · 2: 1548px           | none — cost of two (3400+480+12=3892) fits under W (4960); slack 1068 goes to the companion (the only flexible column)                                                           |
| DP-2    | 1: 2532px (clamped from fixed 3400, all of W) | 2 (companion) → 1 (group) — two-column cost (3886) exceeds W (2532); folded to one, but 3400 alone still exceeds 2532, so the degenerate clamp of §3 gives Dofus all of W anyway |
| Laptop  | 1: 1904px (clamped from fixed 3400, all of W) | 2 (companion) → 1 (group) — same shape as DP-2: two columns cost 3884 against W 1904, and 3400 alone still exceeds 1904                                                          |

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
| DP-1    | 1: 3736px · 2: 600px · 3: 600px | none                                                           |
| DP-2    | 1: 1320px · 2: 600px · 3: 600px | none                                                           |
| Laptop  | 1: 1300px · 2: 600px            | 3 (stream) → 2 (chat) — three columns cost 1908 against W 1904 |

No role here declares a `fixed_width`, so this table is unchanged by the
decisions this document folds in — it exercises only the ladder, same as
before.

### `steam-games` (roles: 1 fullscreen `min_width=800`)

| Profile | Resolved columns | Folded                      |
| ------- | ---------------- | --------------------------- |
| DP-1    | 1: 4960px        | n/a — one role, never folds |
| DP-2    | 1: 2532px        | n/a                         |
| Laptop  | 1: 1904px        | n/a                         |

With solo framing retired, a lone flexible column simply absorbs all the
slack and fills `available_width` — the column is the sole flexible
survivor, so distribution in §3 hands it everything. That is what a
fullscreen game or video actually wants, and it needs no field declared to
get it; the old model's inconsistency (a lone column getting an arbitrary
decorative margin by default) is gone because there is no margin left to
apply.

### `media` (roles: 1 fullscreen `min_width=800`)

Same shape as `steam-games` — one always-full column, same numbers
(4960/2532/1904), for the same reason.

### `code` (roles: 1 editor group `min_width=1200`, 2 browser `min_width=800`)

| Profile | Resolved columns     | Folded                                                                                                                                           |
| ------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| DP-1    | 1: 4148px · 2: 800px | none                                                                                                                                             |
| DP-2    | 1: 1726px · 2: 800px | none                                                                                                                                             |
| Laptop  | 1: 1904px            | 2 (browser) → 1 (editor) — two columns cost 2004 against W 1904; the sole flexible survivor then absorbs all remaining slack (1200 + 704 = 1904) |

This is the model's own worked example (`editor ≥1200, browser ≥800`) run
against the real numbers instead of illustrative ones, and it reproduces the
stated outcome exactly: three tiers of nothing needed here (the real `code`
scene has two blocks, not the issue's illustrative three), ultrawide gives
the slack to the editor, and the laptop folds everything into one column
that then fills the whole panel — no solo margin subtracted, unlike the
version of this table under the retired model.

### `obsidian-linear` (roles: 1 Obsidian `min_width=900`, 2 Linear `min_width=700`)

| Profile | Resolved columns     | Folded                                                                |
| ------- | -------------------- | --------------------------------------------------------------------- |
| DP-1    | 1: 4248px · 2: 700px | none                                                                  |
| DP-2    | 1: 1826px · 2: 700px | none                                                                  |
| Laptop  | 1: 1200px · 2: 700px | none — two columns cost 1604 against W 1904, fits with 300px to spare |

Deliberately does **not** fold on the laptop, unlike `code` and `dofus`:
1600×1200-class panels are exactly where two readable panes of text still
fit side by side, which the ladder should not fold away just because it can.

### `proton` (roles: 1 mail `min_width=700`, 2 Pass companion `min_width=420`)

| Profile | Resolved columns     | Folded                          |
| ------- | -------------------- | ------------------------------- |
| DP-1    | 1: 4528px · 2: 420px | none                            |
| DP-2    | 1: 2106px · 2: 420px | none                            |
| Laptop  | 1: 1480px · 2: 420px | none — cost 1124 against W 1904 |

Never folds on any real profile — mail and a password manager are both
comfortably narrow, so this scene never exercises the ladder at all. Worth
keeping as the "boring" control case: not every scene needs to.

### `logs` (no `blocks` declared — tmux-managed)

No roles, so no resolver decision: an empty role list is the same "one
implicit column, the whole width" the resolver already gives an empty
`blocks` list today. All three profiles: one column, the full
`available_width` — 4960/2532/1904px, identical arithmetic to
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
   arithmetic in `layout.lua` and `deck.lua`.
2. **`scene` and `deck` become presentations over resolved columns** —
   solo framing's old job disappears with it; both layouts read `members`
   and `x_offset` and otherwise keep their existing rendering.
3. **Navigation and keybinds read resolved columns** — §6, unchanged in
   shape, narrower in what it reads.
4. **`deck` gets wired to the compositor** — only after the first three
   land, per the issue's own ordering.
