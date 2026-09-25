#!/usr/bin/env bash
# Live: a project opened onto a DECK scene (the shape the real `code` scene
# has: one group block per project, every project class in one `flip`
# column). 95_project_group.sh covers the plain-tiled scene; this is the one
# the desk actually runs, where the deck parks what its column does not show
# while the template is still spawning.
. "$(dirname "$0")/../lib.sh"

if ! command -v kitty >/dev/null 2>&1; then
    e2e_log "SKIP: kitty not installed"
    exit 0
fi

e2e_start
wait_boot_focus_quiet
go_workspace code-deck

# An ad-hoc terminal on the project column FIRST, so the strip is already
# showing something else when the project opens. This is the live shape (a
# `Kitty-Main` shares the code column with the projects), and the case that
# breaks: the project's whole thing is parked from the moment it opens, and
# it must still form its group down there rather than wait for a turn on
# screen it never gets.
spawn_test_window e2e-deck-term

PROJECT_DIR="$E2E_ROOT/deck-repo"
mkdir -p "$PROJECT_DIR"
cat >"$QF_STORE/projects.json" <<JSON
{"projects":{"deckdemo":{"path":"$PROJECT_DIR","windows":["nvim","yazi","zsh","run"],"workspace":"code-deck","kind":"repo","study":false,"priority":0},"deckalt":{"path":"$PROJECT_DIR","windows":["nvim","yazi","zsh","run"],"workspace":"code-deck","kind":"repo","study":false,"priority":0}}}
JSON

demo_clients() { clients | jq -c '[.[] | select(.class == "Proj-deckdemo")]'; }
class_count() { [ "$(demo_clients | jq 'length')" = "$1" ]; }
one_group() {
    demo_clients | jq -e '
      . as $w
      | ($w | length) == 4
        and ($w | all((.grouped | length) == 4))' >/dev/null
}

,proj.sh open deckdemo >/dev/null 2>&1
wait_until 200 class_count 4 || e2e_fail "deckdemo did not spawn its template: $(demo_clients)"
wait_until 100 one_group || e2e_fail "the project's windows are not one group on a deck: $(demo_clients | jq -c 'map({class,ws:.workspace.name,grouped:(.grouped|length),tags})')"
e2e_log "PASS: a project opened on a deck scene is one group"

# One thing on the strip, so nothing of this project is parked: a group is
# one thing, and its members travel together.
held() { demo_clients | jq '[.[] | select(.workspace.name | startswith("special:"))] | length'; }
[ "$(held)" = 0 ] || e2e_fail "members of the project's own group were parked apart: $(demo_clients | jq -c 'map({ws:.workspace.name})')"
e2e_log "PASS: the project's group stands on the deck column as one thing"

# A second project opened while the first already stands on the column: the
# live gesture. Each project is its own group of four, and the column shows
# one of them with the other parked whole -- never a project split into
# separate tabs on the strip.
alt_clients() { clients | jq -c '[.[] | select(.class == "Proj-deckalt")]'; }
alt_count() { [ "$(alt_clients | jq 'length')" = "$1" ]; }
alt_one_group() {
    alt_clients | jq -e '
      . as $w
      | ($w | length) == 4
        and ($w | all((.grouped | length) == 4))' >/dev/null
}
,proj.sh open deckalt >/dev/null 2>&1
wait_until 200 alt_count 4 || e2e_fail "deckalt did not spawn its template: $(alt_clients)"
wait_until 100 alt_one_group || e2e_fail "the second project is not one group: $(alt_clients | jq -c 'map({ws:.workspace.name,grouped:(.grouped|length),tags})')"
one_group || e2e_fail "the first project stopped being one group once a second opened: $(demo_clients | jq -c 'map({ws:.workspace.name,grouped:(.grouped|length)})')"
whole() { # $1 = jq class filter output -- every member on one workspace
    printf '%s' "$1" | jq -e '[.[].workspace.name] | unique | length == 1' >/dev/null
}
whole "$(demo_clients)" || e2e_fail "the first project was split across workspaces: $(demo_clients | jq -c 'map({ws:.workspace.name})')"
whole "$(alt_clients)" || e2e_fail "the second project was split across workspaces: $(alt_clients | jq -c 'map({ws:.workspace.name})')"
e2e_log "PASS: two projects on one deck column are two whole groups"

# Exactly one project is SHOWN, and it is the one just opened, with focus on
# one of its members: opening a project puts it in front of you. Everything
# else on the column is parked whole. (The live symptom this pins: every
# project window ended up on the hold and focus sat on the browser beside
# it.)
shown_classes() { clients | jq -r '[.[] | select(.class | startswith("Proj-")) | select(.workspace.name == "code-deck") | .class] | unique | join(",")'; }
focused_class() { hc -j activewindow | jq -r '.class // "none"'; }
wait_until 100 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq -r "[.[] | select(.class | startswith(\"Proj-\")) | select(.workspace.name == \"code-deck\") | .class] | unique | length")" = 1 ]' ||
    e2e_fail "expected exactly one project shown on the column, saw: $(shown_classes)"
[ "$(shown_classes)" = "Proj-deckalt" ] || e2e_fail "the project just opened is not the one shown: $(shown_classes)"
wait_until 60 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j activewindow | jq -r ".class // \"none\"")" = "Proj-deckalt" ]' ||
    e2e_fail "focus did not land on the project just opened, it sits on: $(focused_class)"
e2e_log "PASS: opening a project shows it and focuses it"

