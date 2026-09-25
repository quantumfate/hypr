#!/usr/bin/env bash
# ,hyprfocus — the read-only verbs, pinned against the shipped declaration.
#
# The resolver now exists twice: in Lua for the compositor and here in Python
# for the CLI. That duplication is deliberate (the CLI must work with no
# compositor) and it is a real drift risk, so this pins what the Python side
# resolves to. If the two implementations disagree about what a mode means,
# one of them is wrong and this is where it shows.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cli="$here/../bin/,hyprfocus"
[[ -x $cli ]] || cli="$here/../,hyprfocus"

# Pointer-expiry conformance (mode fallback rule): shared fixtures with the
# Lua resolver's `M.effective_mode` (tests/hyprfocus_init_spec.lua), covering
# expiry -> `previous` and expiry -> `work`. Runs with no sibling checkout, so
# it sits ahead of the quickshell-declaration guard below.
pointer_fixtures="$here/fixtures/hyprfocus/pointer"
pointer_fail=0
for fixture in "$pointer_fixtures"/*.json; do
    result=$(
        python3 - "$cli" "$fixture" <<'PY'
import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader

cli_path, fixture_path = sys.argv[1], sys.argv[2]
loader = SourceFileLoader("hyprfocus_cli", cli_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

case = json.loads(open(fixture_path).read())
print(module.effective_mode(case["pointer"]))
PY
    )
    if [[ $result == "$(python3 -c "import json;print(json.load(open('$fixture'))['effective'])")" ]]; then
        echo "  ok   $(basename "$fixture")"
    else
        echo "  FAIL $(basename "$fixture") -> got $result"
        pointer_fail=1
    fi
done

# Overridable so a quickshell worktree can be checked before it merges.
declaration="${HYPRFOCUS_DECLARATION:-$here/../../quickshell/assets/hyprfocus.default.json}"

if [[ ! -f $declaration ]]; then
    echo "skip: sibling quickshell checkout not found at $declaration" >&2
    exit "$pointer_fail"
fi

fail=$pointer_fail
check() {
    local name=$1 expected=$2 actual=$3
    if [[ $actual == "$expected" ]]; then
        echo "  ok   $name"
    else
        echo "  FAIL $name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        fail=1
    fi
}

run() { "$cli" --declaration "$declaration" "$@"; }

# Game mode is the sharpest case: the widest scene set, and the one whose whole
# point is giving things up. Its workspaces are derived from its scene set.
check "gaming admits only its scene set's workspaces" \
    "dofus, pokemon, steam-games, proton, media" \
    "$(run resolve gaming | awk '/^workspaces/ {sub(/^workspaces */, ""); print}')"

check "gaming stops the Obsidian suite" \
    "theme-auto, state-backup, chezmoi, audio-notify" \
    "$(run resolve gaming | awk '/^services/ {sub(/^services */, ""); print}')"

# Each scene carries the monitor role the mode places it on.
check "gaming carries only its own scenes, placed by role" \
    "dofus@primary, pokemon@primary, steam-games@primary, proton@primary, media@secondary" \
    "$(run resolve gaming | awk '/^scenes/ {sub(/^scenes */, ""); print}')"

check "neutral is the recovery set" \
    "code@primary, proton@primary, logs@secondary" \
    "$(run resolve neutral | awk '/^scenes/ {sub(/^scenes */, ""); print}')"

# Dependency closure: nothing names the indexer, it arrives via `wants`.
check "neutral pulls in Obsidian's companions without naming them" \
    "theme-auto, obsidian, obsidian-index, linear-sync, state-backup, chezmoi, audio-notify" \
    "$(run resolve neutral | awk '/^services/ {sub(/^services */, ""); print}')"

# neutral is hidden: the recovery fallback is never listed as a peer.
check "every user-facing mode is listed, hidden ones are not" \
    "gaming work" \
    "$(run modes | sed 's/^[* ] *//' | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')"

# A typo must fail loudly rather than resolving to a desk missing a workspace.
if run resolve gamming >/dev/null 2>&1; then
    echo "  FAIL an unknown mode should exit non-zero"
    fail=1
else
    echo "  ok   an unknown mode exits non-zero"
fi

# Seeding, against a scratch state tree — never the machine this runs on.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

check "seeding installs the declaration" \
    "seeded $scratch/quantum-store/hyprfocus.json (3 modes)" \
    "$(QF_STORE=$scratch/quantum-store "$cli" seed "$declaration")"

