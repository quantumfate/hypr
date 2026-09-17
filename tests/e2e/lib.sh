#!/usr/bin/env bash
# Nested-Hyprland harness: source it, call e2e_start, drive the instance with
# `hc`, assert, and let the EXIT trap tear everything down.
#
# Safety contract: every hyprctl call goes through `hc`, which always passes
# `-i <nested signature>` and refuses to run if that signature is empty or
# equals the parent session's. Runtime, state, cache, store and config dirs
# are all under one mktemp root; external commands the config spawns (qs,
# uwsm, notify-send, systemctl, setxkbmap, ,hyprfocus) resolve to logging
# stubs.

set -euo pipefail

E2E_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
E2E_DIR="$E2E_REPO/tests/e2e"
E2E_PARENT_SIG=${HYPRLAND_INSTANCE_SIGNATURE:-}
E2E_BOOT_TIMEOUT=${E2E_BOOT_TIMEOUT:-20}
E2E_ROOT=""
E2E_PID=""
E2E_SIG=""
E2E_WAYLAND=""

e2e_log() { printf 'e2e: %s\n' "$*" >&2; }
e2e_fail() {
    printf 'e2e: FAIL: %s\n' "$*" >&2
    exit 1
}

# Kill the nested compositor and remove the sandbox. Safe to call twice.
e2e_stop() {
    if [[ -n $E2E_PID ]] && kill -0 "$E2E_PID" 2>/dev/null; then
        kill -TERM "$E2E_PID" 2>/dev/null || true
        for _ in $(seq 50); do
            kill -0 "$E2E_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$E2E_PID" 2>/dev/null || true
        wait "$E2E_PID" 2>/dev/null || true
    fi
    E2E_PID=""
    if [[ -n $E2E_ROOT && -d $E2E_ROOT && ${E2E_KEEP:-0} != 1 ]]; then
        # Spawned test clients die with the compositor; anything left in the
        # sandbox's process group goes too.
        pkill -f "$E2E_ROOT" 2>/dev/null || true
        command rm -rf -- "$E2E_ROOT"
    fi
}

