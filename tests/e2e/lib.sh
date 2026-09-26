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
#
# Opt-in real bar (per scenario, off by default): set `E2E_REAL_BAR=1` before
# calling `e2e_start`/`e2e_boot`. `qs` is then left off the stub PATH, so it
# resolves to the real quickshell binary, and `bar_start` launches it
# directly against the sibling checkout (see its header below). Every other
# scenario is unaffected -- the stub is still linked for `qs` whenever
# `E2E_REAL_BAR` is unset, exactly as before.

set -euo pipefail

E2E_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
E2E_DIR="$E2E_REPO/tests/e2e"
E2E_PARENT_SIG=${HYPRLAND_INSTANCE_SIGNATURE:-}
E2E_BOOT_TIMEOUT=${E2E_BOOT_TIMEOUT:-20}
E2E_ROOT=""
E2E_PID=""
E2E_SIG=""
E2E_WAYLAND=""
E2E_BAR_PID=""
declare -a E2E_EXTRA_PIDS=()
# When the boot transition settled (ns since epoch); the anchor
# `wait_boot_focus_quiet` measures the boot main-landing window from.
E2E_SETTLE_AT=0

# Track a background PID (e.g. the real bar) so e2e_stop kills it too --
# nothing outside the nested compositor's own client list dies with it
# automatically.
e2e_track_pid() { E2E_EXTRA_PIDS+=("$1"); }

e2e_log() { printf 'e2e: %s\n' "$*" >&2; }
e2e_fail() {
    printf 'e2e: FAIL: %s\n' "$*" >&2
    exit 1
}

# Kill the nested compositor and remove the sandbox. Safe to call twice.
e2e_stop() {
    local pid
    for pid in "${E2E_EXTRA_PIDS[@]-}"; do
        [[ -n $pid ]] && kill -TERM "$pid" 2>/dev/null || true
    done
    E2E_EXTRA_PIDS=()
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
        # E2E_REAL_BAR opts a scenario out of the qs stub alone: leaving it
        # unlinked here lets PATH fall through to the real quickshell binary.
        [[ $name == qs && ${E2E_REAL_BAR:-0} == 1 ]] && continue
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
    # Opt-in (E2E_BIG_MONITOR=1): hypr/monitors.lua sizes WAYLAND-1 to fit a
    # real bar's islands without overlap. Read at config load, not set here
    # via hyprctl -- see the "Real bar" section of this directory's Readme.
    [[ ${E2E_BIG_MONITOR:-0} == 1 ]] && export QF_E2E_BIG_MONITOR=1 || unset QF_E2E_BIG_MONITOR
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
    # Confirmed no-op on this Lua-config build ("unknown request" from
    # `hyprctl keyword`/`monitorv2` alike) -- kept as a harmless attempt in
    # case a future Hyprland build honors it, but E2E_BIG_MONITOR above
    # (hypr/monitors.lua, applied at config load) is what actually works.
    hc keyword monitor "WAYLAND-1,1280x360@60,0x0,1" >/dev/null || true
    # The sandbox contract in one assertion: every store write from here on
    # must land under the mktemp root. A scenario that lost these exports
    # would otherwise write to the live desk's store, which has happened.
    [[ $QF_STORE == "$E2E_ROOT/"* ]] ||
        e2e_fail "QF_STORE is not inside the sandbox root ($QF_STORE); refusing to touch the live store"
    e2e_log "nested instance $E2E_SIG up (pid $E2E_PID, $E2E_WAYLAND, root $E2E_ROOT)"
}

# Ephemeral form: boot, arm the EXIT trap that tears it down. Scenarios use
# this; `hq up` uses e2e_boot directly so the instance outlives its process.
e2e_start() {
    trap e2e_stop EXIT
    trap 'exit 130' INT TERM
    e2e_boot
    # Boot enters a mode like any other transition, and its bracket holds the
    # open-focus guard and phases the apply behind the veil. A scenario that
    # starts driving the desk before the settle races both (windows opening
    # unfocused, workspaces mid-move); the settle is the contract's done
    # point, so wait for it rather than for a duration.
    wait_transition_settled || e2e_fail "boot transition never settled"
    # The boot's main landing is scheduled from this same settle; scenarios
    # that assert focus wait the window out with wait_boot_focus_quiet.
    E2E_SETTLE_AT=$(date +%s%N)
}

# wait_transition_settled [tenths]: block until the transition store exists
# and names no active bracket. The compositor publishes the bracket for the
# whole transition (hypr/lib/transition.lua); asserting before it flips
# reads the desk mid-rearrangement.
wait_transition_settled() {
    wait_until "${1:-150}" sh -c "
        test -f '$QF_STORE/hyprfocus.transition.json' &&
        jq -e '.active == false' '$QF_STORE/hyprfocus.transition.json'
    "
}