# The store is edited at runtime, so a seed that clobbered it would throw away
# whatever was tuned by hand.
if QF_STORE=$scratch/quantum-store "$cli" seed "$declaration" >/dev/null 2>&1; then
    echo "  FAIL seeding over an existing store should refuse"
    fail=1
else
    echo "  ok   seeding over an existing store refuses"
fi

if QF_STORE=$scratch/quantum-store "$cli" seed "$declaration" --force >/dev/null 2>&1; then
    echo "  ok   --force replaces it"
else
    echo "  FAIL --force should replace it"
    fail=1
fi

# Version-keyed migration (LEO-337): a store stamped with a lower version than
# the shipped declaration is stale by construction, so it reseeds once with no
# --force. A sandboxed store, never the machine's real $QF_STORE.
migrate_scratch=$(mktemp -d)
trap 'rm -rf "$scratch" "$migrate_scratch"' EXIT
stale=$migrate_scratch/stale.json
jq '.version = 1' "$declaration" >"$stale"

QF_STORE=$migrate_scratch/quantum-store "$cli" seed "$stale" --force >/dev/null 2>&1

migrate_out=$(QF_STORE=$migrate_scratch/quantum-store "$cli" seed "$declaration" 2>&1)
if [[ $migrate_out == *"reseeded"* ]]; then
    echo "  ok   a stale-version store reseeds without --force"
else
    echo "  FAIL a stale-version store should reseed without --force"
    fail=1
fi
check "the stale store now equals the shipped declaration exactly" \
    "$(jq -S . "$declaration")" \
    "$(jq -S . "$migrate_scratch/quantum-store/hyprfocus.json")"

# One-way: seeding again at the now-current version still refuses without
# --force, so a store at the shipped version is never silently clobbered.
if QF_STORE=$migrate_scratch/quantum-store "$cli" seed "$declaration" >/dev/null 2>&1; then
    echo "  FAIL seeding again at the current version should refuse"
    fail=1
else
    echo "  ok   a store already at the shipped version still refuses without --force"
fi

# A declaration that cannot resolve is one the desk would fail on at the next
# mode change; failing at seed time is the cheaper place to find out.
broken=$scratch/broken.json
jq '.modes.gaming.scenes[1].name = "commms"' "$declaration" >"$broken"
if QF_STORE=$scratch/quantum-store "$cli" seed "$broken" --force >/dev/null 2>&1; then
    echo "  FAIL seeding an unresolvable declaration should refuse"
    fail=1
else
    echo "  ok   seeding an unresolvable declaration refuses"
fi

