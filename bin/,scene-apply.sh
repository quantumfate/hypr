#!/usr/bin/env bash
# ,scene-apply.sh [mode] — bring user-unit background work in line with the
# active focus mood (LEO-238). This is the enforcement seam: Focus.qml spawns
# it detached whenever the active mood changes, and it runs the same store the
# shell reads, so the desk's systemd reality follows its policy.
#
# It computes TWO unit sets from the mood-policy store + this repo's contract
# (etc/scene-managed.json):
#
#   stop   — the units the mood's deferred and prevented background tasks map
#            to through the contract's capability map (the mood panel's
#            allow/defer/prevent cycle). Scene reachability lives in the
#            DECLARATION now: the gaming mode retires the Obsidian suite
#            through hyprfocus's own service resources, enforced by the CLI
#            apply spawned at every converge, and LEO-270 removed the scene
#            key from the contract because mode policy in the wrong home is
#            the divergence this milestone closes.
#   start  — whatever the previous apply had stopped that this mood no longer
#            stops (the handback for the task-level gates).
#
# Units on the contract's `protected` list are never touched, period. Stops go
# through systemd — SIGTERM + the unit's own TimeoutStopSec, never SIGKILL — so
# a service mid-write gets a chance to finish. A mood that DEFERS a task stops
# it like prevent does but records it as deferred. `graceful` entries names in
# the contract are only REQUESTED and logged: the message protocol is LEO-242,
# the seam here is that they are never forced.
#
# Every decision lands in $XDG_STATE_HOME/scene-policy/log.jsonl (the scene-
# policy logging workspace, LEO-241, reads it); the last state is written to
# applied.json so the next transition knows what to hand back. An optional
# mode argument forces a mood (the tests use it); without one it reads the
# store's focus.json like Focus does.
#
#   --dry-run   print the computed plan and log lines without touching systemd
#               — how the tests exercise the computation.
#   SYSTEMCTL   env var override (default systemctl) — the tests point it at a
#               recorder so the real desktop is never touched.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The shared quantum-store directory; the legacy paths are reads.
STATE_DIR="${QF_STORE:-${XDG_STATE_HOME:-$HOME/.local/state}/quantum-store}"
LEGACY_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
SYSTEMCTL=${SYSTEMCTL:-systemctl}

contract="$SCRIPT_DIR/../etc/scene-managed.json"
focus_file="$STATE_DIR/focus.json"
[ -f "$focus_file" ] || focus_file="$LEGACY_STATE_DIR/focus.json"
policy_file="$STATE_DIR/mood-policy.json"
[ -f "$policy_file" ] || policy_file="$LEGACY_STATE_DIR/mood-policy.json"
log_dir="$STATE_DIR/scene-policy"
log_file="$log_dir/log.jsonl"
applied_file="$log_dir/applied.json"

dry_run=0
mode_arg=""
for arg in "$@"; do
    case "$arg" in
    --dry-run) dry_run=1 ;;
    --help | -h | help)
        sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
        exit 0
        ;;
    *) mode_arg="$arg" ;;
    esac
done

need() { command -v "$1" >/dev/null 2>&1 || {
    echo ",scene-apply.sh: missing $1" >&2
    exit 1
}; }
need jq

[ -f "$contract" ] || {
    echo ",scene-apply.sh: missing contract $contract" >&2
    exit 1
}
mkdir -p "$log_dir"

ts() { date +%s; }
# One JSON line per decision/outcome (LEO-241 consumes this file). In --dry-run
# the line goes to stdout as a human plan instead.
log() {
    local action=$1 unit=$2 outcome=$3
    if [ "$dry_run" = 1 ]; then
        printf '  %s: %s\n' "$outcome" "$unit"
        return
    fi
    jq -nc --arg ts "$(ts)" --arg mood "$mode" \
        --arg action "$action" --arg unit "$unit" --arg outcome "$outcome" \
        '{ts: ($ts | tonumber), mood: $mood, action: $action, unit: $unit, outcome: $outcome}' \
        >>"$log_file"
}

# Resolve the mood for this apply: an explicit arg wins (tests/manual runs);
# otherwise read the store's focus.json exactly like Focus.active does — a
# timed mood whose `until` already passed reads as neutral.
if [ -z "$mode_arg" ]; then
    if [ -f "$focus_file" ]; then
        mode=$(jq -r '.mode // "neutral"' "$focus_file")
        until=$(jq -r '.until // ""' "$focus_file")
        if [ "$mode" != neutral ] && [ -n "$until" ]; then
            until_ms=$(date -d "$until" +%s%3N 2>/dev/null || echo 0)
            [ "$(date +%s%3N)" -gt "$until_ms" ] && mode=neutral
        fi
    else
        mode=neutral
    fi
