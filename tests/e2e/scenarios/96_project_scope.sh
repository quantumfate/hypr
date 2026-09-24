#!/usr/bin/env bash
# Live: LEO-311 chunk D's context-aware project bindings. `hypr/lib/project.lua`
# resolves "the active project's nvim/run window" from the FOCUSED window's
# class/tags, never a hardcoded name; `,proj.sh scope` spawns a declared
# scope with the project's own command and it joins the group by class —
# same as `95_project_group.sh` but exercising the bindings chunk, not `open`.
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

PROJECT_DIR="$E2E_ROOT/scope-repo"
mkdir -p "$PROJECT_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"scoped":{"path":"$PROJECT_DIR","windows":["nvim","zsh","run"],"workspace":"code","kind":"repo","study":false,"priority":0,"scopes":{"test":"echo scope-ran; sleep 300"}}}}
JSON

proj_clients() { clients | jq -c '[.[] | select(.class == "Proj-scoped")]'; }
class_count() { [ "$(proj_clients | jq 'length')" = "$1" ]; }
slot_tags_match() { [ "$(proj_clients | jq -r '[.[].tags[]? | select(startswith("slot:"))] | sort | join(",")')" = "$1" ]; }

,proj.sh open scoped >/dev/null 2>&1
wait_until 100 class_count 3 || e2e_fail "scoped project did not spawn its template: $(proj_clients)"
wait_until 100 slot_tags_match "slot:nvim,slot:run,slot:zsh" || e2e_fail "template windows never got their role tags: $(proj_clients)"
e2e_log "PASS: open spawns the declared-scope project's plain template"

# Resolution: hypr/lib/project.lua reads whichever window is focused right
# now — no scenario fixture ever names "scoped" to it.
nvim_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:nvim") | .address')
zsh_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:zsh") | .address')
hc dispatch "hl.dsp.focus({ window = \"address:$zsh_addr\" })" >/dev/null
RESULT_FILE="$E2E_ROOT/project-resolve.json"
rm -f "$RESULT_FILE"
hc eval "
package.path = package.path .. \";$E2E_REPO/?.lua\"
local project = require(\"hypr.lib.project\")
local w = hl.get_active_window()
local class = project.focused_class(w)
local addr = project.slot_address(hl.get_windows() or {}, class, \"nvim\")
local f = assert(io.open(\"$RESULT_FILE\", \"w\"))
f:write(addr or \"\")
f:close()
" >/dev/null
wait_until 30 test -f "$RESULT_FILE" || e2e_fail "the Lua resolution snippet never ran"
resolved=$(cat "$RESULT_FILE")
assert_eq "$resolved" "$nvim_addr" "project.slot_address resolves the focused project's nvim window dynamically"
e2e_log "PASS: focus-nvim resolution matches the live nvim-tagged window"

# Scope spawn: a declared scope spawns with the project's own command and
# joins the existing group (same class => same scene-grouped column).
hc dispatch "hl.dsp.focus({ window = \"address:$zsh_addr\" })" >/dev/null
,proj.sh scope test >/dev/null 2>&1
wait_until 100 class_count 4 || e2e_fail "declared scope never spawned: $(proj_clients)"
wait_until 100 slot_tags_match "slot:nvim,slot:run,slot:test,slot:zsh" || e2e_fail "scope window never got its role tag: $(proj_clients)"
one_group() {
    proj_clients | jq -e '
      . as $w
      | ($w | length) == 4
        and ($w | all((.grouped | length) == 4))' >/dev/null
}
wait_until 50 one_group || e2e_fail "the scope window did not join the project's group: $(proj_clients)"
e2e_log "PASS: a declared scope spawns with its own command and joins the group"

# Re-invoking the same scope focuses the live one instead of spawning again.
,proj.sh scope test >/dev/null 2>&1
sleep 0.3
class_count 4 || e2e_fail "re-invoking a live scope spawned a duplicate: $(proj_clients)"
test_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:test") | .address')
focused_is() { [ "$(hc -j activewindow | jq -r '.address')" = "$1" ]; }
wait_until 50 focused_is "$test_addr" || e2e_fail "re-invoking a live scope did not focus it"
e2e_log "PASS: re-invoking a live scope focuses it instead of respawning"