# Applying, against a recorder rather than the machine's own systemd. Nothing
# in this file may touch a real unit.
recorder=$scratch/systemctl
cat >"$recorder" <<'REC'
#!/usr/bin/env bash
# Answers `show` from three env lists, so a test can describe a desk and see
# what moves: ACTIVE names running units, MISSING names units nothing
# installed, ONESHOT names units that are actions rather than states.
args=("$@")
unit=${args[${#args[@]} - 1]}
for a in "${args[@]}"; do
    if [[ $a == show ]]; then
        [[ " ${MISSING:-} " == *" $unit "* ]] && load=not-found || load=loaded
        [[ " ${ACTIVE:-} " == *" $unit "* ]] && state=active || state=inactive
        [[ " ${ONESHOT:-} " == *" $unit "* ]] && kind=oneshot || kind=simple
        printf '%s\n%s\n%s\n' "$load" "$state" "$kind"
        exit 0
    fi
done
echo "${2:-} $unit" >>"$RECORD"
exit 0
REC
chmod +x "$recorder"

apply_with() {
    local active=$1 mode=$2 decl=${3:-$declaration}
    : >"$scratch/record"
    RECORD=$scratch/record ACTIVE=$active MISSING=${MISSING:-} ONESHOT=${ONESHOT:-} \
        SYSTEMCTL=$recorder QF_STORE=$scratch/quantum-store HYPRFOCUS_NO_THEME=1 \
        "$cli" --declaration "$decl" apply "$mode" >/dev/null 2>&1
    sort "$scratch/record" | tr '\n' ' ' | sed 's/ $//'
}

full_suite="obsidian.service obsidian-index-normalize.service obsidian-linear-sync.service obsidian-linear-sync.timer"
baseline="theme-auto.service theme-auto.timer state-backup.service state-backup.timer audio-notify.service"

check "entering game stops the Obsidian suite" \
    "stop obsidian-index-normalize.service stop obsidian-linear-sync.service stop obsidian-linear-sync.timer stop obsidian.service" \
    "$(apply_with "$full_suite $baseline" gaming)"

check "leaving game starts them again" \
    "start obsidian-index-normalize.service start obsidian-linear-sync.service start obsidian-linear-sync.timer start obsidian.service" \
    "$(apply_with "$baseline" neutral)"

# A unit already in the state the mode wants is left alone: switching between
# two modes that share a service must not stop and restart it.
check "a service both modes want is not touched" \
    "" \
    "$(apply_with "$baseline $full_suite" neutral)"

# The protected rail wins over any declaration: a hand-edited store must not be
# able to stop the audio stack or the idle daemon. Other units still move, so
# what is asserted is that no protected one was asked to stop.
protected_run=$(apply_with "pipewire.service hypridle.service theme-auto.service" game)
if [[ $protected_run == *"stop pipewire"* || $protected_run == *"stop hypridle"* ]]; then
    echo "  FAIL a protected unit was stopped"
    fail=1
else
    echo "  ok   protected units are never stopped"
fi

# Drift is reported rather than silently doing nothing: a task the contract
# does not implement means the declaration and the unit files have diverged.
drifted=$scratch/drifted.json
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['base']['services'].append('ghost')
d['modes']['neutral']['services'] = {'add': ['ghost']}
json.dump(d, open(sys.argv[2], 'w'))
" "$declaration" "$drifted"

# Captured rather than piped into grep: `grep -q` exits on the first match, the
# writer takes SIGPIPE, and `pipefail` would turn a passing check into a
# failing one.
drift_output=$(RECORD=$scratch/record ACTIVE='' SYSTEMCTL=$recorder QF_STORE=$scratch/quantum-store \
    HYPRFOCUS_NO_THEME=1 "$cli" --declaration "$drifted" apply neutral 2>&1)
if [[ $drift_output == *"have drifted"* ]]; then
    echo "  ok   an unimplemented task is reported, not ignored"
else
    echo "  FAIL an unimplemented task should be reported"
    fail=1
fi

# A unit nothing installed is named once and skipped. Retrying it will never
# succeed, and attempting it every transition turns a packaging problem into
# permanent noise that hides real failures.
missing_run=$(MISSING="theme-auto.service theme-auto.timer" apply_with "" neutral)
if [[ $missing_run == *"theme-auto"* ]]; then
    echo "  FAIL a unit that is not installed should not be attempted"
    fail=1
else
    echo "  ok   a unit that is not installed is skipped"
fi

missing_report=$(MISSING="theme-auto.service" RECORD=$scratch/record ACTIVE='' SYSTEMCTL=$recorder \
    QF_STORE=$scratch/quantum-store HYPRFOCUS_NO_THEME=1 "$cli" --declaration "$declaration" apply neutral 2>&1)
if [[ $missing_report == *"not installed: theme-auto.service"* ]]; then
    echo "  ok   a missing unit is named once"
else
    echo "  FAIL a missing unit should be named"
    fail=1
fi

# A oneshot is an action, not a state: starting one means "run it now", which
# is its timer's job. Left alone when admitted, so a transition does not
# re-trigger a sync every time it runs.
oneshot_run=$(ONESHOT="obsidian-linear-sync.service" apply_with "" neutral)
if [[ $oneshot_run == *"start obsidian-linear-sync.service"* ]]; then
    echo "  FAIL a oneshot should not be started by a transition"
    fail=1
else
    echo "  ok   a oneshot is left to its timer"
fi

# Stopping one is still meaningful: it cancels a run in flight.
oneshot_stop=$(ONESHOT="obsidian-linear-sync.service" apply_with "obsidian-linear-sync.service" gaming)
if [[ $oneshot_stop == *"stop obsidian-linear-sync.service"* ]]; then
    echo "  ok   a oneshot in flight is still cancelled"
else
    echo "  FAIL a running oneshot should be stoppable"
    fail=1
fi

# Every decision is appended: with a schedule able to change the mode on its
# own, "why did my desk do that" needs an answer.
if [[ -s $scratch/quantum-store/hyprfocus/log.jsonl ]]; then
    echo "  ok   decisions are logged"
else
    echo "  FAIL decisions should be logged"
    fail=1
fi

echo
[[ $fail -eq 0 ]] && echo "hyprfocus: all checks passed" || echo "hyprfocus: failures above"
exit $fail
