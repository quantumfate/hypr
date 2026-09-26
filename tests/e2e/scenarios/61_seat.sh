#!/usr/bin/env bash
# The seat (hypr/events/seat.lua) and the monitor-scoped switch
# (hypr/lib/desk.lua), driven through the REAL bind closures
# (`hypr.hyprfocus.binds`.action, since `send_shortcut` does not re-enter Lua
# binds in this sandbox):
#
#   * mod+l / mod+h cross onto the empty secondary and back, three times, and
#     each return lands on a window;
#   * the pointer is brought along with every cross;
#   * pointer motion alone does not move the seat;
#   * a workspace switch for one monitor never takes the keyboard to the
#     other, even for a workspace standing on the other one.
. "$(dirname "$0")/../lib.sh"

run_lua() {
    local result="$E2E_ROOT/seat-result.json"
    command rm -f -- "$result"
    local wrapped="package.path = package.path .. \";$E2E_REPO/?.lua\"
local json = require(\"hypr.lib.json\")
local function out(tbl)
  local f = assert(io.open(\"$result\", \"w\"))
  f:write(json.encode(tbl))
  f:close()
end
$1"
    hc eval "$wrapped" >/dev/null || e2e_fail "lua snippet failed: $1"
    wait_until 30 test -f "$result" || true
    [[ -f $result ]] && cat "$result" || echo '{}'
}

key() {
    run_lua "require('hypr.hyprfocus.binds').action('$1')() out({})" >/dev/null
    sleep 0.6
}

# seat monitor, the monitor under the pointer, and the focused class.
where() {
    run_lua "
local nav = require('hypr.lib.nav')
local c = hl.get_cursor_pos()
local w = hl.get_active_window()
out({ seat = require('hypr.events.seat').monitor(),
      pointer = c and nav.monitor_at(hl.get_monitors(), c.x, c.y) or '',
      win = w and w.class or '' })"
}

expect() {
    local label=$1 filter=$2 got
    got=$(where)
    jq -e "$filter" <<<"$got" >/dev/null || {
        [[ -f $E2E_ROOT/seat-events.log ]] && cat "$E2E_ROOT/seat-events.log" >&2
        hc -j monitors | jq -c '[.[] | {name, x, width, ws: .activeWorkspace.name}]' >&2
        e2e_fail "$label: $got"
    }
}

# Every focus event, for the failure output above.
trace_events() {
    run_lua "
local path = '$E2E_ROOT/seat-events.log'
local function log(s) local f = io.open(path, 'a') f:write(s, '\\n') f:close() end
hl.on('monitor.focused', function(m) log('monitor.focused ' .. tostring(m and m.name)) end)
hl.on('workspace.active', function(w) log('workspace.active ' .. tostring(w and w.name)) end)
hl.on('window.active', function(w) log('window.active ' .. tostring(w and w.class)) end)
out({})" >/dev/null
}

e2e_start
if ! hc output create headless HEADLESS-2 >/dev/null 2>&1 ||
    ! wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e 'map(.name) | index(\"HEADLESS-2\")'"; then
    e2e_log "SKIP seat: cannot create a headless output here"
    exit 0
fi
wait_boot_focus_quiet

go_workspace grouped
spawn_test_window e2e-seat
hc dispatch "hl.dsp.focus({ window = 'class:e2e-seat' })" >/dev/null
sleep 0.4
expect "start" '.seat == "WAYLAND-1" and .win == "e2e-seat"'
trace_events

for i in 1 2 3; do
    key "Focus the tile to the right"
    expect "cross #$i onto the empty secondary" '.seat == "HEADLESS-2" and .win == ""'
    key "Focus the tile to the right"
    expect "right again at the outer edge #$i" '.seat == "HEADLESS-2"'
    key "Focus the tile to the left"
    expect "return #$i lands on the window" '.seat == "WAYLAND-1" and .win == "e2e-seat"'
done

# The pointer follows a cross; moving it by itself does not move the seat.
key "Focus the tile to the right"
hc dispatch "hl.dsp.cursor.move({ x = 10, y = 10 })" >/dev/null
sleep 0.4
expect "pointer motion leaves the seat alone" '.seat == "HEADLESS-2" and .pointer == "WAYLAND-1"'
key "Focus the tile to the left"
expect "back to the window" '.seat == "WAYLAND-1" and .win == "e2e-seat"'

# A switch for the secondary stays on the secondary, even for a workspace the
# mode places there but which currently stands on the primary.
hc dispatch "hl.dsp.workspace.move({ workspace = 'name:aside', monitor = 'WAYLAND-1' })" >/dev/null
sleep 0.4
run_lua "require('hypr.lib.desk').switch('HEADLESS-2', 'aside') out({})" >/dev/null
sleep 0.6
on=$(hc -j workspaces | jq -r '.[] | select(.name == "aside") | .monitor')
[[ $on == HEADLESS-2 ]] || e2e_fail "switch left aside on $on"
expect "switch keeps the keyboard on its monitor" '.seat == "HEADLESS-2"'

# A scene the mode places on the primary is refused for the secondary.
run_lua "out({ ok = require('hypr.lib.desk').switch('HEADLESS-2', 'grouped') })" | jq -e '.ok == false' >/dev/null ||
    e2e_fail "a primary scene was switched onto the secondary"

e2e_log "PASS seat"
