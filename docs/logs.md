# Log groups

**Status: design, not yet implemented.** Nothing below is wired. It describes
what the `logs` scene is meant to become and what has to move to get there.
Neighbours: [scenes.md](scenes.md) (the scene contract), [deck.md](deck.md)
(the column strip this borrows), [project-groups.md](project-groups.md) (the
engine this mirrors), [bin/Readme.md](../bin/Readme.md) (the helpers).

A **log group** is one Hyprland group of terminal windows on the `logs`
scene, one window per log source, declared by a document. It is the same
shape a project group has — and deliberately so: the desk already knows how
to fold a class into a group, strip it across a deck column, and bind its
tabs, so this is wiring rather than new machinery.

A log group **may** name a project. That link is an optional contract, not a
property of either side: a log group that watches a unit, a device or a
machine belongs to nobody, and a project with nothing worth tailing declares
no logs at all.

## What exists today

- The `logs` scene declares `blocks: []` and `strays: "float"`. Every window
  that lands there matches no block, so the runtime stray decision floats it
  — including the log viewer, whose own window rule asks for `float = false`
  and loses. **This is why the logs workspace does not work.** A scene with
  no blocks has no layout to put anything in.
- `hypr/services/logging/init.lua` — the `logs` submap (11 keys) and the
  window rule that tags class `logviewer` `+logs` and routes it to
  `name:logs`.
- `logview` / `logstream` / `logpick` (system-config's `zsh` role) open a log
  source in **one** kitty window classed `logviewer`, holding a **tmux**
  session with one tmux window per source, on its own socket and its own CWD.
- `$QF_STORE/projects.json` and `.proj.toml`'s `[scopes]` — the existing
  "declared window with a command" precedent this borrows.

The tmux half is the part that goes. It predates the group engine and solves,
inside one window, exactly what Hyprland groups solve between windows — the
same move `,proj.sh` already made when it stopped being tmux-shaped.

## The model

One kitty per source, classed `Log-<name>`, tagged `slot:<source>` at launch,
folded into one group by `hypr/scene/grouping.lua` because they share a class.
The `logs` scene gains a block that names them and a `deck` layout, so several
log groups live on one workspace as a strip, one shown at a time.

```
Log-hypr      slot:build   slot:unit    slot:trace
Log-system    slot:errors  slot:kernel  slot:follow
  -> two groups, two things on the logs deck's column
```

Nothing here is new engine work: `Log-[A-Za-z0-9_-]+` is a block like
`Proj-[A-Za-z0-9_-]+`, and the deck already strips a column of groups.

A log group **ends when its last window closes**, exactly like a project
group: the group is the instantiation of its declaration, derived from the
windows it holds, never a remembered membership set. Reopening a source is a
deliberate gesture — a declared key, or the picker. The long-running tail is
served by keeping the source declared, not by keeping the group alive empty.

## The document

A log group is declared in its **own** file, not in `.proj.toml`. Two reasons:
a log group need not have a project to live in, and the two documents are
going to carry different schemas once they are described in CUE.

```toml
# logs.toml -- in a repo, or in the log catalogue for a group with no project
project = "hypr"        # OPTIONAL. The link. Absent = a standalone group.

[sources]
build = "just check"
unit  = "journalctl --user -u hyprfocus -f"
trace = ",hyprfocus log --follow"
```

`project` is the whole of the contract. When present it names a project by
the same name its class already carries, so `Log-hypr` pairs with `Proj-hypr`
and there is no second mapping to drift. When absent the group stands alone
and every rule below that mentions a project simply does not apply to it.

Standalone groups need a home for their documents, since they have no repo:
a **log catalogue** store document of their own, populated by an explicit
`add`, the same deliberate gesture `,proj.sh add` is — nothing scans. Its own
document, not a `kind` inside the projects store: the two carry different
schemas once they are described in CUE, and a log group need not have a
project to live in — the repo's rule is one document per concern.

## Direction: the code scene drives

A project and its log group are paired, but the pairing is **one-way** for
ordering.

- Scrolling the `code` deck to a project brings its linked log group forward
  on the `logs` scene.
- Scrolling the `logs` deck does **not** reorder or scroll the `code` deck.

That asymmetry is the point. Browsing logs is a read: stepping through the
log strip looking for something must not rearrange the work behind it, and a
strip that reorders under you because you looked at a neighbour is worse than
no linking at all. The code scene is where the intent lives, so it is the only
side that pushes.

Opening a project **never spawns** its log group: the bring-forward is an
ordering act over a group that already exists. Spawning windows nobody asked
for is a launch, and the desk otherwise avoids it.

An unlinked log group is simply never brought forward by a project swap, and
scrolling past it changes nothing on `code` either.

## Window rules

Routing has to be by class, decided per scene:

- `Log-*` -> `name:logs`, tiled, admitted to the logs block.
- `Proj-*` -> `name:code`, unchanged.
- A log window must not join a project's group, and a project window must not
  join a log's. They already cannot: `grouping.lua` folds only one block's
  classes per group, and the two classes live in different blocks on
  different scenes.
- The class prefixes must not collide with a project named `hypr` producing
  `Log-hypr` and `Proj-hypr` — they do not, and that shared suffix IS the
  link.

## Cards

The bar side mirrors `OpenProjects`: a live view of which log groups are
open and which is focused, read from the compositor rather than a state file.
A card for a linked group shows the pairing, so the relationship is visible
rather than implied. Clicking one focuses that group; it does not move the
`code` scene, for the same reason scrolling the log deck does not.

## Staging

1. **The scene works.** Give `logs` a block for `Log-*` and a deck layout, so
   a log window tiles and groups instead of floating. `,logs.sh` with
   `open`/`pick`/`kill`, mirroring `,proj.sh`. The default picker stays —
   discovering a source by fzf is how this is used when nothing is declared.
2. **The document.** `logs.toml`, the catalogue for standalone groups, and
   `sync`.
3. **The link.** `project = "..."`, and the one-way bring-forward from a
   `code` deck swap.
4. **The cards.** The bar view and its pairing indicator.
5. **Retire tmux.** Remove `logview`'s tmux server, `tmux_logs.conf.j2` and
   the socket, once the group engine covers what they did. Not before: the
   viewer is the working implementation until the replacement is.

## Decisions (user, 2026-09-24)

- **Catalogue** — standalone log groups live in the store's **own log
  catalogue document**, not a `kind` inside the projects store: the two carry
  different schemas, and the repo keeps one document per concern.
- **Lifecycle** — a log group **ends with its last window**, like a project
  group. The declaration survives; the runtime group does not. Reopening a
  source is a deliberate gesture.
- **Project open** — opening a project **never spawns** its log group; a
  project swap only brings an existing group forward. The pairing is an
  ordering act, not a launch.
