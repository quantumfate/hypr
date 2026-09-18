# Columns

**Status: contract, not yet implemented.** This is the deliverable for the
first step of "one column core": the resolver's inputs, the precedence rule,
the folding ladder, and resolved outcomes for every real scene on every host
profile, reviewed before any Lua changes. Read [scenes.md](scenes.md) and
[deck.md](deck.md) first; this widens both in place, the same way deck.md
widened scenes.md, rather than starting a fourth document.

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

A scene declares columns as **roles** — an order of importance and a minimum
viable width, never a percentage — and **one resolver** fits those roles into
whatever width the monitor actually has, by priority; `scene` and `deck`
become two ways of presenting whatever the resolver decided.

## 1. Resolver: inputs and outputs

### Inputs

| Input             | Shape                                                                         | Comes from                            |
| ----------------- | ----------------------------------------------------------------------------- | ------------------------------------- |
| `roles`           | ordered list, `{ priority: integer, min_width: number, fold_into: integer? }` | the scene declaration                 |
| `available_width` | number, px                                                                    | the monitor, live                     |
| `gaps_in`         | number, px                                                                    | resolved host/monitor geometry        |
| `gaps_out`        | number, px (already resolved per side, symmetric for this arithmetic)         | resolved host/monitor geometry        |
| `solo_frame`      | boolean, default `true`                                                       | the scene declaration                 |
| `solo_extra`      | number, px, default `SOLO_EXTRA` (180)                                        | engine constant, unchanged from today |

