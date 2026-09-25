#!/usr/bin/env bash
# Live: a log group (docs/logs.md) is a declared group like a project is —
# `,logs.sh open` spawns one kitty per declared source, they fold into ONE
# Hyprland group by class, and the `logs` deck column shows them as one thing.
#
# The scene used to declare `blocks: []`, so every window landing on `logs`
# matched nothing and the stray rule floated it — including the viewer, whose
# own rule asks for `float = false` and lost. That is what "the logs workspace
# does not work" meant.
. "$(dirname "$0")/../lib.sh"

if ! command -v kitty >/dev/null 2>&1; then
    e2e_log "SKIP: kitty not installed"
    exit 0
fi

e2e_start
wait_boot_focus_quiet
go_workspace logs

REPO="$E2E_ROOT/log-repo"
mkdir -p "$REPO"
cat >"$REPO/logs.toml" <<'TOML'
[sources]
build = "sleep 600"
unit = "sleep 600"
TOML

,logs.sh add demo "$REPO" >/dev/null || e2e_fail ",logs.sh add refused a repo carrying a logs.toml"
[ "$(,logs.sh list | head -1)" = "$(printf 'demo\tbuild,unit')" ] ||
    e2e_fail "the catalogue did not fold the declared sources: $(,logs.sh list)"
e2e_log "PASS: a repo's logs.toml folds into the catalogue"

demo_clients() { clients | jq -c '[.[] | select(.class == "Log-demo")]'; }
slot_tags() { demo_clients | jq -r '[.[].tags[]? | select(startswith("slot:"))] | sort | join(",")'; }

,logs.sh open demo >/dev/null 2>&1 || true
wait_until 200 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Log-demo\")] | length")" = 2 ]' ||
    e2e_fail "the log group did not spawn one window per source: $(demo_clients)"
wait_until 150 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq -r "[.[] | select(.class == \"Log-demo\") | .tags[]? | select(startswith(\"slot:\"))] | sort | join(\",\")")" = "slot:build,slot:unit" ]' ||
    e2e_fail "the sources never got their role tags: $(slot_tags)"
e2e_log "PASS: one window per declared source, each carrying its role"

one_group() {
    demo_clients | jq -e '. as $w | ($w | length) == 2 and ($w | all((.grouped | length) == 2))' >/dev/null
}
wait_until 150 one_group || e2e_fail "the log group's windows are not one group: $(demo_clients | jq -c 'map({ws:.workspace.name,grouped:(.grouped|length)})')"
e2e_log "PASS: a log group is one Hyprland group"

# Tiled, not floating — the defect the empty block list caused.
demo_clients | jq -e 'all(.floating == false)' >/dev/null ||
    e2e_fail "log windows floated instead of tiling: $(demo_clients | jq -c 'map({floating})')"
e2e_log "PASS: log windows tile on the logs scene"

# The group ends with its last window (docs/logs.md lifecycle).
,logs.sh kill demo >/dev/null 2>&1 || true
wait_until 100 sh -c '[ "$(hyprctl -i "$E2E_SIG" -j clients | jq "[.[] | select(.class == \"Log-demo\")] | length")" = 0 ]' ||
    e2e_fail "killing the group left windows behind: $(demo_clients)"
e2e_log "PASS: a log group ends with its last window"
