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

- `bin/,proj.sh` — the project manager (tmux is gone from
  here). A project is a set of kitty windows in one Hyprland group on the
  `code` scene — no sessions, no sockets; the project ends when its last
  window closes and nothing is remembered. `$QF_STORE/projects.json` is the
  source of truth for which projects exist and their window template
  (`,proj.sh sync` populates it from a filesystem scan; nothing else scans).
  `pick` chooses a project with fzf, never in a separate window — from a
  Hyprland bind (no terminal at all) it opens one project-classed kitty
  window whose first screen IS fzf, and that window's `open` call brings up
  the rest of the project's windows (`pick --inline`, used internally for
  that re-exec). Full reference, including how an nvim window is asked to
  quit rather than force-closed, in the script's own header comment.

- `bin/,job.sh` — starts a long-running job (dev server, build, watcher) as a
  transient `systemd --user` service instead of a plain background process, so
  it survives a compositor restart. `systemd-run --user`, not
  `--scope` and not `uwsm app --`: a scope inherits the caller's own stdio
  rather than the journal, and `uwsm app --` parents the command to the
  graphical session (`wayland-session@hyprland.desktop.target`), the exact
  thing a compositor restart tears down — the one case this exists to survive.
  A dev server draws nothing, so it has no business in the graphical session
  at all. The unit is named `proj-job-<project>-<name>`, so `,proj.sh` can
  later enumerate the jobs a project owns; `logview unit:<name>` (below)
  already knows how to tail it, since it is an ordinary systemd unit.

  **What belongs in a unit vs. a terminal window:** a window is for something
  a person is looking at or typing into — an editor, a shell, an interactive
  REPL. A unit is for something that just needs to keep running and only
  incidentally produces output — a dev server, a long build, a file watcher.
  The test is "would losing this be a regression if the compositor restarted
  right now": if yes, it is a unit; if the window closing was always going to
  end it anyway, a window is fine.

  ```
  ,job.sh start myproj dev -- npm run dev   # transient unit proj-job-myproj-dev
  ,job.sh logs myproj dev                   # journalctl --user -u ..., -f
  ,job.sh restart myproj dev -- npm run dev
  ,job.sh stop myproj dev
  ,job.sh list myproj                       # every job unit for one project
  ```

  No real service is converted to this mechanism yet — this ships the
  mechanism and the one worked example above.