# Placement never moves focus (docs/declared-groups.md rule 3): a window
# arriving into a thing the strip is NOT showing makes the deck park and
# re-place, and none of that may take the keyboard off what the user is
# typing in. Quickshell anchors its overlays to `Hyprland.focusedMonitor`,
# so a focus dance here is a which-key overlay on the wrong screen.
browser_addr=$(clients | jq -r '[.[] | select(.class == "e2e-browser")] | first | .address // empty') || true
if [ -z "$browser_addr" ]; then
    spawn_test_window e2e-browser
    browser_addr=$(clients | jq -r '[.[] | select(.class == "e2e-browser")] | first | .address')
fi
hc dispatch "hl.dsp.focus({ window = [[address:$browser_addr]] })" >/dev/null
wait_until 30 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j activewindow | jq -r ".address // empty")" = "'"$browser_addr"'" ]' ||
    e2e_fail "could not focus the browser column to type in"

# A late member arriving into a thing the strip is NOT showing -- spawned
# directly, so this is a window opening, never a user gesture asking to be
# taken anywhere (`,proj.sh open` is that gesture, and it SHOULD move focus).
WAYLAND_DISPLAY=$E2E_WAYLAND setsid kitty --class Proj-deckdemo -e sh -c "sleep 600" >/dev/null 2>&1 &
wait_until 150 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Proj-deckdemo\")] | length")" -ge 5 ]' ||
    e2e_fail "the late project window never mapped"
sleep 1
[ "$(hc -j activewindow | jq -r '.address // empty')" = "$browser_addr" ] ||
    e2e_fail "placement moved focus off the window being typed in: $(hc -j activewindow | jq -c '{address,class}')"
e2e_log "PASS: parking and re-placing a thing leaves focus where the user put it"

# A floating prompt keeps the keyboard. The project picker floats as a stray
# on a deck scene, and the deck's own focus rescue used to count "the focused
# window is not one of the boxes I placed" as "nothing is focused" -- so it
# took focus off the picker and you could not type into it.
spawn_test_window e2e-prompt
prompt_addr=$(client_of e2e-prompt | jq -r '.address')
hc dispatch "hl.dsp.window.float({ window = [[address:$prompt_addr]] })" >/dev/null
hc dispatch "hl.dsp.focus({ window = [[address:$prompt_addr]] })" >/dev/null
wait_until 30 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j activewindow | jq -r ".address // empty")" = "'"$prompt_addr"'" ]' ||
    e2e_fail "could not focus the floating prompt"

# Make the deck work while it is focused: bring another project forward,
# which is exactly the pass that used to steal the keyboard.
hc eval "package.path = package.path .. \";$E2E_REPO/?.lua\"
require('hypr.scene.deck_provider').reconcile('code-deck')" >/dev/null
sleep 0.6
[ "$(hc -j activewindow | jq -r '.address // empty')" = "$prompt_addr" ] ||
    e2e_fail "the deck stole focus from a floating prompt: $(hc -j activewindow | jq -c '{class,address}')"
e2e_log "PASS: a floating prompt keeps focus through a deck pass"

# The scene's isles actually dock. A deck anchors them to COLUMNS, and the
# dock grammar has to accept that target: it did not, so every dock on a
# deck scene was dropped at parse time and the screen published an empty map
# — no isle docked anywhere, and the opt-in project strip vanished entirely
# (live, 2026-09-24).
docks_json() { jq -c '.docks // {}' "$QF_STORE/geometry.json" 2>/dev/null || echo '{}'; }
wait_until 100 sh -c '[ "$(jq -r "[.docks // {} | .[] | keys[]] | unique | length" "$QF_STORE/geometry.json" 2>/dev/null)" -ge 4 ]' ||
    e2e_fail "the deck scene published no docks: $(docks_json)"
docks_json | jq -e '[.[] | to_entries[] | select(.value.state == "docked") | .key] | index("bar.projects")' >/dev/null ||
    e2e_fail "the project strip did not dock over its column: $(docks_json)"
e2e_log "PASS: a deck scene docks its isles onto its columns"

# And nothing was dropped on the way in: a dropped dock is reported, never
# silent, so the scenario fails on the report rather than on its symptom.
! grep -aq "dock_dropped" "$E2E_STUB_LOG" 2>/dev/null ||
    e2e_fail "the scene declared a dock the grammar refused: $(grep -a dock_dropped "$E2E_STUB_LOG" | tail -3)"
e2e_log "PASS: every declared dock parsed"

# Closing one member of a group on a deck: the compositor survives, and the
# window left behind stays TILED. The live symptom this pins is a window
# snapping out of the tiling into floating and covering the screen after a
# close — a group dropping to its last member destroys the group, and that
# re-assigns the survivor's space mid-pass.
survivor_class="Proj-deckalt"
victim=$(clients | jq -r --arg c "$survivor_class" '[.[] | select(.class == $c)] | .[0].address // empty')
[ -n "$victim" ] || e2e_fail "no member of $survivor_class to close"
hc dispatch "hl.dsp.window.close({ window = [[address:$victim]] })" >/dev/null
sleep 1.5
hc -j clients >/dev/null 2>&1 || e2e_fail "the compositor died closing a group member"
clients | jq -e --arg c "$survivor_class" '[.[] | select(.class == $c)] | length >= 1 and all(.floating == false)' >/dev/null ||
    e2e_fail "a survivor fell out of the tiling: $(clients | jq -c --arg c "$survivor_class" '[.[] | select(.class == $c) | {floating, ws: .workspace.name}]')"
e2e_log "PASS: closing a group member leaves the rest tiled, and the session up"
