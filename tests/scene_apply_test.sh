#!/usr/bin/env bash
# Functional tests for ,scene-apply.sh — the mood-mode systemd seam (LEO-238).
#
# The script's job is stopping/starting real user units, so the tests give it a
# fake desk: XDG_STATE_HOME points into a scratch tree seeded with the stores
# (`focus.json` + `mood-policy.json`, the shapes the shell writes), and
# SYSTEMCTL points at a recorder so the real desktop is never touched. The
# contract under test is the repo's own etc/scene-managed.json, so the tests
# derive the expected unit sets from it rather than hard-coding them.

set -euo pipefail

ROOT_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENE_APPLY="$ROOT_REPO/bin/,scene-apply.sh"
CONTRACT="$ROOT_REPO/etc/scene-managed.json"
FIXTURE="$ROOT_REPO/tests/fixtures/mood-policy.json"
pass=0
fail=0

check() {
    local what=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        pass=$((pass + 1))
        printf '  ok   %s\n' "$what"
    else
        fail=$((fail + 1))
        printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$what" "$expected" "$actual"
    fi
}

contains() {
    local what=$1 needle=$2 haystack=$3
    case "$haystack" in
    *"$needle"*)
        pass=$((pass + 1))
        printf '  ok   %s\n' "$what"
        ;;
    *)
        fail=$((fail + 1))
        printf '  FAIL %s\n       %q not found in: %s\n' "$what" "$needle" "$haystack"
        ;;
    esac
}

not_contains() {
    local what=$1 needle=$2 haystack=$3
    case "$haystack" in
    *"$needle"*)
        fail=$((fail + 1))
        printf '  FAIL %s\n       %q unexpectedly found in: %s\n' "$what" "$needle" "$haystack"
        ;;
    *)
        pass=$((pass + 1))
        printf '  ok   %s\n' "$what"
        ;;
    esac
}

# A scratch desk: the two stores the script reads, shaped like the shell's.
setup() {
    ROOT=$(mktemp -d)
    export XDG_STATE_HOME="$ROOT/state"
    export QF_STORE="$XDG_STATE_HOME/quantum-store"
    mkdir -p "$XDG_STATE_HOME" "$QF_STORE"

    # The systemctl recorder. Appends its arguments and succeeds, so the script
    # takes the same path it would on a real desk without touching one.
    SYSTEMCTL_LOG="$ROOT/systemctl.log"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$SYSTEMCTL_LOG" >"$ROOT/systemctl"
    chmod +x "$ROOT/systemctl"
    export SYSTEMCTL="$ROOT/systemctl"
    : >"$SYSTEMCTL_LOG"

    cp "$FIXTURE" "$XDG_STATE_HOME/mood-policy.json"
}

teardown() {
    unset SYSTEMCTL
    rm -rf "$ROOT"
}

run() { "$SCENE_APPLY" "$@"; }
stopper() { cat "$SYSTEMCTL_LOG"; }
scan_units() { jq -r --arg s "$1" '.scenes[$s].stop[]?' "$CONTRACT"; }
graceful_units() { jq -r --arg s "$1" '.scenes[$s].graceful[]?' "$CONTRACT"; }

echo "gaming: the mood's reachable scene brings the contract's stop list under systemd"
setup
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
run gaming
for unit in $(scan_units gaming); do
    contains "gaming stops $unit" "--user stop $unit" "$(stopper)"
done
for unit in $(graceful_units gaming); do
    not_contains "graceful $unit is never stopped, only requested" "--user stop $unit" "$(stopper)"
done
for unit in $(jq -r '.protected[]?' "$CONTRACT"); do
    not_contains "protected $unit is never touched" "--user stop $unit" "$(stopper)"
done
check "the applied state records the mood that stopped them" "gaming" \
    "$(jq -r '.mode' "$QF_STORE/scene-policy/applied.json")"
teardown

echo "returning to neutral hands the stopped units back"
setup
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
run gaming
printf '{"mode":"neutral","until":null}' >"$XDG_STATE_HOME/focus.json"
run neutral
for unit in $(scan_units gaming); do
    contains "leaving gaming restarts $unit" "--user start $unit" "$(stopper)"
done
check "neutral's applied state stops nothing" "<none>" \
    "$(jq -r '.stopped | if length == 0 then "<none>" else .[] end' "$QF_STORE/scene-policy/applied.json" | tr '\n' ' ' | sed 's/ *$//')"
teardown

echo "a lapsed timed mood reads as neutral and applies nothing"
setup
printf '{"mode":"work","until":"2000-01-01T00:00:00.000Z"}' >"$XDG_STATE_HOME/focus.json"
contains "stale until resolves to neutral" "PLAN mood=neutral stop=<none>" "$(run --dry-run 2>&1)"
teardown

echo "moods with no reachable scene leave the desk's units alone"
setup
for mode in neutral work study; do
    printf '{"mode":"%s","until":null}' "$mode" >"$XDG_STATE_HOME/focus.json"
    run "$mode"
done
not_contains "units that only a reachable scene stops are not stopped" "--user stop obsidian" "$(stopper)"
not_contains "and nothing is started during a no-op apply" "--user start" "$(stopper)"
teardown

teardown

echo "a prevented background task maps to its contract units at apply time"
setup
jq '.moods.gaming.background.prevent = ["obsidian"]' "$FIXTURE" >"$XDG_STATE_HOME/mood-policy.json"
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
plan=$(run gaming --dry-run)
for unit in $(jq -r '.tasks.obsidian[]?' "$CONTRACT"); do
    contains "prevented task plans $unit" "would-stop: $unit" "$plan"
done
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