else
    mode="$mode_arg"
fi

# The mood's policy record; neutral (or a missing store) reads as the resting
# mood — nothing restricted.
if [ "$mode" = neutral ] || [ ! -f "$policy_file" ]; then
    mood='{}'
else
    mood=$(jq -c --arg m "$mode" '.moods[$m] // {}' "$policy_file")
fi

# Protected units are a hard rail: never logged as stop/start candidates.
protected=()
while IFS= read -r unit; do
    [ -n "$unit" ] && protected+=("$unit")
done < <(jq -r '.protected[]? // empty' "$contract")

# The previous applied state (what the last transition stopped).
stopped_now=()
while IFS= read -r unit; do
    [ -n "$unit" ] && stopped_now+=("$unit")
done < <(jq -r '.stopped[]? // empty' "$applied_file" 2>/dev/null || true)

is_protected() {
    local unit=$1
    for p in "${protected[@]}"; do [ "$p" = "$unit" ] && return 0; done
    return 1
}

# Build the stop set (space-separated; unit names never contain spaces).
stop_units=""
add_stop() {
    local unit=$1
    [ -z "$unit" ] && return
    if is_protected "$unit"; then
        log skip-protected "$unit" "skipped"
        return
    fi
    case " $stop_units " in
    *" $unit "*) ;;
    *) stop_units="$stop_units $unit" ;;
    esac
}

# The mood's own scene policy lives in the declaration, not here: the mode's
# services (remove-gaming's obsidian suite, etc.) are enforced as CLI apply at
# every converge (hypr/hyprfocus/init.lua). What this script stops is the
# mood's OWN task-level policy (the mood panel's allow/defer/prevent cycle):
# deferred tasks stop now and come back when the mood does, prevented tasks
# stop too, and (LEO-270) the contract is pure capability-to-units: a scene
# key read here would be policy in the wrong home again.

# Task-level gates: deferred and prevented tasks map to their units. Defer is
# stop-now (it waits for a friendlier mood), just recorded as deferred.
while IFS= read -r task; do
    [ -z "$task" ] && continue
    while IFS= read -r unit; do
        [ -n "$unit" ] && add_stop "$unit"
    done < <(jq -r --arg t "$task" '.tasks[$t][]? // empty' "$contract")
done < <(printf '%s' "$mood" | jq -r '.background.defer[]? // empty')

while IFS= read -r task; do
    [ -z "$task" ] && continue
    while IFS= read -r unit; do
        [ -n "$unit" ] && add_stop "$unit"
    done < <(jq -r --arg t "$task" '.tasks[$t][]? // empty' "$contract")
done < <(printf '%s' "$mood" | jq -r '.background.prevent[]? // empty')

# Units to hand back: previously stopped, no longer in the stop set.
starts=""
for unit in "${stopped_now[@]}"; do
    case " $stop_units " in
    *" $unit "*) ;;
    *) starts="$starts $unit" ;;
    esac
done

# Apply, or print the plan under --dry-run. systemd stop/start sends SIGTERM and
# honours the unit's own TimeoutStopSec — nothing is ever force-killed here.
for unit in $stop_units; do
    if [ "$dry_run" = 1 ]; then
        log stop "$unit" "would-stop"
        continue
    fi
    if "$SYSTEMCTL" --user stop "$unit" >/dev/null 2>&1; then
        log stop "$unit" "stopped"
    else
        log stop "$unit" "failed"
    fi
done

for unit in $starts; do
    if [ "$dry_run" = 1 ]; then
        log start "$unit" "would-start"
        continue
    fi
    if "$SYSTEMCTL" --user start "$unit" >/dev/null 2>&1; then
        log start "$unit" "started"
    else
        log start "$unit" "failed"
    fi
done

# Persist the applied state so the next transition knows what to hand back.
stopped_json=$(printf '%s' "$stop_units" | jq -R -s 'split(" ") | map(select(length > 0))')
jq -nc --arg mode "$mode" --argjson stopped "$stopped_json" '{mode: $mode, stopped: $stopped}' \
    >"$applied_file.tmp" && mv "$applied_file.tmp" "$applied_file"

if [ "$dry_run" = 1 ]; then
    printf '\n  PLAN mood=%s stop=%s hand-back=%s\n' "$mode" "${stop_units:-<none>}" "${starts:-<none>}"
fi
