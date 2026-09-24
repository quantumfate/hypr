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
`jq`; `95_project_group.sh` additionally needs `kitty` (`,proj.sh`'s own
terminal) and skips itself when it is missing. Not part of `just check`: it
is not headless.

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
  units — except `uwsm app -- CMD`, which the stub still logs but then runs
  CMD for real: uwsm itself is only a scoping wrapper with no login manager
  to scope into here, and a scenario waiting on the window CMD opens (e.g.
  `,proj.sh`'s own launches) needs it to actually run;
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

| Script                         | Checks                                                                                                                                                                              | Eval |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| `00_boot.sh`                   | boots under the e2e host; no shell/uwsm launch                                                                                                                                      | no   |
| `10_group.sh`                  | two group-block windows form one group                                                                                                                                              | no   |
| `20_float_strays.sh`           | `strays = "float"` floats an unmatched window                                                                                                                                       | no   |
| `30_shelf_silent.sh`           | a shelf class routes to its special without showing it                                                                                                                              | no   |
| `40_mode_roundtrip.sh`         | work/gaming (+ neutral hop) round trips keep every window reachable                                                                                                                 | yes  |
| `50_headless_output.sh`        | a headless secondary output takes its scene; removal                                                                                                                                | no   |
| `60_navigation.sh`             | mod+h/l/j/k across tiles, into/out of a group, onto an empty monitor                                                                                                                | yes  |
| `65_focus_transitions.sh`      | work→study→gaming→work, timed expiry falls back to `previous`, neutral recovery — held sets and pointer fields at each step                                                         | yes  |
| `67_transition_focus_guard.sh` | a window opening mid-transition stays unfocused behind the veil; the bracket's no_focus guard holds the landing                                                                     | yes  |
| `70_boot_pointer.sh`           | boot: a stale pointer lands on `work`; an unexpired timed mode survives a restart                                                                                                   | no   |
| `75_undeclared_workspace.sh`   | a window on a workspace the host never declared moves to its monitor's own                                                                                                          | no   |
| `80_collect_home.sh`           | a claimed window standing elsewhere is re-homed to its scene, focus unmoved                                                                                                         | no   |
| `85_companion_cap.sh`          | a companion spawn past a block's `max_spawns` is capped, not spawned                                                                                                                | no   |
| `86_launch_claim.sh`           | a claimed launch is stowed and tracked wherever the shared profile's pin landed it                                                                                                  | no   |
| `90_live_gaps.sh`              | editing `conf/base.lua` gap numbers + reload applies them live (general + scene rule gaps)                                                                                          | no   |
| `90_deck.sh`                   | deck layout: exactly one member visible, flip changes it and follows focus                                                                                                          | yes  |
| `91_scene_gaps_reload.sh`      | a scene's own declared gaps beat the host profile; a store edit reaches the desk with no `hyprctl reload`                                                                           | no   |
| `92_bar_gap_publish.sh`        | the bar's opt-in gap is the distance to the scene's outermost VISIBLE window, not the layout's box                                                                                  | no   |
| `95_whichkey.sh`               | submap enter/leave against `hypr/lib/submap.lua`+`whichkey.lua`: enter is a real submap event, exit unwinds a nested chain and dismisses, a withheld tree never appears in the dump | yes  |
| `95_project_group.sh`          | `,proj.sh open` groups a project's real kitty windows on `code`; reopen refocuses/completes; last-window-close ends it                                                              | no   |
| `96_focus_reload.sh`           | a reload never moves focus; a mode's declared `main` scene is the fallback at session start / fresh entry, never a pull-back                                                        | yes  |
| `96_project_scope.sh`          | `,proj.sh open` with a declared scope spawns the scope's own command into the group; rerun refocuses instead of respawning; resolution matches the focused window                   | yes  |
| `97_bar_truth.sh`              | the REAL bar (not the `qs` stub): workspace rows populate, active row follows a same-monitor switch, compositor truth after a cross-monitor switch                                  | no   |
| `97_code_deck.sh`              | the `code` scene's own deck shape — a project column (one Hyprland group per project) beside a browser column                                                                       | yes  |
| `97_project_picker.sh`         | `,proj.sh pick` floats a project-classed picker on `code` outside every project group; the picker's own close does not steal focus back from the choice                             | no   |
| `98_project_focus_binds.sh`    | the `p`/`n`/`r` project binds resolve the focused project's live nvim/run window via `hypr/lib/project.lua` and focus it                                                            | yes  |

A scenario is a script that sources `lib.sh`, calls `e2e_start`, and exits
non-zero on failure (`e2e_fail`). Each gets its own nested compositor.

**Boot focus.** When the boot transition settles, `focus_mode_entry`
(`hypr/hyprfocus/init.lua`) lands on the mode's declared `main` scene and
re-asserts that landing at +1.2s/+3s/+6s: each check yanks focus back to
`main` whenever the active workspace is not main, and nothing gives it back.
A scenario that opens a project on another workspace inside that window has
its focus stolen out from under it, so focus-sensitive scenarios call
`wait_boot_focus_quiet` right after `e2e_start` (it waits the series out from
the settle `e2e_start` already stalls on). Scenarios that only spawn and
count windows never need it.

## Real bar (`E2E_REAL_BAR=1`, `97_bar_truth.sh`)

Every scenario above replaces `qs` with a logging stub (see "Isolation"), so
the bar's displayed state disagreeing with the compositor's actual state is
invisible to the suite by construction — a same-monitor workspace switch
that never updates the active-row highlight, say, would pass every scenario
here. `97_bar_truth.sh` is the one opt-out.

**Opting in** (per scenario, additive — every other scenario is unaffected
and keeps the fast stub):

```sh
E2E_REAL_BAR=1     # qs stays off the stub PATH; falls through to the real binary
E2E_BIG_MONITOR=1  # WAYLAND-1 sized wide enough that the bar's islands don't overlap
e2e_start
bar_start WAYLAND-1                    # launch the real bar, wait for its layer
bar_shot WAYLAND-1 "$path.png"         # screenshot exactly the bar's own layer geometry
bar_diff "$a.png" "$b.png"             # differing-pixel count between two shots
```

`bar_start` launches `qs -p <sibling quickshell checkout>/shell.qml` directly
(the same "run from a checkout" mode quickshell's own README documents),
bypassing `hypr/events/start.lua`'s production launch line entirely — that
file deliberately never launches anything under `QF_E2E` (its own comment:
the nested compositor "starts nothing outside itself"), so these helpers
launch the bar the same deliberate, sandboxed way `spawn_test_window`
launches a test client. The checkout is found via `E2E_QS_PATH` if set, else
the sibling of this repo's own main checkout (not a worktree) named
`quickshell` — `bar_qs_path` resolves it with
`git worktree list --porcelain`, since a scenario run from inside
`.claude/worktrees/<name>` is not itself that sibling's neighbour.

**Sizing the nested output.** `hyprctl keyword monitor` / `monitorv2`
against a running instance is a confirmed no-op on this Lua-config build —
both answer `unknown request`, live, not a timing race — so the small
default output (auto mode/scale; a real bar's three islands overlap
unreadably at that width) cannot be resized after boot. What actually works:
sizing at **config load**, before Hyprland locks in the output's mode.
`hypr/monitors.lua` reads `QF_E2E_BIG_MONITOR` (set by `E2E_BIG_MONITOR=1`
before `e2e_start`) and calls `hl.monitor()` for `WAYLAND-1` explicitly, the
same mechanism the file's own default catch-all rule already uses. This is
opt-in and e2e-only (gated on `QF_E2E` too) — every other scenario keeps
today's small, fast output.

**What real pixels can and can't prove here.** `bar_shot` crops to the
`quickshell-bar` layer's own advertised geometry (from `hc -j layers`), so a
diff reflects the bar's actual rendered content, not notifications or
tooltips compositing elsewhere on the output. Confirmed working, live,
against the real `WAYLAND-1` backend output (`WLR_RENDERER=pixman`, same as
`hq shot`). Against a `headless` output (`hyprctl output create headless
...`, used for the secondary monitor / `aside` scene), `grim` fails outright
with `failed to create buffer` — a headless output has no compositor-side
buffer to screencopy at all, unrelated to `WLR_RENDERER` (which only fixes
this for a real backend output). So `97_bar_truth.sh`'s cross-monitor leg
verifies the switch through compositor truth (`hyprctl -j monitors`) and
confirms the primary bar keeps rendering correctly once a second bar
instance exists, rather than pixel-diffing the secondary bar directly — a
real gap, not a stub covering for it, documented here since every future
on-screen scenario runs into the same limits.