# Build the sandbox and boot the nested compositor; sets E2E_ROOT/E2E_PID/
# E2E_SIG/E2E_WAYLAND. No EXIT trap: callers that want ephemeral teardown use
# e2e_start below; `hq up` (tests/e2e/hq) calls this directly to keep the
# instance running past its own process.
#
# --detach: launch Hyprland in its own session (setsid) and disown it, so it
# survives the launching shell exiting. Used by `hq up`; scenarios don't need
# it since their EXIT trap (e2e_start) kills it deliberately.
e2e_boot() {
    local detach=${1:-}
    [[ -n ${WAYLAND_DISPLAY:-} ]] || e2e_fail "no parent WAYLAND_DISPLAY: nested Hyprland needs a Wayland session"
    local parent_rt=${XDG_RUNTIME_DIR:?}
    local parent_wl=$WAYLAND_DISPLAY
    [[ $parent_wl == /* ]] || parent_wl="$parent_rt/$parent_wl"

    E2E_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qf-e2e.XXXXXX")

    mkdir -p "$E2E_ROOT"/{run,state,cache,config,store,bin}
    chmod 700 "$E2E_ROOT/run"
    # hyprland.lua finds its modules under $XDG_CONFIG_HOME/hypr.
    ln -s "$E2E_REPO" "$E2E_ROOT/config/hypr"
    cp "$E2E_DIR/fixtures/hyprfocus.json" "$E2E_ROOT/store/"
    # Named off the store rule so the privacy gate never reads a fixture as a diary.
    cp "$E2E_DIR/fixtures/focus.pointer.json" "$E2E_ROOT/store/focus.json"
    for name in qs notify-send uwsm systemctl setxkbmap ,hyprfocus; do
        ln -s "$E2E_DIR/stubs/stub" "$E2E_ROOT/bin/$name"
    done

    export XDG_RUNTIME_DIR="$E2E_ROOT/run"
    export XDG_STATE_HOME="$E2E_ROOT/state"
    export XDG_CACHE_HOME="$E2E_ROOT/cache"
    export XDG_CONFIG_HOME="$E2E_ROOT/config"
    export QF_STORE="$E2E_ROOT/store"
    export QF_E2E=1
    export QF_HOST=e2e
    export E2E_STUB_LOG="$E2E_ROOT/stubs.log"
    export PATH="$E2E_ROOT/bin:$E2E_REPO/bin:$PATH"
    # Software rendering: dmabuf screencopy from a nested Wayland-backend
    # output is unreliable across GPUs/sandboxes ("failed to create buffer" in
    # grim); pixman buffers are plain shm and `hq shot` needs those to work.
    export WLR_RENDERER=pixman
    unset HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS

    if [[ $detach == --detach ]]; then
        setsid env WAYLAND_DISPLAY="$parent_wl" Hyprland --config "$E2E_REPO/hyprland.lua" \
            >"$E2E_ROOT/hyprland.log" 2>&1 &
        disown
    else
        WAYLAND_DISPLAY=$parent_wl Hyprland --config "$E2E_REPO/hyprland.lua" \
            >"$E2E_ROOT/hyprland.log" 2>&1 &
    fi
    E2E_PID=$!

    local waited=0 dir
    while ((waited < E2E_BOOT_TIMEOUT * 10)); do
        kill -0 "$E2E_PID" 2>/dev/null || {
            tail -n 40 "$E2E_ROOT/hyprland.log" >&2
            e2e_fail "nested Hyprland exited during boot"
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
    [[ -n $E2E_SIG ]] || e2e_fail "no instance socket after ${E2E_BOOT_TIMEOUT}s"
    [[ $E2E_SIG != "$E2E_PARENT_SIG" ]] || e2e_fail "nested signature equals the parent's; refusing"
    export HYPRLAND_INSTANCE_SIGNATURE=$E2E_SIG

    # The nested compositor's own client socket, for test windows.
    local sock
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        [[ -S $sock ]] && E2E_WAYLAND=$(basename "$sock") && break
    done
    [[ -n $E2E_WAYLAND ]] || e2e_fail "nested compositor has no wayland socket"
    wait_until 100 hc -j monitors >/dev/null
    # Small window: conf/hosts/e2e.lua is data and can't call hl.monitor()
    # itself, so pin WAYLAND-1's mode here, once, for every caller.
    hc keyword monitor "WAYLAND-1,1280x360@60,0x0,1" >/dev/null || true
    e2e_log "nested instance $E2E_SIG up (pid $E2E_PID, $E2E_WAYLAND, root $E2E_ROOT)"
}

# Ephemeral form: boot, arm the EXIT trap that tears it down. Scenarios use
# this; `hq up` uses e2e_boot directly so the instance outlives its process.
e2e_start() {
    trap e2e_stop EXIT
    trap 'exit 130' INT TERM
    e2e_boot
}

# hyprctl against the nested instance only.
hc() {
    [[ -n $E2E_SIG && $E2E_SIG != "$E2E_PARENT_SIG" ]] || e2e_fail "hc: no nested instance (refusing to reach the live session)"
    hyprctl -i "$E2E_SIG" "$@"
}

# wait_until <tenths> <cmd...>: retry until the command succeeds.
wait_until() {
    local tries=$1
    shift
    for _ in $(seq "$tries"); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}

# Clients as JSON.
clients() { hc -j clients; }

# The first client of a class, as JSON ("" if none).
client_of() { clients | jq -c --arg c "$1" 'map(select(.class == $c)) | first // empty'; }

has_class() { [[ -n $(client_of "$1") ]]; }

# wait_for_class <class> [tenths]
wait_for_class() {
    wait_until "${2:-100}" has_class "$1" || e2e_fail "no window of class $1 appeared"
}

# spawn_test_window <class>: a foot window on the nested instance, alive
# until the compositor goes away.
spawn_test_window() {
    local class=$1
    WAYLAND_DISPLAY=$E2E_WAYLAND setsid foot --app-id "$class" \
        sh -c "sleep 600 # $E2E_ROOT" >/dev/null 2>&1 &
    wait_for_class "$class"
}

# assert_eq <actual> <expected> <what>
assert_eq() {
    [[ $1 == "$2" ]] || e2e_fail "$3: expected '$2', got '$1'"
}

# go_workspace <name>: focus a named workspace on the nested instance.
go_workspace() {
    # hyprctl's dispatch argument is Lua on this config.
    hc dispatch "hl.dsp.focus({ workspace = [[name:$1]] })" >/dev/null ||
        e2e_fail "could not focus workspace $1"
    wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j activeworkspace | jq -e --arg n '$1' '.name == \$n'" ||
        e2e_fail "workspace $1 never became active"
}
