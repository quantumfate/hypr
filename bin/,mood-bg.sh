#!/usr/bin/env bash
# ,mood-bg.sh <task> — dispatch-time gate for background work (LEO-238). A
# timer sidecar or long-running loop consults this before doing real work; the
# ACTIVE mood's background policy decides the verdict and the exit code tells
# the caller whether to run now, wait, or not run at all:
#
#   allow / unset   0   run it (anything not listed runs; LEO-252 retired
#                       the wildcard/policy vocabulary from the store)
#   defer           2   wait for a friendlier mood
#   prevent         3   off while the current mood runs
#
# Same philosophy as ,focus-guard.sh: the verdict is read at dispatch time via
# the focus IPC, never compiled in, so switching moods needs no reload — the
# next run simply sees the new mood. Fails OPEN when the shell IPC cannot be
# reached: a broken socket must not silently stop legitimate background work.
set -euo pipefail

task=${1:?usage: ,mood-bg.sh <task>}
verdict=$(qs -c quantumfate ipc call -- focus bg "$task" 2>/dev/null) || verdict=allow

case "$verdict" in
allow | unset) exit 0 ;;
defer)
    echo "deferred: $task waits for a friendlier mood" >&2
    exit 2
    ;;
prevent)
    echo "prevented: $task is off while the current mood runs" >&2
    exit 3
    ;;
*) exit 0 ;; # unknown verdict — treat as open
esac
