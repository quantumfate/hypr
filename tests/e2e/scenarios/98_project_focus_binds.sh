#!/usr/bin/env bash
# Live: the `n`/`r` project binds (SUPER+Space p n / p r), end to end. Not
# `hq key` (AGENTS.md: that cannot fire a Lua bind closure) — this runs the
# same resolution `hypr/binds.lua`'s closures call
# (`hypr/lib/project.lua`'s `focused_class`/`slot_address`) via `hc eval`,
# starting from a non-nvim, non-run window focused, so the fixture never
# names the project to it.
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

PROJECT_DIR="$E2E_ROOT/focus-repo"
mkdir -p "$PROJECT_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"focustest":{"path":"$PROJECT_DIR","windows":["nvim","zsh","run"],"workspace":"code","kind":"repo","study":false,"priority":0}}}
JSON

proj_clients() { clients | jq -c '[.[] | select(.class == "Proj-focustest")]'; }
class_count() { [ "$(proj_clients | jq 'length')" = "$1" ]; }
slot_tags_match() { [ "$(proj_clients | jq -r '[.[].tags[]? | select(startswith("slot:"))] | sort | join(",")')" = "$1" ]; }
focused_is() { [ "$(hc -j activewindow | jq -r '.address')" = "$1" ]; }

,proj.sh open focustest >/dev/null 2>&1
wait_until 100 class_count 3 || e2e_fail "focustest did not spawn its template: $(proj_clients)"
# The addresses below are read via slot tags; `stamp_slot` lands each tag a
# beat after its window maps, so wait for all three before reading.
wait_until 100 slot_tags_match "slot:nvim,slot:run,slot:zsh" || e2e_fail "focustest windows never got their role tags: $(proj_clients)"

nvim_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:nvim") | .address')
run_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:run") | .address')
zsh_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:zsh") | .address')

# Start on the plain shell — the non-nvim, non-run member.
hc dispatch "hl.dsp.focus({ window = \"address:$zsh_addr\" })" >/dev/null
wait_until 30 focused_is "$zsh_addr" || e2e_fail "could not focus the zsh member to begin from"

resolve_and_focus() { # $1 = role
    RESULT_FILE="$E2E_ROOT/resolve-$1.txt"
    rm -f "$RESULT_FILE"
    hc eval "
package.path = package.path .. \";$E2E_REPO/?.lua\"
local project = require(\"hypr.lib.project\")
local w = hl.get_active_window()
local class = project.focused_class(w)
local addr = class and project.slot_address(hl.get_windows() or {}, class, \"$1\")
if addr then
  hl.dispatch(hl.dsp.focus({ window = \"address:\" .. addr }))
end
local f = assert(io.open(\"$RESULT_FILE\", \"w\"))
f:write(addr or \"\")
f:close()
" >/dev/null
    wait_until 30 test -f "$RESULT_FILE" || e2e_fail "the $1-bind resolution snippet never ran"
    cat "$RESULT_FILE"
}

resolved_nvim=$(resolve_and_focus nvim)
assert_eq "$resolved_nvim" "$nvim_addr" "the n bind resolves the focused project's real nvim window"
wait_until 30 focused_is "$nvim_addr" || e2e_fail "the n bind's dispatch never landed focus on nvim"
e2e_log "PASS: n focuses the active project's nvim window from a non-nvim start"

# r, now starting from nvim (whichever member is focused, never a fixture name).
resolved_run=$(resolve_and_focus run)
assert_eq "$resolved_run" "$run_addr" "the r bind resolves the focused project's real run window"
wait_until 30 focused_is "$run_addr" || e2e_fail "the r bind's dispatch never landed focus on run"
e2e_log "PASS: r focuses the active project's run window from a non-run start"
