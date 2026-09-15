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
echo "the contract is a pure capability map: no scene key anywhere (LEO-270)"
setup
check "the contract carries protected + tasks only" "protected,tasks" \
    "$(jq -r 'keys | sort | join(",")' "$CONTRACT")"
teardown

echo "gaming: scene reachability stops nothing here - the declaration's services do"
setup
jq '.moods.gaming.background = {"policy":"allow","allow":["*"],"defer":[],"prevent":[]}' \
    "$FIXTURE" >"$XDG_STATE_HOME/mood-policy.json"
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
run gaming
not_contains "scene-apply stops nothing for a reachable scene" "--user stop obsidian" "$(stopper)"
check "the applied state records the mood that stopped them" "gaming" \
    "$(jq -r '.mode' "$QF_STORE/scene-policy/applied.json")"
teardown

echo "no mood-policy with real gate decision leaves units untouched"
setup
for mode in gaming work study; do
    printf '{"mode":"%s","until":null}' "$mode" >"$XDG_STATE_HOME/focus.json"
    run "$mode"
done
not_contains "task-gate-less moods leave the desk's units alone" "--user stop obsidian" "$(stopper)"
not_contains "and nothing is started during a no-op apply" "--user start" "$(stopper)"
teardown

echo "a lapsed timed mood reads as neutral and applies nothing"
setup
printf '{"mode":"work","until":"2000-01-01T00:00:00.000Z"}' >"$XDG_STATE_HOME/focus.json"
contains "stale until resolves to neutral" "PLAN mood=neutral stop=<none>" "$(run --dry-run 2>&1)"
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

echo "a veto holds a stop, once, and the transition completes (LEO-256)"
setup
jq '.moods.gaming.background.prevent = ["obsidian"]' "$FIXTURE" >"$XDG_STATE_HOME/mood-policy.json"
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
# The unit files its own refusal: mid-work windows, in its own words.
mkdir -p "$QF_STORE/scene-policy"
printf '{"%s":{"reason":"indexing a large vault","until":9999999999999}}\n' \
    "$(jq -r '.tasks.obsidian[0]' "$CONTRACT")" >"$QF_STORE/scene-policy/veto.json"
run gaming
not_contains "a vetoing unit is not stopped" "--user stop $(jq -r '.tasks.obsidian[0]' "$CONTRACT")" "$(stopper)"
vetoes=$(jq -r '.vetoes[0].unit' "$QF_STORE/scene-policy/last.json")
check "the veto record names the unit" "$(jq -r '.tasks.obsidian[0]' "$CONTRACT")" "$vetoes"
check "and the reason the unit gave" "indexing a large vault" \
    "$(jq -r '.vetoes[0].reason' "$QF_STORE/scene-policy/last.json")"
# The next mood must not "hand the running unit back a start it never lost":
stopp=$(jq -r '.tasks.obsidian[0]' "$CONTRACT")
stopped_list=$(jq -r --arg s "$stopp" '.stopped | index($s) // -1' "$QF_STORE/scene-policy/applied.json")
check "a vetoed unit is not recorded as stopped" "-1" "$stopped_list"
teardown

echo "an expired veto does not hold"
setup
jq '.moods.gaming.background.prevent = ["obsidian"]' "$FIXTURE" >"$XDG_STATE_HOME/mood-policy.json"
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
mkdir -p "$QF_STORE/scene-policy"
printf '{"%s":{"reason":"stale window","until":1}}\n' \
    "$(jq -r '.tasks.obsidian[0]' "$CONTRACT")" >"$QF_STORE/scene-policy/veto.json"
plan=$(run gaming --dry-run)
not_contains "a lapsed refusal is not honoured" "vetoed" "$plan"
teardown

echo "the units gate logs the running manager's gaps (LEO-290)"
setup
jq '.moods.gaming.background.prevent = ["obsidian"]' "$FIXTURE" >"$XDG_STATE_HOME/mood-policy.json"
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/focus.json"
run gaming
if grep -q "not-installed" "$QF_STORE/scene-policy/log.jsonl"; then
    printf '  ok   absent declared units land in the log\n'
    pass=$((pass + 1))
else
    printf '  FAIL the units gate logged nothing\n'
    fail=$((fail + 1))
fi
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