- `bin/,theme.sh` — the palette/wallpaper fan-out (full verb list in the
  script's own header). Wallpapers live per palette (`wallpapers/<palette>/*`
  at the repo root, which is `$CONFIG/hypr/wallpapers/<palette>` once
  `ansible/roles/hypr` symlinks this whole repo in as `~/.config/hypr`); an
  image may join more than one palette via a symlink into a second palette's
  folder rather than a copy or a shared/ bucket — so listing one palette's
  folder is always its whole set. `wallpaper list|next|prev|random` are
  per-monitor (`theme.json`'s `wallpapers[palette][output]`, `"*"` meaning
  every monitor); cycling is a shuffled, deterministic-per-session order
  (`wallpaper_shuffle[palette].orders[output]`) that never repeats until that
  output's fitting subset is exhausted. `wallpaper F [P]` still binds a file
  directly, refusing one outside `P`'s set once that palette has a set folder,
  and now also refusing one that does not fit an already-known output; a bare
  legacy name or a flat (pre-palette-folders) binding still resolves — the
  Quickshell store's older writes are not stranded. `bin/,wallpaper.sh` is now
  a thin wrapper over `,theme.sh wallpaper` for keybinds.

  Cycling a wallpaper (`wallpaper next|prev|random`, and `,wallpaper.sh`)
  calls `apply_wallpaper` directly and never touches `apply_hyprland` — it
  pokes `awww` and writes only `theme.json` (never `require()`'d by
  `hyprland.lua`, so the compositor's inotify watcher never sees it, per
  `docs/live-config.md` §1). A wallpaper rotation therefore reloads nothing
  and re-lays-out nothing on its own. `apply_hyprland` itself also no longer
  reloads on every `apply`: it stamps the palette it last reloaded for
  (`$XDG_CACHE_HOME/quantumfate/hyprland.applied`, the same pattern
  `apply_transparency` already used for its own dial) and skips `hyprctl
  reload` when the resolved palette hasn't moved — closing the one way a
  same-palette `apply` (chiefly `theme-auto.timer`'s hourly tick, which calls
  `apply` — and therefore `apply_wallpaper` — unconditionally) could still
  reload purely because it ran, with no colour change to show for it. A real
  palette switch still reloads, since Hyprland's own colours only come from
  re-running its Lua config (see `apply_hyprland`'s own comment).

  Every apply also writes `$XDG_CONFIG_HOME/zsh/theme.zsh` — `BAT_THEME` and
  `FZF_DEFAULT_OPTS` for the resolved palette, since zsh/fzf read no store and
  get no live D-Bus poke of their own. The zsh role's rc file must `source
~/.config/zsh/theme.zsh` (after this file exists) for a shell to pick up
  the palette it was started under; a shell already running picks it up the
  next time something re-sources rc (a new prompt does not re-source on its
  own — same "next launch" tier as Zen/Obsidian below).

  nvim needs no restart at all: `apply_nvim` pokes every running editor's
  control socket, and every editor also watches the store itself, so a flip
  lands immediately on socketed and socketless instances alike. The poke is
  reported honestly — `immediate` only when a socket actually swapped the
  scheme (a lazy catppuccin that answers `E185` counts as pending, not
  applied), and a socketless desk is pending with a reason, since the editor
  still converges through its own watcher. Editors follow the store's
  `resolved` palette — the lease-aware value `apply` writes beside the
  baseline `palette` — so the poke and the watcher always agree on one
  palette, and a mode's lease reaches nvim through both paths.

  A palette's folder is one pool; each monitor draws from it at random, but
  only from the images that actually fit that monitor's live pixel size read
  from `hyprctl monitors -j` (aspect and scale, never a hardcoded output
  list). `fits_output()` in `,theme.sh` applies two documented numbers:
  `FIT_ASPECT_TOLERANCE` (0.20 — the image's aspect ratio may differ from the
  output's by at most 20% relative) and `FIT_MIN_SCALE` (0.5 — the image must
  supply at least half the output's width and height after aspect-matched
  scaling, so it is never upscaled more than 2x). An ultrawide image and a
  16:9/16:10 output differ by well over 20%, so they never cross. If nothing
  in a palette's pool fits an output, that output's binding is left alone and
  the honest gap is recorded in `theme.result.json`'s `failed` list (surface
  `wallpaper:<output>`) rather than stretching or cropping something that
  does not belong there. `wallpaper list` reports, per monitor, which of the
  pool's images fit (`monitors[output].fits`) and which one is current.
  Image and output sizes are cached (`image_size()`/`output_size()`, keyed by
  mtime) so listing a large pool stays fast; tests inject fixed sizes via
  `THEME_IMAGE_SIZES`/`THEME_OUTPUT_SIZES` rather than probing real images or
  the live session.

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
  never a file), keyed by `TRACE` (the window address). `,hyprfocus apply
<mode>` re-runs `,theme.sh apply` after its own unit bookkeeping
  (`reapply_theme`), since a mode's accent role can change even when the
  palette does not; best-effort and silent, skipped under `HYPRFOCUS_NO_THEME`
  (the tests' escape hatch).

  ```
  ,hyprfocus log                       # recent scene-policy rows (background work)
  ,hyprfocus log --trace 0x55f3...     # one window's whole lifecycle
  ,hyprfocus log --follow              # live lifecycle journal
  ```

  The `logs` workspace's `h` entry (`hypr/services/logging/init.lua`) opens
  `,hyprfocus log --follow` in a kitty window, since `logview`'s spec
  vocabulary has no generic "journal filtered by `SYSLOG_IDENTIFIER`" source.

- `bin/,profile-force` — forces `hypr/lib/profile.lua`'s geometry profile
  (`desk-dual`/`laptop-solo`) to test one machine's layout from the other. A
  typed command on purpose, never a keybind: the override outranks the live
  monitor fingerprint on every config load, so a single mis-tapped key once
  cost two weeks of invisible bad geometry. Every force carries an expiry
  (default 120 minutes, `,profile-force <name> [minutes]`) and announces
  itself loudly — a notification plus a `stage=profile` trace record — on
  every load while it stands (`hypr/lib/profile.lua`'s `M.announce`, called
  from `conf/host.lua`). `,profile-force clear` drops it early; `,profile-force
status` reads the store directly for what is standing and until when.

How the shared state + IPC bridges work:
[quickshell/ARCHITECTURE.md](https://github.com/quantumfate/quickshell/blob/main/ARCHITECTURE.md).

The desk's shared state lives in one store directory: `$QF_STORE` (default
`$XDG_STATE_HOME/quantum-store`, exported by `env-hyprland`). Every runtime
reads backward one step to the location before it existed, so a store not yet
moved still answers and migrates on the next write — except `hyprfocus.json`
(the scene declaration), which opts out on both sides (`hypr/lib/store.lua`'s
`NO_LEGACY`, quickshell's `Store { legacyMigration: false }` in
`Hyprfocus.qml`): a missing declaration must leave the engine inert and say
so, never resurrect an old one. Seeding and reseeding now run themselves at
session start (`hypr/lib/maintenance.lua`, called from `hypr/events/start.lua`)
and log every action with `stage=maintenance` — `,hyprfocus seed` and
`,proj.sh sync` are no longer something to remember to run by hand.
