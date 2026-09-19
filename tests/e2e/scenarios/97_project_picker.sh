#!/usr/bin/env bash
# Live: the project picker's group behaviour (LEO-311). The picker is one
# more `Proj-<name>`-classed kitty window ("picker" is a valid suffix of
# `config.apps.project.class`'s pattern, conf/base.lua), so it needs no
# picker-specific grouping code at all: `hypr/scene/grouping.lua`'s runtime
# join decision matches on the `code` scene's group BLOCK
# ("Kitty-Main"/"Proj-*"), not on literal class equality, so it folds into
# whichever group already holds the focused project's windows the same way
# a declared scope does (96_project_scope.sh).
#
# Unpin is not quite as free: an early version dispatched focus to the
# chosen window and let kitty close the picker window on its own shell
# exiting, trusting that closing a background, already-non-focused group
# member would not disturb focus. Verified live instead of assumed — it
# does disturb it, which is exactly why `,proj.sh` now backgrounds
# `reassert_focus_after_picker_closes` to re-assert once the picker's
# window is confirmed gone. This scenario drives the real `,proj.sh pick`
# path (a stubbed `fzf` stands in for the interactive choice) so that fix is
# exercised, not just the raw grouping mechanics.
. "$(dirname "$0")/../lib.sh"

if ! command -v kitty >/dev/null 2>&1; then
    e2e_log "SKIP: kitty not installed"
    exit 0
fi

e2e_start

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
{"projects":{"pickme":{"path":"$PROJECT_DIR","windows":["one","two"],"workspace":"code","kind":"repo","study":false,"priority":0}}}
JSON

proj_clients() { clients | jq -c '[.[] | select(.class == "Proj-pickme" or .class == "Proj-picker")]'; }
class_count() { [ "$(proj_clients | jq 'length')" = "$1" ]; }
pickme_tags_match() { [ "$(proj_clients | jq -r '[.[] | select(.class == "Proj-pickme") | .tags[]?] | sort | join(",")')" = "$1" ]; }
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
# `launch_inline_picker`, which spawns a real `Proj-picker` kitty window
# running `,proj.sh pick --inline` — the stubbed `fzf` "chooses" the only
# project in the store immediately.
,proj.sh pick >/dev/null 2>&1
wait_until 100 class_count 3 || e2e_fail "the picker window never appeared: $(proj_clients)"
one_group() {
    proj_clients | jq -e '
      . as $w
      | ($w | length) == 3
        and ($w | all((.grouped | length) == 3))' >/dev/null
}
wait_until 50 one_group || e2e_fail "the picker did not join pickme's existing group: $(proj_clients)"
e2e_log "PASS: the picker joins the focused project's group on arrival, unassisted"

# The picker closes itself once its choice is made, and focus must land — and
# stay — on the template's default window ("one"), not bounce back to
# wherever the picker's own close would otherwise send it.
wait_until 60 class_count 2 || e2e_fail "the picker window outlived making its choice: $(proj_clients)"
wait_until 60 focused_is "$one_addr" || e2e_fail "closing the picker did not leave focus on the chosen window: $(hc -j activewindow)"
e2e_log "PASS: choosing a project in the picker focuses it and the picker's own close does not steal focus back"