# wait_boot_focus_quiet: block until the boot transition's grace is over.
# `focus_mode_entry` (hypr/hyprfocus/init.lua) lands on the mode's declared
# main scene when the boot transition settles, and the desk then stays quiet
# for `transition.GRACE_MS` (6000ms, hypr/lib/transition.lua `M.QUIET`): a
# window mapped inside it opens WITHOUT focus. A focus-sensitive step must
# wait the grace out first. The settle `e2e_start` already stalls on is the
# moment the grace starts, so +7s clears it with margin.
wait_boot_focus_quiet() {
    [[ $E2E_SETTLE_AT != 0 ]] || e2e_fail "wait_boot_focus_quiet: no settle recorded (e2e_start)"
    local tv=$((7000 * 1000000))
    while (($(date +%s%N) - E2E_SETTLE_AT < tv)); do
        sleep 0.1
    done
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
    local seen=""
    for _ in $(seq 50); do
        local cur
        # One garbled read during a busy boot must not sink the poll; the
        # loop retries.
        cur=$(hyprctl -i "$E2E_SIG" -j activeworkspace | jq -r '.name' 2>/dev/null) || cur=""
        seen="$seen $cur"
        [[ $cur == "$1" ]] && return 0
        sleep 0.1
    done
    e2e_fail "workspace $1 never became active (seen:$seen, transition: $(cat "$QF_STORE/hyprfocus.transition.json" 2>/dev/null))"
}

# --- Real bar (E2E_REAL_BAR=1 scenarios only) ------------------------------
#
# hypr/events/start.lua never launches qs under QF_E2E by design (see its
# comment: the nested compositor "starts nothing outside itself"), so these
# helpers launch it directly, the same way spawn_test_window launches a test
# client directly -- deliberate, sandboxed, and independent of the
# production `hl.exec_cmd("... uwsm app -- qs ...")` launch line.

# The quickshell checkout this repo is developed alongside: `E2E_QS_PATH` if
# set, else the sibling of this repo's OWN main checkout (not this worktree)
# named `quickshell`.
bar_qs_path() {
    if [[ -n ${E2E_QS_PATH:-} ]]; then
        printf '%s\n' "$E2E_QS_PATH"
        return
    fi
    local main_wt
    main_wt=$(git -C "$E2E_REPO" worktree list --porcelain | awk '/^worktree /{print $2; exit}')
    printf '%s\n' "$(dirname "$main_wt")/quickshell"
}

# Is a quickshell-bar layer up on the given monitor?
bar_layer_up() {
    hc -j layers | jq -e --arg m "$1" \
        '(.[$m].levels["2"] // []) | map(select(.namespace == "quickshell-bar")) | length > 0' \
        >/dev/null
}

# bar_start <monitor>: launch the real bar against the nested instance and
# wait for its layer-shell surface to attach to <monitor>. Requires
# E2E_REAL_BAR=1 (so `qs` isn't the stub) and a sibling quickshell checkout.
bar_start() {
    [[ ${E2E_REAL_BAR:-0} == 1 ]] || e2e_fail "bar_start: set E2E_REAL_BAR=1 before e2e_start"
    local monitor=$1 qs_path
    qs_path=$(bar_qs_path)
    [[ -f "$qs_path/shell.qml" ]] || e2e_fail "bar_start: no shell.qml at $qs_path (set E2E_QS_PATH)"
    QT_QPA_PLATFORM=wayland qs -p "$qs_path/shell.qml" >"$E2E_ROOT/qs.log" 2>&1 &
    E2E_BAR_PID=$!
    e2e_track_pid "$E2E_BAR_PID"
    wait_until 300 bar_layer_up "$monitor" || {
        tail -n 40 "$E2E_ROOT/qs.log" >&2
        e2e_fail "real bar never attached to $monitor"
    }
}

# bar_shot <monitor> <out.png>: screenshot exactly the bar's own layer
# geometry on <monitor> (real pixels off the nested compositor's own
# output -- see tests/e2e/Readme.md "Real bar" for what this can and can't
# capture).
bar_shot() {
    local monitor=$1 out=$2 geo
    # `|| true`: a plain assignment's exit status is the pipeline's under
    # `set -e`, and hc can glitch mid-transition -- surface the real error
    # via the explicit checks below instead of dying here with no message.
    geo=$(hc -j layers | jq -r --arg m "$monitor" \
        '(.[$m].levels["2"] // []) | map(select(.namespace == "quickshell-bar")) | first
         | if . == null then empty else "\(.x),\(.y) \(.w)x\(.h)" end') || true
    [[ -n $geo ]] || e2e_fail "bar_shot: no quickshell-bar layer on $monitor"
    WAYLAND_DISPLAY="$E2E_WAYLAND" grim -g "$geo" "$out" || e2e_fail "bar_shot: grim failed for $monitor ($geo)"
}

# bar_diff <img1> <img2>: count of differing pixels between two screenshots.
# `compare` exits 1 when the images DIFFER (its normal, expected outcome
# here) and 2 on a real error -- `|| true` so a genuine difference doesn't
# look like a shell failure under `set -e`.
bar_diff() {
    compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}' || true
}
