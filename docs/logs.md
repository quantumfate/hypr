# Log groups

**Status: stage 1 wired; stages 2-5 are design.** The scene works and
`bin/,logs.sh` instantiates a declared group on it
(`tests/e2e/scenarios/99_log_group.sh`). What is NOT wired: nothing reads a
group's `logs.toml` except `add`, there is no `sync`, the bar cards do not
exist, and `logview`'s tmux server is untouched.
Neighbours: [scenes.md](scenes.md) (the scene contract), [deck.md](deck.md)
(the column strip this borrows), [project-groups.md](project-groups.md) (the
engine this mirrors), [bin/Readme.md](../bin/Readme.md) (the helpers).

A **log group** is a **declared group**
([declared-groups.md](declared-groups.md) is the contract both front-ends
share; read it first). It is one Hyprland group of terminal windows on the
`logs` scene, one window per log source, declared by a document. It is the
same shape a project group has — and deliberately so: the desk already knows how
to fold a class into a group, strip it across a deck column, and bind its
tabs, so this is wiring rather than new machinery.

A log group stands alone. It is **not** linked to a project: an earlier
revision paired them by name (`Log-hypr` with `Proj-hypr`) and had the `code`
deck push its log group forward on a scroll. That link is retired (user
decision, 2026-09-24) — it bought an ordering nicety and cost a standing
maintenance burden in both decks, two documents and every scenario that
touches either. A log group watches what it watches; a project is opened
because you asked for it.

## What exists today

- The `logs` scene declares a `Log-[A-Za-z0-9_-]+` group block, a `logviewer`
  block and a deck layout: a column of log groups beside a `Kitty-logs`
  terminal. It used to declare `blocks: []`, so every window landing there
  matched nothing and the stray rule floated it — including the viewer, whose
  own rule asks for `float = false` and lost. That was why the logs workspace
  did not work.
- `bin/,logs.sh` — `list/add/drop/open/pick/kill`. One kitty per declared
  source, classed `Log-<name>`, tagged `slot:<source>`, folded into one group
  by the scene's block; `open` ends with one act that shows the group and
  focuses it, and the spawn is detached so it outlives the picker window that
  asked for it (docs/declared-groups.md rule 4).
- The catalogue (`$QF_STORE/logs.json`): `name -> { path, sources{} }`,
  folded from a repo's own `logs.toml` by `add`. Nothing scans.
- `SUPER+e o` opens the picker, `SUPER+e SHIFT+d` closes the focused group.
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
# logs.toml -- in a repo, or in the log catalogue
[sources]
build = "just check"
unit  = "journalctl --user -u hyprfocus -f"
trace = ",hyprfocus log --follow"
```

Groups need a home for their documents, since they have no repo:
a **log catalogue** store document of their own, populated by an explicit
`add`, the same deliberate gesture `,proj.sh add` is — nothing scans. Its own
document, not a `kind` inside the projects store: the two carry different
schemas once they are described in CUE, and a log group need not have a
project to live in — the repo's rule is one document per concern.

## Window rules

Routing has to be by class, decided per scene:

- `Log-*` -> `name:logs`, tiled, admitted to the logs block.
- `Proj-*` -> `name:code`, unchanged.
- A log window must not join a project's group, and a project window must not
  join a log's. They already cannot: `grouping.lua` folds only one block's
  classes per group, and the two classes live in different blocks on
  different scenes.
- A `Log-<name>` and a `Proj-<name>` sharing a suffix mean nothing to each
  other. The names may match because the subject matches; no code reads one
  from the other.

## Cards

The bar side mirrors `OpenProjects`: a live view of which log groups are
open and which is focused, read from the compositor rather than a state file.
Clicking one focuses that group, and moves nothing else.

## Staging

1. ~~**The scene works.**~~ Done: the block, the deck layout and `,logs.sh`
   with `list/add/drop/open/pick/kill`, pinned by
   `tests/e2e/scenarios/99_log_group.sh`.
2. **The document.** `sync` (refresh every catalogued group from its own
   `logs.toml`, the way `,proj.sh sync` does), and a group's sources editable
   without a repo.
3. **The cards.** The bar view.
4. **Retire tmux.** Remove `logview`'s tmux server, `tmux_logs.conf.j2` and
   the socket, once the group engine covers what they did. Not before: the
   viewer is the working implementation until the replacement is.

## Decisions (user, 2026-09-24)

- **Catalogue** — standalone log groups live in the store's **own log
  catalogue document**, not a `kind` inside the projects store: the two carry
  different schemas, and the repo keeps one document per concern.
- **Lifecycle** — a log group **ends with its last window**, like a project
  group. The declaration survives; the runtime group does not. Reopening a
  source is a deliberate gesture.
- **No project link** (2026-09-24) — log groups and project groups are
  independent. The pairing, and the `code`-deck bring-forward it enabled, are
  retired unbuilt: the ordering nicety did not pay for the maintenance it put
  on two decks and two documents.
