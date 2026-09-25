#!/usr/bin/env bash
# Live: `,proj.sh` reads the store and turns a project into
# real kitty windows the compositor groups by class — no stub, no eval.
. "$(dirname "$0")/../lib.sh"

if ! command -v kitty >/dev/null 2>&1; then
    e2e_log "SKIP: kitty not installed"
    exit 0
fi

e2e_start
# The boot's main landing re-checks steal focus for a few seconds after the
# settle (lib.sh's wait_boot_focus_quiet); project work that asserts focus
# must not race them.
wait_boot_focus_quiet

# A store with one project, no filesystem scan involved: `,proj.sh open`
# reads this directly. Plain shell roles only (no "nvim") — this scenario is
# about grouping, not the nvim graceful-quit path (that's proj_pick_test.sh).
PROJECT_DIR="$E2E_ROOT/demo-repo"
mkdir -p "$PROJECT_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"demo":{"path":"$PROJECT_DIR","windows":["one","two"],"workspace":"code","kind":"repo","study":false,"priority":0}}}
JSON

demo_clients() { clients | jq -c '[.[] | select(.class == "Proj-demo")]'; }
class_count() { [ "$(demo_clients | jq 'length')" = "$1" ]; }
slot_tags_match() { [ "$(demo_clients | jq -r '[.[].tags[]? | select(startswith("slot:"))] | sort | join(",")')" = "$1" ]; }
one_group() {
    demo_clients | jq -e '
      . as $w
      | ($w | length) == 2
        and ($w | all((.grouped | length) == 2))
        and ($w[0].grouped | sort) == ($w[1].grouped | sort)' >/dev/null
}
focused_is() { [ "$(hc -j activewindow | jq -r '.address')" = "$1" ]; }

,proj.sh open demo >/dev/null 2>&1
wait_until 100 class_count 2 || e2e_fail "demo did not spawn two windows: $(demo_clients)"
wait_until 100 slot_tags_match "slot:one,slot:two" || e2e_fail "windows never got their role tags: $(demo_clients)"
wait_until 50 one_group || e2e_fail "demo's two windows are not one group: $(demo_clients)"
assert_eq "$(demo_clients | jq -r '.[0].workspace.name')" "code" "project windows land on the code workspace"
e2e_log "PASS: open spawns the whole template, grouped, on code"

# Reopening: nothing new spawns, the requested window takes focus.
,proj.sh open demo two >/dev/null 2>&1
sleep 0.3
class_count 2 || e2e_fail "reopening an already-open project spawned something new: $(demo_clients)"
two_addr=$(demo_clients | jq -r '.[] | select(.tags[]? == "slot:two") | .address')
wait_until 30 focused_is "$two_addr" || e2e_fail "the requested window never took focus"
e2e_log "PASS: reopen refocuses instead of respawning"

# One window gone: reopening spawns only the missing one.
one_addr=$(demo_clients | jq -r '.[] | select(.tags[]? == "slot:one") | .address')
hc dispatch "hl.dsp.window.close({ window = \"address:$one_addr\" })" >/dev/null
wait_until 50 class_count 1 || e2e_fail "closing one window did not leave exactly one: $(demo_clients)"
,proj.sh open demo >/dev/null 2>&1
wait_until 100 class_count 2 || e2e_fail "reopening with one window missing did not bring it back: $(demo_clients)"
e2e_log "PASS: reopen with one window missing spawns only that one"

# Closing the last window dissolves the group: nothing project-classed left.
# Retried, address list recomputed each pass: a window closed moments after
# spawning (the "missing one" above just came back) can miss its first close
# request before the compositor has settled it. The TABLE form is required —
# `hl.dsp.window.close("address:...")` ignores the string and closes the
# focused window instead (verified in the Lua plugin source: a bare-string
# arg makes the window upval nil, and a nil selector falls back to focus).
close_all_demo() {
    local a
    for a in $(demo_clients | jq -r '.[].address'); do
        hc dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
    done
    class_count 0
}
wait_until 50 close_all_demo || e2e_fail "the project's windows outlived closing all of them: $(demo_clients)"
e2e_log "PASS: closing the last window ends the project"

# Template order, not arrival order: a project declared run-before-zsh still
# sits zsh, run in the physical group (hypr/lib/project.lua's TEMPLATE_ROLES),
# and the recorded order mod+j/k walks mirrors that group rather than the
# order the kitty windows happened to map in.
ORDER_DIR="$E2E_ROOT/order-repo"
mkdir -p "$ORDER_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"ordered":{"path":"$ORDER_DIR","windows":["run","zsh"],"workspace":"code","kind":"repo","study":false,"priority":0}}}
JSON

ordered_clients() { clients | jq -c '[.[] | select(.class == "Proj-ordered")]'; }
ordered_count() { [ "$(ordered_clients | jq 'length')" = "$1" ]; }
ordered_tags() { [ "$(ordered_clients | jq -r '[.[].tags[]? | select(startswith("slot:"))] | sort | join(",")')" = "$1" ]; }

,proj.sh open ordered >/dev/null 2>&1
wait_until 100 ordered_count 2 || e2e_fail "ordered did not spawn its template: $(ordered_clients)"
wait_until 100 ordered_tags "slot:run,slot:zsh" || e2e_fail "ordered's windows never got their role tags: $(ordered_clients)"

zsh_a=$(ordered_clients | jq -r '.[] | select(.tags[]? | startswith("slot:zsh")) | .address')
run_a=$(ordered_clients | jq -r '.[] | select(.tags[]? | startswith("slot:run")) | .address')
template_group_order() {
    [ "$(ordered_clients | jq -r '.[0].grouped | join(",")')" = "$zsh_a,$run_a" ]
}
wait_until 50 template_group_order ||
    e2e_fail "the group's physical order is not the template order (expected $zsh_a,$run_a): $(ordered_clients)"
e2e_log "PASS: a project group sits in template order, not arrival order"

# The walk order mod+j/k uses (hypr/binds.lua's focus_in_group) reads the
# adapter over the live group: it must agree with the groupbar above.
ADAPTER_FILE="$E2E_ROOT/ordered-adapter.txt"
command rm -f -- "$ADAPTER_FILE"
hc eval "
package.path = package.path .. \";$E2E_REPO/?.lua\"
local group_adapters = require('hypr.scene.group_adapters')
local grouping = require('hypr.scene.grouping')
local w = hl.get_window('address:$zsh_a')
local order = group_adapters.for_class(w.class).order(group_adapters.normalize_members(w.group), { group_key = grouping.group_key(w) })
local f = assert(io.open(\"$ADAPTER_FILE\", 'w'))
f:write(table.concat(order, ','))
f:close()
" >/dev/null
wait_until 30 test -f "$ADAPTER_FILE" || e2e_fail "the adapter-order snippet never ran"
assert_eq "$(cat "$ADAPTER_FILE")" "$zsh_a,$run_a" "mod+j/k walks the same order the groupbar shows"

close_all_ordered() {
    local a
    for a in $(ordered_clients | jq -r '.[].address'); do
        hc dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
    done
    ordered_count 0
}
wait_until 50 close_all_ordered || e2e_fail "the ordered project's windows outlived closing them: $(ordered_clients)"
