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

## Scenarios

| Script                  | Checks                                                 | Eval |
| ----------------------- | ------------------------------------------------------ | ---- |
| `00_boot.sh`            | boots under the e2e host; no shell/uwsm launch         | no   |
| `10_group.sh`           | two group-block windows form one group                 | no   |
| `20_float_strays.sh`    | `strays = "float"` floats an unmatched window          | no   |
| `30_shelf_silent.sh`    | a shelf class routes to its special without showing it | no   |
| `40_mode_roundtrip.sh`  | gaming/neutral round trips keep every window reachable | yes  |
| `50_headless_output.sh` | a headless secondary output takes its scene; removal   | no   |

A scenario is a script that sources `lib.sh`, calls `e2e_start`, and exits
non-zero on failure (`e2e_fail`). Each gets its own nested compositor.
