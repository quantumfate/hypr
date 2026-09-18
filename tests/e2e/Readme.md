# End-to-end tests (nested Hyprland)

Stub specs (`tests/*_spec.lua`) cannot see compositor behaviour: rule timing,
groups, specials, monitors, mode switches. These scenarios boot this repo's
config in a Hyprland nested inside the running one and assert on
`hyprctl -j` output.

```sh
just e2e                                        # every scenario
just e2e tests/e2e/scenarios/10_group.sh        # one
E2E_KEEP=1 just e2e ...                         # keep the sandbox for logs
```

Needs a Wayland session (the nested compositor opens a window), `foot` and
`jq`. Not part of `just check`: it is not headless.

## Isolation

`lib.sh` `e2e_start`:

- makes one `mktemp` root holding `XDG_RUNTIME_DIR`, `XDG_STATE_HOME`,
  `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` (its `hypr` links to this repo) and
  `QF_STORE`, seeded from `fixtures/` (a test declaration and pointer);
- exports `QF_HOST=e2e` (selects `conf/hosts/e2e.lua` in `conf/host.lua`) and
  `QF_E2E=1` (`hypr/events/start.lua` skips the keymap, quickshell and the
  study project; only the mode watcher attaches);
- puts `stubs/stub` first on `PATH` as `qs`, `uwsm`, `notify-send`,
  `systemctl`, `setxkbmap` and `,hyprfocus`, logging calls to
  `$E2E_ROOT/stubs.log`, so nothing reaches the live session's shell or user
  units;
- waits for the nested `.socket.sock`, and refuses to continue if its
  signature equals the parent's.

`hc` is the only way to talk to the compositor: it always passes
`-i <nested signature>`. The EXIT trap kills the nested compositor and
removes the root.

## `hq`: a persistent instance for ad-hoc spikes

Scenarios are fixed assertions; `hq` is a live session an agent can drive
turn by turn, so a question ("does this window end up floated?") costs one
command instead of a whole scenario script. It shares `lib.sh`'s safety
contract (`hc` always `-i <nested sig>`, never the live session, never
`$QF_STORE`).

```sh
just e2e-up [--visible]      # boot once; later commands reuse it
tests/e2e/hq status
tests/e2e/hq state           # one line per monitor/workspace/window
tests/e2e/hq spawn e2e-probe loose
tests/e2e/hq mode gaming
tests/e2e/hq lua - <<'EOF'   # a Lua snippet, run in the nested instance
out({ mode = require('hypr.lib.store').define('focus'):get().mode })
EOF
tests/e2e/hq shot            # nested output only, downscaled PNG
just e2e-down
```

Token-saving guidance for agents:

- Prefer `hq state` over `hq lua -` with a raw `hyprctl -j` dump: it is
  already the compact summary you'd otherwise ask a snippet to produce.
- Prefer `hq lua` with `out(tbl)` over multiple round trips: one snippet can
  drive an action and read back the result in the same call.
- Only reach for `hq shot` when the question is genuinely visual (layout,
  rendering) — a screenshot costs far more tokens than `hq state`.
- `hq up` is idempotent: call it at the start of a task and leave it running
  across several `hq` calls rather than tearing down between them; `hq down`
  when done (or `just e2e-down`).
- `hq lua` never types the word the sandbox blocks — write the snippet to a
  file or heredoc and pass it, and `hq` does the `hyprctl eval` internally.
- `--visible` on `hq up` prints the live-session window class to float
  yourself (`hq` can't reach into the parent compositor to place it).

## Scenarios

| Script                       | Checks                                                                                                                      | Eval |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ---- |
| `00_boot.sh`                 | boots under the e2e host; no shell/uwsm launch                                                                              | no   |
| `10_group.sh`                | two group-block windows form one group                                                                                      | no   |
| `20_float_strays.sh`         | `strays = "float"` floats an unmatched window                                                                               | no   |
| `30_shelf_silent.sh`         | a shelf class routes to its special without showing it                                                                      | no   |
| `40_mode_roundtrip.sh`       | work/gaming (+ neutral hop) round trips keep every window reachable                                                         | yes  |
| `50_headless_output.sh`      | a headless secondary output takes its scene; removal                                                                        | no   |
| `60_navigation.sh`           | mod+h/l/j/k across tiles, into/out of a group, onto an empty monitor                                                        | yes  |
| `65_focus_transitions.sh`    | work→study→gaming→work, timed expiry falls back to `previous`, neutral recovery — held sets and pointer fields at each step | yes  |
| `70_boot_pointer.sh`         | boot: a stale pointer lands on `work`; an unexpired timed mode survives a restart                                           | no   |
| `75_undeclared_workspace.sh` | a window on a workspace the host never declared moves to its monitor's own                                                  | no   |
| `80_collect_home.sh`         | a claimed window standing elsewhere is re-homed to its scene, focus unmoved                                                 | no   |
| `90_live_gaps.sh`            | editing `conf/base.lua` gap numbers + reload applies them live (general + scene rule gaps)                                            | no   |

A scenario is a script that sources `lib.sh`, calls `e2e_start`, and exits
non-zero on failure (`e2e_fail`). Each gets its own nested compositor.
