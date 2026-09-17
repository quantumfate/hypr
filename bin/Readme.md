# bin/ — the helpers the desktop spawns

The `,name.sh` helpers Hyprland's binds and Quickshell call. They used to live
in a standalone [scripts](https://github.com/quantumfate/scripts) repo, now
retired into this one — the delivery rule is that the config ships beside the
code it invokes, and `bin/` is the PATH entry system-config puts on every
session.

Most are small `,name.sh` wrappers invoked from Hyprland keybinds. A few
integrate with the shared state / UI:

- `bin/qfs` — "quantumfate shell": wraps the Quickshell IPC surface
  (`qfs theme cycle`, `qfs window rename "..."`, `qfs show`, …). Zsh completion
  `_qfs` lives in the quickshell repo's `completions/`.

- `bin/,proj.sh` — the tmux project manager: one entry point for "put me in
  project X". `pick` chooses a project with fzf, never in a separate window —
  inside tmux it's a `tmux display-popup`; from a Hyprland bind (no terminal at
  all) it opens one project-classed kitty window whose first screen IS fzf,
  and the same window becomes the project session once you choose
  (`pick --inline`, used internally for that re-exec). Full reference in the
  script's own header comment.

- `bin/dofus_swap.py` — Dofus auto turn-swap detector. Reads its roster from the
  shared team source of truth (`$QF_STORE/dofus/team.json`), the same file
  the Quickshell UI edits, so team changes take effect live.
  (Querying that team store from the shell is done with `dofus-team`, which lives
  in the quickshell repo's `scripts/`.)

- `bin/copy_settings.sh` + `bin/wrap_action.sh` — the leftover, hand-invoked
  Dofus helpers (ex-[dofus-scripts](https://github.com/quantumfate/dofus-scripts),
  retired here): settings replication across accounts/characters, and the
  keybind wrapper that lets a global chord fall through to the game window.

- `bin/obsidian_vault.py` + `bin/,obsidian-cli-wrapper.sh` — Obsidian Zettelkasten
  bootstrap: scans `~/Documents/Obsidian/Main`, infers the missing
  `idx`/`meta_idx` index-note chain for a topic, creates notes via Templater, and
  keeps a tag-structure store (`$QF_STORE/obsidian/tags.json`, plus a
  GPG-encrypted `.gpg` copy). The vault is the source of truth; the store is a
  projection. Full reference: quickshell
  `docs/obsidian-vault-manifest.md`.

  ```
  ,obsidian-cli-wrapper.sh status                                  # vault/store state
  ,obsidian-cli-wrapper.sh create atomic "Some Title" --tag Topic/Sub
  ,obsidian-cli-wrapper.sh ensure-topic Topic/Sub --dry-run        # plan index notes
  ```

- `bin/obsidian_linear_sync.py` + `bin/obsidian-linear-sync` — one-way mirror of
  Linear into the same vault. Projects, milestones and issues become index notes
  under `Projects/`, so the index-notes plugin renders the hierarchy; sub-issues
  are filed under their parent. Linear is the source of truth and nothing is ever
  deleted. The API key is read from Proton Pass at runtime (`Productivity` /
  `linear.app` / `api_key`); a locked vault notifies and exits. Runs every five
  minutes from `obsidian-linear-sync.timer`, deployed by the `obsidian_linear`
  role in **system-config**.

  Because tags are derived from Linear's naming, a rename moves a whole subtree.
  The previous hierarchy is kept in `$QF_STORE/obsidian/linear.json` so the
  next run can diff it and rename the old tag prefix wherever it appears —
  including on notes the sync never created.

  ```
  obsidian-linear-sync                       # dry run
  obsidian-linear-sync --apply               # sync now
  obsidian-linear-sync --project lance.nvim --apply
  obsidian-linear-sync --apply --force       # rewrite managed blocks regardless
  ```

- `bin/,scene-apply.sh` + `bin/,mood-bg.sh` — the mood-mode enforcement seam
  (LEO-238). `,scene-apply.sh [mode]` is spawned detached by the shell whenever
  the active focus mood changes and brings user-unit background work in line
  with it: it stops the units the contract (`etc/scene-managed.json`) maps to
  the mood's reachable scenes and deferred/prevented background tasks, and
  hands back whatever the previous mood stopped. Units on the contract's
  `protected` list are never touched; stops go through systemd (SIGTERM + the
  unit's `TimeoutStopSec`, never SIGKILL); `graceful` entries are only
  requested and logged. Every decision lands in
  `$QF_STORE/scene-policy/log.jsonl`, the feed for the scene-policy
  logging workspace (LEO-241). `--dry-run` prints the plan without touching
  systemd. `,mood-bg.sh <task>` is the dispatch-time gate for a task's timer:
  it asks the shell (`focus bg <task>`) and exits 0 to run, 2 to defer, 3 to
  prevent — the same verdict the mood panel shows.

  ```
  ,scene-apply.sh game        # gated manual run (the shell triggers this anyway)
  ,scene-apply.sh --dry-run   # show the plan, touch nothing
  ,mood-bg.sh obsidian        # timer gate → 0 | 2 | 3
  ```

  The contract ships from this repo because the actor ships here (the desktop's
  delivery rule: each repo delivers its own role/data; quickshell never reads
  `etc/scene-managed.json` — it asks the same policy Focus reads).

- `bin/,hyprfocus` — reads and applies the hyprfocus declaration (see
  `hypr/hyprfocus/`); `log` also queries the window lifecycle journal
  (LEO-352, [docs/lifecycle.md](../docs/lifecycle.md) Part B). Every
  identify/leave/admit/interact decision the compositor makes is written by
  `hypr/lib/trace.lua` to the systemd journal (`SYSLOG_IDENTIFIER=hyprfocus`,
  never a file), keyed by `TRACE` (the window address).

  ```
  ,hyprfocus log                       # recent scene-policy rows (background work)
  ,hyprfocus log --trace 0x55f3...     # one window's whole lifecycle
  ,hyprfocus log --follow              # live lifecycle journal
  ```

  The `logs` workspace's `h` entry (`hypr/services/logging/init.lua`) opens
  `,hyprfocus log --follow` in a kitty window, since `logview`'s spec
  vocabulary has no generic "journal filtered by `SYSLOG_IDENTIFIER`" source.

How the shared state + IPC bridges work:
[quickshell/ARCHITECTURE.md](https://github.com/quantumfate/quickshell/blob/main/ARCHITECTURE.md).

The desk's shared state lives in one store directory: `$QF_STORE` (default
`$XDG_STATE_HOME/quantum-store`, exported by `env-hyprland`). Every runtime
reads backward one step to the location before it existed, so a store not yet
moved still answers and migrates on the next write.
