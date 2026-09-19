# Project groups

**Status: design, not yet implemented.** This is the flow the `code` scene is
meant to have. It supersedes the ad-hoc half of `bin/,proj.sh`'s current
`pick`/`open` behaviour; everything in "What already exists" below stays.

A project group is one Hyprland group of kitty windows that a project
declares: its directory, an ordered set of windows, and the command each one
runs. Opening a project means instantiating that declaration. The desk already
does the hard parts — grouping by block, the deck's column strip, class-context
binds — so most of this is wiring, not new machinery.

## What already exists

- `bin/,proj.sh` — `list/sync/drop/pick/open/kill/focus/scope/pick-scope`.
  Projects come from `sync`, which folds each repo's `.proj.toml` into the
  store. There is no `create`: a project exists because a `.proj.toml` does.
- The store (`$QF_STORE/projects.json`): `name -> { kind, study, priority,
  path, windows[], workspace, scopes{} }`. `windows` is an ordered list of
  role NAMES only.
- `window_command()` in `,proj.sh` hardcodes the mapping: `nvim` gets
  `nvim --listen <sock> .`, every other role gets a bare shell. A project
  cannot say what its windows run.
- `scopes` — `name -> command`, spawned on demand, tagged `slot:<name>`.
  This is already "a declared window with a command", just not part of the
  template.
- Each spawned window is tagged `slot:<role>`, and the group's class is
  `Proj-<name>`. An ad-hoc `mod+return` terminal is class `Kitty-Main`.
  **Declared and ad-hoc windows are therefore already distinguishable, by
  class and by tag, with no new state.**
- `hypr/scene/grouping.lua` folds a new `Proj-*`/`Kitty-Main` window into
  whichever group already holds most of that block's peers, so a project's
  windows group themselves.
- `hypr/lib/bind.lua`'s submap tree supports class-context binds, which is the
  mechanism the per-project binds below need.

## The gaps

1. **Windows carry no commands.** `windows: ["nvim","zsh","run"]` cannot say
   that `run` is `npm run dev`. Only `scopes` can, and those are on-demand.
2. **The picker is not a picker.** `mod+space p p` runs `,proj.sh pick`, which
   spawns a `Proj-picker` kitty that tiles into the deck — it takes a column
   and is half off-screen. It should be a small floating window.
3. **No per-project binds.** `p n` / `p r` are hardcoded to the roles `nvim`
   and `run`. A project declaring `db` or `logs` has no key.
4. **`mod+j/k` walks everything.** It should walk only the ad-hoc terminals.

## Design

### 1. The declaration

`.proj.toml` gains an ordered `[[windows]]` array. The bare-string form stays
valid and means "a plain shell", so nothing already declared has to change.

```toml
directory = "."                      # optional; defaults to the repo root

[[windows]]
name = "nvim"                        # role; becomes the `slot:nvim` tag
command = "nvim ."                   # optional; omitted = plain zsh
key = "n"                            # optional; its contextual bind

[[windows]]
name = "run"
command = "npm run dev"
key = "r"

[[windows]]
name = "zsh"                         # no command, no key: just a shell
```

`sync` folds this into the store as `windows: [{ name, command?, key? }]`.
The store schema change is additive; `,proj.sh` reads the old string form as
`{ name = <string> }`.

**Why in the repo, not the store:** a project's window set is a property of the
project, versioned with it, the same argument `.proj.toml` already makes. The
store stays a cache that `sync` rebuilds.

### 2. `window_command` becomes a lookup

`window_command()` stops hardcoding roles and reads the declaration: a window
with a `command` runs it, one without opens a shell. `nvim`'s control socket
stops being a special case and becomes the general rule below.

### 3. Kitty remote control — yes, but only for identity

Give every project window `--listen-on unix:$XDG_RUNTIME_DIR/kitty/<class>-<role>.sock`
and `allow_remote_control=socket-only`. That buys:

- **A stable handle per window**, independent of Hyprland addresses, which
  survive nothing. `kitty @ --to <sock> ls` answers "what is actually running
  in here, and in what directory".
- **Clean teardown** — `kitty @ close-window` instead of killing a process.
- **Re-use** — `,proj.sh` can send a command to an existing window rather than
  spawning a second one.
- It generalises the nvim socket that already exists for exactly this reason.

**What it must NOT do: layout.** One kitty instance with internal splits would
take window management away from Hyprland, and the group, the deck strip and
every scene rule would stop applying. One kitty process per window stays the
rule; the socket is for identity and control only.

### 4. The picker floats

`pick` spawns its kitty with class `Proj-picker` as now, but the scene gains a
float rule for that class (`strays` already floats undeclared classes on
`code`; the picker needs an explicit rule since it matches `Proj-*`). Sized
small and centred. Choosing instantiates the group; the picker closes itself.
The existing `reassert_focus_after_picker_closes` already handles focus after
that close.

A second entry — `pick --window` — lists the *open* windows of the focused
project and jumps to one. This is the "temporarily pin and jump" idea: it is a
floating fzf over `kitty @ ls` output across the group's sockets, and jumping
is a plain focus dispatch. Nothing needs pinning in the compositor.

### 5. Contextual binds

The project submap (`mod+space p`) keeps `p` (pick a project) and gains
nothing else hardcoded. Instead, when a `Proj-<name>` window is focused, the
submap is extended from that project's declaration: each window with a `key`
becomes an entry that focuses its `slot:<name>` window.

`p n` and `p r` therefore keep working for any project that declares
`key = "n"` on nvim and `key = "r"` on run — the current behaviour becomes the
default declaration rather than a hardcoded rule.

### 6. `mod+j/k` walks ad-hoc terminals only

On a deck column, `mod+j/k` filters to windows with **no `slot:` tag** —
i.e. `mod+return` terminals. Declared windows are reached by their contextual
bind, never by stepping. `mod+ctrl+j/k` keeps scrolling the column strip and is
unaffected.

## Open questions

1. **Does `key` collide?** A project declaring `key = "p"` would shadow the
   picker. Proposal: reserved keys (`p`, `o`, `k`) are refused by `sync` with a
   warning, rather than silently dropped.
2. **Group ordering.** The declaration is ordered; Hyprland group order is
   arrival order. Spawning strictly in sequence (as `spawn_missing` already
   does, one at a time) preserves it — worth an e2e assertion.
3. **`create`.** Still nothing writes a `.proj.toml`. A `,proj.sh create`
   scaffolding one from a template would close the loop, but it is separable
   from everything above.

## Verification

Live, on the real desk — the harness cannot see focus theft or float geometry:

1. `mod+space p p` shows a small floating picker, not a tiled column.
2. Choosing a project spawns its declared windows in declared order, grouped,
   and focus lands on the first.
3. A project-declared `key` focuses that window while the project is focused,
   and does nothing while it is not.
4. `mod+return` twice, then `mod+j/k` — steps between exactly those two
   terminals, never into the project's declared windows.
5. `mod+ctrl+j/k` still scrolls the column strip.
