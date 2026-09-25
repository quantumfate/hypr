#!/usr/bin/env bash
# Live: the project picker floats (LEO-311). The picker is one more kitty
# window classed `Proj-picker` ("picker" is a valid suffix of
# `config.apps.project.class`'s pattern, conf/base.lua). The `code` scene
# declares one literal `Proj-<name>` group block per project, so
# `Proj-picker` matches none of them — and on a `strays = "float"` scene,
# `hypr/scene/strays.lua` floats any window whose class matches no block:
# the picker arrives floating, outside every project group, with no
# picker-specific rule anywhere. (The retired catch-all `Proj%-.*` block
# grouped it instead; the per-project declaration is the shape this
# scenario models, same as the live seed.)
#
# Focus is not as free: an early version dispatched focus to the chosen
# window and let kitty close the picker window on its own shell exiting,
# trusting that closing a background, already-non-focused window would not
# disturb focus. Verified live instead of assumed — it does disturb it,
# which is exactly why `,proj.sh` now backgrounds
# `reassert_focus_after_picker_closes` to re-assert once the picker's
# window is confirmed gone. This scenario drives the real `,proj.sh pick`
# path (a stubbed `fzf` stands in for the interactive choice) so that fix
# is exercised, not just the raw float.
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

# A stub `fzf` that always "picks" the first line of stdin — deterministic,
# so the picker's own choice never needs a human or a real fuzzy-finder.
cat >"$E2E_ROOT/bin/fzf" <<'SH'
#!/usr/bin/env bash
head -n1
SH
chmod +x "$E2E_ROOT/bin/fzf"

PROJECT_DIR="$E2E_ROOT/picker-repo"
mkdir -p "$PROJECT_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"pickme":{"path":"$PROJECT_DIR","windows":["one","two"],"workspace":"code","kind":"repo","study":false,"priority":0},"pickalt":{"path":"$PROJECT_DIR","windows":["one"],"workspace":"code","kind":"repo","study":false,"priority":0}}}
JSON

# The picker lists only projects that are NOT open (bin/,proj.sh's
# `fzf_pick`), so the project it can actually choose is "pickalt" — "pickme"
# is opened first precisely so the picker has a live group to stay out of.
proj_clients() { clients | jq -c '[.[] | select(.class == "Proj-pickme" or .class == "Proj-picker")]'; }
alt_clients() { clients | jq -c '[.[] | select(.class == "Proj-pickalt")]'; }
picker_clients() { clients | jq -c '[.[] | select(.class == "Proj-picker")]'; }
class_count() { [ "$(proj_clients | jq 'length')" = "$1" ]; }
pickme_tags_match() { [ "$(proj_clients | jq -r '[.[] | select(.class == "Proj-pickme") | .tags[]? | select(startswith("slot:"))] | sort | join(",")')" = "$1" ]; }
focused_is() { [ "$(hc -j activewindow | jq -r '.address')" = "$1" ]; }

,proj.sh open pickme >/dev/null 2>&1
wait_until 100 class_count 2 || e2e_fail "pickme did not spawn its template: $(proj_clients)"
wait_until 100 pickme_tags_match "slot:one,slot:two" || e2e_fail "template windows never got their role tags: $(proj_clients)"
two_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:two") | .address')
one_addr=$(proj_clients | jq -r '.[] | select(.tags[]? == "slot:one") | .address')

# Start on the non-default window ("one" is the template's first, and the
# default `,proj.sh pick` lands on): the picker must land on "one" from here,
# never from a fixture that already names it.
hc dispatch "hl.dsp.focus({ window = \"address:$two_addr\" })" >/dev/null
wait_until 30 focused_is "$two_addr" || e2e_fail "could not focus 'two' to begin from"

# The real, non-inline picker path: no tty, so `pick` hands off to
# `launch_inline`, which spawns a real `Proj-picker` kitty window
# running `,proj.sh pick --inline` — the stubbed `fzf` "chooses" the only
# project in the store immediately.
,proj.sh pick >/dev/null 2>&1
wait_until 100 class_count 3 || e2e_fail "the picker window never appeared: $(proj_clients)"
picker_floated() {
    picker_clients | jq -e '
      . as $w
      | ($w | length) == 1
        and $w[0].floating
        and ($w[0].grouped | length) == 0' >/dev/null
}
wait_until 50 picker_floated || e2e_fail "the picker did not arrive floating, outside every group: $(picker_clients)"
pickme_grouped() {
    proj_clients | jq -e '
      [.[] | select(.class == "Proj-pickme")] as $w
      | ($w | length) == 2
        and ($w | all((.grouped | length) == 2))' >/dev/null
}
wait_until 50 pickme_grouped || e2e_fail "the project's own windows stopped being one group: $(proj_clients)"
e2e_log "PASS: the picker floats on the code workspace, outside the project's group"

# The picker closes itself once its choice is made, and focus must land —
# and stay — on the template's default window ("one"), not bounce back to
# wherever the picker's own close would otherwise send it.
wait_until 60 class_count 2 || e2e_fail "the picker window outlived making its choice: $(proj_clients)"
wait_until 100 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Proj-pickalt\")] | length")" = 1 ]' ||
    e2e_fail "the chosen project never spawned: $(alt_clients)"
alt_addr=$(alt_clients | jq -r '.[0].address')
wait_until 60 focused_is "$alt_addr" || e2e_fail "closing the picker did not leave focus on the chosen window: $(hc -j activewindow)"
e2e_log "PASS: choosing a project in the picker focuses it and the picker's own close does not steal focus back"

# Cancelling is the other half: with every project open the picker's list is
# empty, so it exits without a choice and closes its own window. Focus must
# come back to where the picker was opened from, not be left on nothing --
# a desk with no focused window is deaf to every contextual bind.
hc dispatch "hl.dsp.focus({ window = [[address:$two_addr]] })" >/dev/null
wait_until 30 focused_is "$two_addr" || e2e_fail "could not focus 'two' before cancelling a picker"
,proj.sh pick >/dev/null 2>&1
no_picker() { [ "$(picker_clients | jq 'length')" = 0 ]; }
wait_until 100 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Proj-picker\")] | length")" -ge 1 ]' ||
    e2e_fail "the cancelling picker never appeared"
wait_until 100 no_picker || e2e_fail "the picker with nothing to offer never closed: $(picker_clients)"
wait_until 60 focused_is "$two_addr" || e2e_fail "a cancelled picker left focus nowhere: $(hc -j activewindow)"
e2e_log "PASS: a picker that ends without a choice gives focus back to where it came from"
