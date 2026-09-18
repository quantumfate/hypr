#!/usr/bin/env bash
# Boot decision (hypr/hyprfocus/boot.lua, wired into hyprland.start by
# hypr/events/start.lua): login always enters `work`, unless the pointer
# names a still-running timed mode, which resumes and keeps its `previous`.
# Verified across an actual compositor restart, not just the mode watcher's
# converge — that's the only way to see `hyprland.start` fire twice against
# the same $QF_STORE. No eval.
. "$(dirname "$0")/../lib.sh"

# Captured before e2e_start repoints XDG_RUNTIME_DIR/WAYLAND_DISPLAY at the
# sandbox, so the restart below can still reach the parent's real socket.
PARENT_RUNTIME=$XDG_RUNTIME_DIR
PARENT_WAYLAND=$WAYLAND_DISPLAY

e2e_start

PARENT_WL=$PARENT_WAYLAND
[[ $PARENT_WL == /* ]] || PARENT_WL="$PARENT_RUNTIME/$PARENT_WL"

# Kill the nested compositor and relaunch it against the SAME sandbox root
# (same $QF_STORE, same $XDG_RUNTIME_DIR) — a restart, not a fresh sandbox.
restart_nested() {
    kill -TERM "$E2E_PID" 2>/dev/null || true
    for _ in $(seq 50); do
        kill -0 "$E2E_PID" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL "$E2E_PID" 2>/dev/null || true
    wait "$E2E_PID" 2>/dev/null || true
    E2E_SIG=""
    WAYLAND_DISPLAY="$PARENT_WL" Hyprland --config "$E2E_REPO/hyprland.lua" \
        >"$E2E_ROOT/hyprland-restart.log" 2>&1 &
    E2E_PID=$!
    local waited=0 dir
    while ((waited < E2E_BOOT_TIMEOUT * 10)); do
        kill -0 "$E2E_PID" 2>/dev/null || {
            tail -n 40 "$E2E_ROOT/hyprland-restart.log" >&2
            e2e_fail "nested Hyprland exited during restart"
        }
        for dir in "$XDG_RUNTIME_DIR"/hypr/*/; do
            if [[ -S $dir.socket.sock ]]; then
                E2E_SIG=$(basename "$dir")
                break 2
            fi
        done
        sleep 0.1
        waited=$((waited + 1))
    done
    [[ -n $E2E_SIG ]] || e2e_fail "no instance socket after restart"
    export HYPRLAND_INSTANCE_SIGNATURE=$E2E_SIG
    wait_until 100 hc -j monitors >/dev/null
}

# --- Case 1: a stale (open-ended) `neutral` pointer boots into `work` -------
cat >"$QF_STORE/focus.json" <<'EOF'
{ "mode": "neutral", "until": null, "source": "manual", "set_at": "2020-01-01T00:00:00Z", "previous": null }
EOF
restart_nested
wait_until 50 sh -c "jq -e '.mode == \"work\"' '$QF_STORE/focus.json'" ||
    e2e_fail "boot from a neutral pointer did not land on work: $(cat "$QF_STORE/focus.json")"
e2e_log "PASS boot: neutral pointer -> work"

# --- Case 2: an unexpired timed mode survives a restart, `previous` intact -
FUTURE=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
cat >"$QF_STORE/focus.json" <<EOF
{ "mode": "gaming", "until": "$FUTURE", "source": "timer", "set_at": "2020-01-01T00:00:00Z", "previous": "work" }
EOF
restart_nested
wait_until 50 sh -c "jq -e '.mode == \"gaming\" and .previous == \"work\"' '$QF_STORE/focus.json'" ||
    e2e_fail "an unexpired timed mode did not survive a restart: $(cat "$QF_STORE/focus.json")"
e2e_log "PASS boot: unexpired timed mode resumes and keeps previous"
