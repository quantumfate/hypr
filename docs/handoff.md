# Handoff — 2026-09-19

Start here, then delete this file when the two items below are done.
Read `AGENTS.md` first; everything here assumes it.

## State

All three repos are on `main`, unpushed, gates green except one known
failure (below). The desk is working: saves apply live, gaps apply, theme
follows day/night, shelf keys work, close works, project keys exist, the
bar derives the active workspace by name, a reload keeps focus, a fresh
store seeds itself.

**Known failing spec:** `tests/host_geometry_publish_spec.lua` expects the
desk-dual primary gap of 80, and the working tree has the user's own
uncommitted tuning (`conf/base.lua`, primary `gaps_out.right = 15`). Do not
revert it. Ask the user for their final numbers, then commit them and update
the spec.

## Unfinished work — two branches, nothing lost

### 1. Project picker: pin and move — `worktree-agent-a07309e5fef2c15b6`

Worktree: `.claude/worktrees/agent-a07309e5fef2c15b6` (uncommitted changes in
`bin/,proj.sh`).

The user's design: the picker should join the project's group temporarily —
appearing in place as one of its tabs rather than as a floating stranger —
and when a choice is made, focus moves to the chosen window and the picker
goes away. tmux's feel, without tmux.

The agent was mid-fix on a real bug it had just diagnosed: a `set -e` trap on
`own_addr=$(own_window_address)` in `bin/,proj.sh`. Verify that fix, finish the
scenario (it was rewriting `tests/e2e/scenarios/97_*` to drive the real
`pick()` path with its own `fzf` stub on PATH), and confirm live in the nested
instance that `n` and `r` focus the active project's nvim/run windows.

### 2. Bar truth + the real shell in the harness — `bar-truth` (quickshell), `.claude/worktrees/bar-truth` (hypr)

Two halves:

- **Read truth, not the model.** `modules/bar/Workspaces.qml` re-evaluates on
  every compositor event but reads `Hyprland.monitorFor(screen).activeWorkspace.name`
  — a Quickshell model object that only refreshes its monitor state on
  monitor-crossing events, which is why the highlight lags on a same-monitor
  switch. Take the workspace from the raw event payload (`workspace>>name`,
  `workspacev2`, `focusedmon>>mon,name`; watch socket2 live to see what this
  build actually emits), or force an explicit refresh before reading. Also:
  the user does not want the scene-name text at all — icon only, keyed by name.
- **Run the real shell in the harness.** `tests/e2e/lib.sh` stubs `qs` with a
  logger, so the bar is never exercised and no test can see a bar/compositor
  disagreement. Make running the real shell opt-in per scenario, then write the
  scenario that would have caught all three of this family's bugs: rows
  populate, same-monitor switch moves the highlight, monitor crossing moves it
  too.
  **Constraint, already established:** the harness's monitor pin is a silent
  no-op on this build (`hyprctl keyword` → "unknown request"; the wayland
  backend refuses mode changes), so the nested output is stuck at 320x90
  logical. Size it where the nested compositor is **launched**, not by
  dispatching afterwards, and record the finding in `tests/e2e/Readme.md`.

## Verification the user still owes

Live, on the real desk, before closing issues:

1. The code workspace on `deck`: open two repo projects, `mod+ctrl+j/k` scrolls
   the strip, `mod+j/k` still moves inside a group.
2. A config write leaves focus where it was.
3. The bar's active highlight follows a same-monitor workspace switch.
4. Clicking a workspace icon in the bar does something (LEO-337, unresolved —
   nothing wrong found in the dispatch, needs a live spike).

## Rules that bit us today, do not relearn them

- **Never trust a stored override.** A `{"forced":"laptop-solo"}` in
  `hypr/monitor-profile.json` made the desktop run laptop geometry for two
  weeks and corrupted every diagnosis, including three by AI. State that beats
  live detection must announce itself.
- **Never trust a model when the compositor can be asked.** Workspace ids are
  gone in this build; anything keyed on them silently collapses.
- **`A || B + C` binds as `A || (B + C)`** — that precedence bug pointed three
  FileViews at the store directory and spun forever.
- Unrequested conveniences are not free. The profile pin nobody asked for cost
  two weeks.

## Blog

`~/Projects/blog/the-haunting-bug/` (transcript + README) and
`~/Projects/blog/column-core-vision/`. The user wants the final transcript
published with updated README context once the verification above passes.
