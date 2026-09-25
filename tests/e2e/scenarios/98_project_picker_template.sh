#!/usr/bin/env bash
# Live: the PICKER path, opening a project with a FULL template.
#
# The path every other project scenario skips. `,proj.sh open` backgrounds
# `spawn_missing`, and when the caller is the picker that backgrounded job is
# a child of the picker's own kitty window -- which closes the instant `pick`
# returns. A template of four windows therefore has to outlive its parent's
# window, which is the same rule `_reassert-focus` already learned the hard
# way. A shell-launched `,proj.sh open` never shows it: that caller stays
# alive, so the template completes.
. "$(dirname "$0")/../lib.sh"

if ! command -v kitty >/dev/null 2>&1; then
    e2e_log "SKIP: kitty not installed"
    exit 0
fi

e2e_start
wait_boot_focus_quiet
go_workspace code-deck

# A stub fzf that always picks the first line, same as 97_project_picker.sh.
cat >"$E2E_ROOT/bin/fzf" <<'SH'
#!/usr/bin/env bash
head -n1
SH
chmod +x "$E2E_ROOT/bin/fzf"

PROJECT_DIR="$E2E_ROOT/template-repo"
mkdir -p "$PROJECT_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"deckdemo":{"path":"$PROJECT_DIR","windows":["nvim","yazi","zsh","run"],"workspace":"code-deck","kind":"repo","study":false,"priority":0}}}
JSON

demo_clients() { clients | jq -c '[.[] | select(.class == "Proj-deckdemo")]'; }
demo_count() { demo_clients | jq 'length'; }
slot_tags() { demo_clients | jq -r '[.[].tags[]? | select(startswith("slot:"))] | sort | join(",")'; }

,proj.sh pick >/dev/null 2>&1 || true
wait_until 250 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Proj-deckdemo\")] | length")" = 4 ]' ||
    e2e_fail "the picker opened $(demo_count)/4 template windows: $(demo_clients | jq -c 'map({tags})')"
e2e_log "PASS: the picker opens the whole template, not the part its own window outlived"

wait_until 150 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq -r "[.[] | select(.class == \"Proj-deckdemo\") | .tags[]? | select(startswith(\"slot:\"))] | sort | join(\",\")")" = "slot:nvim,slot:run,slot:yazi,slot:zsh" ]' ||
    e2e_fail "the template's windows never all got their role tags: $(slot_tags)"
e2e_log "PASS: every template window carries its role"

one_group() {
    demo_clients | jq -e '. as $w | ($w | length) == 4 and ($w | all((.grouped | length) == 4))' >/dev/null
}
wait_until 150 one_group || e2e_fail "the picker-opened project is not one group: $(demo_clients | jq -c 'map({ws:.workspace.name,grouped:(.grouped|length)})')"
e2e_log "PASS: a picker-opened project is one whole group"

# Direction (user decision, 2026-09-24): `mod+j` walks UP the declared order,
# toward the first tab, and `mod+k` walks down it. This drives the exact body
# `hypr/binds.lua` binds to those keys (`hq key` cannot fire a Lua bind
# closure -- see 60_navigation.sh's header), so the direction is pinned by
# the same call the keyboard makes.
step_in_group() { # $1 = next|prev
    local result="$E2E_ROOT/step.txt"
    command rm -f -- "$result"
    hc eval "
package.path = package.path .. \";$E2E_REPO/?.lua\"
local group_adapters = require('hypr.scene.group_adapters')
local grouping = require('hypr.scene.grouping')
local w = hl.get_active_window()
local order = group_adapters.for_class(w.class).order(
  group_adapters.normalize_members(w.group), { group_key = grouping.group_key(w) })
local index
for i, a in ipairs(order) do if a == w.address then index = i end end
local step = '$1' == 'next' and -1 or 1
local target = order[((index - 1 + step) % #order) + 1]
hl.dispatch(hl.dsp.focus({ window = 'address:' .. target }))
local live = hl.get_window('address:' .. target)
local slot = '?'
for _, t in ipairs((live and live.tags) or {}) do local r = t:match('^slot:([^*]+)') if r then slot = r end end
local f = assert(io.open(\"$result\", 'w')) f:write(slot) f:close()
" >/dev/null
    wait_until 30 test -f "$result" || e2e_fail "the $1 snippet never ran"
    cat "$result"
}

zsh_addr=$(demo_clients | jq -r '.[] | select(.tags[]? | startswith("slot:zsh")) | .address')
# Through `present`, not a bare focus dispatch: on a deck the tab may be
# parked, and focusing a parked window does nothing at all (docs/
# declared-groups.md rule 4). This is the same call `,proj.sh` makes.
hc eval "package.path = package.path .. \";$E2E_REPO/?.lua\"
require('hypr.scene.deck_provider').present('$zsh_addr')" >/dev/null
wait_until 30 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j activewindow | jq -r ".address // empty")" = "'"$zsh_addr"'" ]' ||
    e2e_fail "could not focus the zsh tab to step from"
assert_eq "$(step_in_group next)" "yazi" "mod+j from zsh walks up the declared order"
assert_eq "$(step_in_group prev)" "zsh" "mod+k walks back down it"
e2e_log "PASS: mod+j walks up the declared order, mod+k down"

# The picker opening BESIDE a live project group must not disturb it. The
# prompt wears the project class prefix, so `auto_group` can swallow it into
# the neighbouring group — and the executor's answer to a foreigner in a
# block's group is to eject it, an `HL.Group:remove` that re-assigns the
# window's space. That made "open a second project" a reliable way to break
# the formation (live, 2026-09-24). The prompt is `group = "barred"` now, so
# the swallow never happens and no eject is ever needed.
group_size() { demo_clients | jq -r '[.[].grouped | length] | max // 0'; }
BEFORE_SIZE=$(group_size)
[ "$BEFORE_SIZE" = "4" ] || e2e_fail "expected the project group of four before the picker: $BEFORE_SIZE"

,proj.sh pick >/dev/null 2>&1 || true
wait_until 200 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Proj-picker\")] | length")" -ge 1 ]' ||
    e2e_fail "the picker never appeared"
picker_json() { clients | jq -c '[.[] | select(.class == "Proj-picker")]'; }
picker_json | jq -e 'all((.grouped | length) == 0)' >/dev/null ||
    e2e_fail "the picker was swallowed into a group: $(picker_json | jq -c 'map({grouped: (.grouped|length)})')"
[ "$(group_size)" = "4" ] ||
    e2e_fail "the project group changed size while the picker was up: $BEFORE_SIZE -> $(group_size)"
e2e_log "PASS: a picker opens beside a group without joining or breaking it"