A **role** is the unit the resolver reasons about. It is what a `scene`
block or a `deck` column already is, minus the one field that has to go:
`share`. `priority` reuses the existing `order` field — the same integer
that fixes left-to-right position today also fixes importance, so the
declaration gains no new axis. `min_width` is new: the narrowest box the
role can present its content in without becoming unreadable. `fold_into` is
new and optional: a role may name another role's `priority` as an explicit
fold target; absent, the target is the role with the next lower `priority`
number (the next one up in importance) that still stands after this pass —
see §3.

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
  members = { 1 },        -- role priorities folded into this column, self included
}
```

`scene` reads `members` to decide which of a column's underlying blocks'
tiles get placed (a folded-in block's windows stack vertically inside the
column's share, exactly like today's `M.stack` for an ungrouped block's
extra windows — folding does not invent a second stacking rule). `deck`
reads `members` to decide which underlying columns' decks are reachable by
flipping inside that one physical column — flipping already crosses group
boundaries the same way scrolling crosses a stack's members, so a folded
role's deck is just another thing the scroll index walks through. Neither
layout otherwise looks at `roles`, `priority`, or `min_width` again once the
resolver has run; sizing lives in exactly one place.

This is the only new shape either layout gains. Everything else —
`collapse_groups`, `sequence`, `entry_key`/`reorder`, `M.stack`, the group
member-fanout in `boxes` — stays exactly as it is today, called with the
resolver's widths instead of `fractions`' shares.

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
  scene's stated priority and minimums only when `available_width` genuinely
  cannot carry them (§3's ladder), never because a host file or a monitor
  profile says so. A host file has no field left that changes how a scene's
  columns size themselves; it can change the pixels the monitor reports
  through nothing (a host cannot lie about a live monitor) and it can change
  gaps, which is the only geometry a host or profile still owns.

Everything not stated is assumed: a role with no `fold_into` folds to its
priority-neighbour; a scene with no roles at all (`logs`, today) has no
resolver decision to make and the whole available width is one implicit
column, exactly as an empty `blocks` list already behaves.

## 3. The folding ladder

Given `roles` sorted by `priority` (1 = most important) and
`available_width` W:

1. Start with every role as its own candidate column.
2. Cost of N surviving columns = `sum(min_width) + gaps_in * (N - 1)`.
3. If cost ≤ W, stop: every role gets its own column.
4. If cost > W, fold the **lowest-priority surviving role** into its fold
   target (declared `fold_into`, or absent that, the surviving role with the
   next-higher priority — "the next one up"). The folded role's members
   become part of the target column, reachable by flipping (`deck`) or
   stacked within the target's share (`scene`). Recompute cost with one
   fewer surviving column and repeat from step 2.
5. Stop folding when either the remaining set fits (step 3) or exactly one
   column remains.

**When even the one remaining column is below its own minimum** — a role
whose `min_width` exceeds W entirely, on a panel narrower than the content
was ever declared to need — the resolver does not refuse and does not
clip the workspace to nothing: the one surviving column takes the whole of
`available_width` anyway. There is nowhere left to fold to; giving it less
than the whole width would waste space fixing nothing, and giving it
negative or zero width is not an option a layout can place a window in.
This is a degenerate case, not a designed one — see the open questions
(§9) for what should happen next (a warning surface, most likely, not
silent truncation forever).

**Distribution once the surviving set is fixed**: every surviving column
gets exactly its `min_width` (or, for a folded-in target, its own
`min_width` — a folded role's minimum does not add to its target's,
because it presents as a stack/flip inside the target's existing share, not
a wider box). All remaining width — `available_width - cost` — goes
entirely to the single highest-priority surviving column. This is the
literal reading of the worked example in the model's own writeup ("5120
ultrawide — three columns; slack goes to the highest priority") and it
replaces `fractions`' proportional-split arithmetic in both `layout.lua`
and `deck.lua` with one rule that does not need a second declared number
per role.

**Solo framing** is the resolver refusing to let a single surviving column
fill the entire monitor: when exactly one column survives (whether because
the scene only ever declared one, or because folding collapsed everything
into it) and the scene's `solo_frame` is not `false`, `gaps_out` widens by
`solo_extra` before the column's width is computed — identical arithmetic to
today's `layout.lua`, now shared by `deck` for the first time. A scene that
needs edge-to-edge geometry regardless of column count (Dofus, whose tile is
a fixed capture region — see §5's note on `solo_frame`) sets `solo_frame =
false`, same field, now honoured by both layouts.

## 4. Worked outcomes, every real scene, all three profiles

Three real widths, computed once and reused for every scene below:

| Profile           | Output | Panel width                                                                                                                                      | Profile gaps                                 | `available_width` (`W`) | `gaps_in` |
| ----------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------- | ----------------------- | --------- |
| Desktop primary   | DP-1   | 5120                                                                                                                                             | `desk-dual` primary: `gaps_out={8,80,80,80}` | `5120 - 80*2 = 4960`    | 12        |
| Desktop secondary | DP-2   | 2560                                                                                                                                             | `desk-dual` secondary: `gaps_out=14`         | `2560 - 14*2 = 2532`    | 6         |
| Laptop            | eDP-1  | 1920×1200 (`tests/scene_layout_spec.lua`'s fixture work area; `conf/hosts/quantum-laptop.lua` states no literal resolution — see the note below) | `laptop-solo`: `gaps_out=8`                  | `1920 - 8*2 = 1904`     | 4         |

`conf/hosts/quantum-laptop.lua` never states a pixel size — geometry is
fingerprinted from live monitors (`hypr/lib/profile.lua`), never read off a
host file, which is the precedence rule in §2 working as intended. `1920×1200`
is the only concrete laptop number the repository states anywhere
(`tests/scene_layout_spec.lua:398`'s fixture work area); every other laptop
fixture (`tests/host_geometry_publish_spec.lua`,
`tests/host_roles_publish_spec.lua`, `tests/profile_spec.lua`) states only a
width (1920), so 1200 is inferred from the one place a height is pinned, not
invented fresh for this document.

The laptop's `secondary_monitor` (`HDMI-A-1`) is assumed disconnected below —
the ordinary "laptop alone" case. Every scene whose `workspace_specs` entry
names `monitor = "secondary"` (`obsidian-linear`, `media`, `logs`) then
resolves to the primary output by the existing fallback
(`hypr/hyprfocus/init.lua`'s `output_for`), so its resolver row below runs
against the laptop's `eDP-1` width like every other scene's.

Every scene below is `layout = "scene"` (none of the eight declares
`layout = "deck"` yet — `deck` has no wired scene, per deck.md). The
resolver's arithmetic is identical either way; only which windows a column
shows differs. `min_width` values below are this document's proposal, not
yet declared anywhere — they are the number the model asks a scene author to
add where `share` used to be, chosen here to match each block's existing
`share` weighting and to exercise the ladder somewhere real, per §9.

### `dofus` (roles: 1 Dofus group `min_width=1500`, 2 `zen-gaming-media` companion `min_width=480`, `solo_frame=false` — see §5)

| Profile | Resolved columns     | Folded                                                                             |
| ------- | -------------------- | ---------------------------------------------------------------------------------- |
| DP-1    | 1: 4468px · 2: 480px | none                                                                               |
| DP-2    | 1: 2046px · 2: 480px | none                                                                               |
| Laptop  | 1: 1904px            | 2 (companion) → 1 (group) — cost of two columns (1500+480+4=1984) exceeds W (1904) |

The laptop fold is worth reading twice: a fixed capture region (§5, §9)
folding its companion away on the one profile it was never designed for is
exactly the failure mode `solo_frame = false` exists to keep from also
distorting the group's own box — the companion disappears from view, not the
group's geometry.

### `pokemon` (roles: 1 emulator `min_width=700`, 2 chat slot `min_width=600`, 3 stream slot `min_width=600`)

| Profile | Resolved columns                | Folded                                                         |
| ------- | ------------------------------- | -------------------------------------------------------------- |
| DP-1    | 1: 3736px · 2: 600px · 3: 600px | none                                                           |
| DP-2    | 1: 1320px · 2: 600px · 3: 600px | none                                                           |
| Laptop  | 1: 1300px · 2: 600px            | 3 (stream) → 2 (chat) — three columns cost 1908 against W 1904 |

### `steam-games` (roles: 1 fullscreen `min_width=800`, `solo_frame` unset ⇒ `true`)

| Profile | Resolved columns                      | Folded                      |
| ------- | ------------------------------------- | --------------------------- |
| DP-1    | 1: 4600px (solo-framed: 4960 − 2×180) | n/a — one role, never folds |
| DP-2    | 1: 2172px (2532 − 360)                | n/a                         |
| Laptop  | 1: 1544px (1904 − 360)                | n/a                         |

A single-block fullscreen scene taking the default solo frame is almost
certainly wrong for a game meant to fill the panel — flagged in §9, not
silently fixed here.

### `media` (roles: 1 fullscreen `min_width=800`, `solo_frame` unset ⇒ `true`)

Same shape as `steam-games` — one always-solo column, same numbers, same
open question about whether a fullscreen block should default to framed.

### `code` (roles: 1 editor group `min_width=1200`, 2 browser `min_width=800`)

| Profile | Resolved columns     | Folded                                                          |
| ------- | -------------------- | --------------------------------------------------------------- |
| DP-1    | 1: 4148px · 2: 800px | none                                                            |
| DP-2    | 1: 1726px · 2: 800px | none                                                            |
| Laptop  | 1: 1904px            | 2 (browser) → 1 (editor) — two columns cost 2004 against W 1904 |

This is the model's own worked example (`editor ≥1200, browser ≥800`) run
against the real numbers instead of illustrative ones, and it reproduces the
stated outcome exactly: three tiers of nothing needed here (the real `code`
scene has two blocks, not the issue's illustrative three), ultrawide gives
the slack to the editor, and the laptop folds everything into one column.

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
`blocks` list today. All three profiles: one column, full `available_width`
(minus solo framing, since one column is one column regardless of how it got
there — `logs` declares no `solo_frame` override, so it frames like any
other lone column: 4600/2172/1544px, same arithmetic as `steam-games`
above). tmux owns the actual internal splits; the resolver's output here is
a box tmux draws inside, not a decision about what's inside it.

## 5. What the retired/kept fields become

| Field                                | Fate                                         | Why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `blocks[].share` / `columns[].share` | **Retired.**                                 | Replaced by `min_width` + the priority already carried by `order`. A percentage could not express "never below this" or "give slack to the most important thing first" without a second, redundant field; a minimum can, and is the only number `fractions`/the new resolver actually needs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `machines`                           | **Retired.**                                 | No scene in the live declaration (`assets/hyprfocus.default.json`) sets it today — grep confirms zero uses. Its entire purpose was a per-host escape hatch for a sizing rule that could not otherwise see the monitor; the resolver reads the monitor directly (§2), so the escape hatch has nothing left to hatch out of.                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `solo_frame`                         | **Kept, generalized.**                       | Same boolean, same default (`true`), same meaning ("do not let a lone column fill the panel") — except "lone column" now means whatever the resolver decided survives, not just a scene with one declared block. `deck` gains the field's effect for the first time, which is the whole "a lone window is framed identically on both layouts" done-when item.                                                                                                                                                                                                                                                                                                                                                                                                |
| `strays`                             | **Reconciled, mostly retired for `"slot"`.** | `"slot"` was already "an unmatched tiled window divides whatever the declared blocks leave" — that is now simply what happens to an untracked window: it joins the lowest-priority resolved column as an extra member, the same stacking `M.stack` already gives an ungrouped block's extra windows, no separate field needed to say so. `"float"` stays exactly as `hypr/scene/strays.lua` has it today — an open-time decision the resolver does not own or affect, unrelated to sizing. The field's remaining job is narrower: it only ever needs to say `"float"` now; `"slot"` becomes the assumed default with nothing left to configure, so a future schema could drop the field down to a single `float: boolean?` — not decided here, listed in §9. |

**Note on `dofus`'s `solo_frame`**: `conf/hosts/quantum-desktop.lua` and
`conf/hosts/quantum-laptop.lua` both carry a comment saying Dofus "must opt
out of solo framing itself" because its tile is a fixed capture region — but
the live declaration (`assets/hyprfocus.default.json`) does not actually set
`solo_frame: false` on the `dofus` scene today. This document assumes the
comment's stated intent (`solo_frame = false`) for the worked table above,
since that is what a fixed-region capture needs, but the drift between the
host comment and the live declaration is real and pre-dates this document —
flagged again in §9, not silently corrected here.

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
`columns[].share`) is replaced by `blocks[].min_width`; `order` keeps its
existing meaning and gains the second one (§1); `machines` is dropped from
the schema (§5 — nothing currently populates it, so dropping it changes no
live behaviour); `solo_frame` and `strays` keep their current shape.
Concretely, for every scene in the live declaration:

| Scene             | `share` fields removed | `min_width` fields added (this document's proposal, §4) |
| ----------------- | ---------------------- | ------------------------------------------------------- |
| `dofus`           | 2                      | 2 (1500, 480)                                           |
| `pokemon`         | 3                      | 3 (700, 600, 600)                                       |
| `steam-games`     | 1                      | 1 (800)                                                 |
| `media`           | 1                      | 1 (800)                                                 |
| `code`            | 2                      | 2 (1200, 800)                                           |
| `obsidian-linear` | 2                      | 2 (900, 700)                                            |
| `proton`          | 2                      | 2 (700, 420)                                            |
| `logs`            | 0                      | 0 (no blocks declared)                                  |

This chunk does **not** edit `assets/hyprfocus.default.json`, the store
schema, `hypr/scene/spec.lua`'s normalizer, or any Lua module — that is the
next chunk in the issue's own shape-of-work list ("the resolver as a pure
module with specs"), gated on this document being reviewed first.

## 9. Open questions

1. **Fixed-capture scenes vs. a reflowing resolver.** `dofus`'s tile is
   described (host-file comments, §5) as a fixed capture region for
   screen-recording — geometry that must not shift. A resolver that widens
   or narrows columns by live monitor width is in tension with "never
   shifts": does `dofus` need an explicit `min_width == max_width` concept
   (an exact width, not just a floor) that this document does not define,
   or is "it only ever runs on the desktop's primary, which never changes
   live" enough of a guarantee in practice?
2. **Does a single-block fullscreen scene want `solo_frame`?** `steam-games`
   and `media` both currently take the default (`true`) since neither
   declares an opt-out, which frames a fullscreen game or video with the
   same margin a lone code editor gets. That reads as an oversight rather
   than intent, but this document does not have standing to change a live
   scene's declaration — should `solo_frame = false` become the _default_
   for a scene with exactly one always-present role, rather than something
   every fullscreen scene has to opt into individually?
3. **The `dofus` `solo_frame` drift.** The host-file comments assert Dofus
   opts out of solo framing; the live declaration does not actually set the
   field. Which is the bug — the comment describing intent nothing
   implements, or the declaration missing a flag it was always supposed to
   carry?
4. **`min_width` values are this document's proposal, not the user's.**
   Every number in §4 and §8 was chosen here to roughly track each block's
   existing `share` weighting and to exercise the ladder somewhere real; none
   of them come from measuring an actual application's minimum usable width.
   Do these need a real pass (open each app narrow, note where it stops
   being usable) before the schema bump, or are approximate editor-judgment
   numbers acceptable to start from and refine later?
5. **What happens when even the sole surviving column is under its own
   minimum** (§3's degenerate case)? This document has the resolver hand it
   the full available width anyway rather than refuse or clip — is a
   visible warning (the bar, a notification) required at that point, or is
   "smaller than intended, but on screen and reachable" an acceptable silent
   floor?
6. **Does `strays` collapse to a single `float: boolean?`** now that
   `"slot"` has no configuration left to express (§5)? Not decided here;
   flagged as a natural follow-up to the schema bump, not a blocker to it.
7. **`fold_into` — worth declaring anywhere yet?** No real scene in §4 needs
   an explicit fold target; every fold in the worked tables lands on "the
   next one up" by default. Is the field worth adding to the schema now on
   spec, or only once a scene actually needs to name a non-adjacent fold
   target?
