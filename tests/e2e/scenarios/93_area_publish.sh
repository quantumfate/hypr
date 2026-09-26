#!/usr/bin/env bash
# Areas (docs/scenes.md "Areas"): a scene with tiles publishes `work` and
# `columns` whose corners contain the placed windows' geometry, monitor-local.
# Switching scene on a monitor republishes for the new scene.
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace code-deck
spawn_test_window e2e-proj-alpha-a
spawn_test_window e2e-browser

GEOM="$QF_STORE/geometry.json"

published_scene() { jq -r '.areas["WAYLAND-1"].scene // empty' "$GEOM" 2>/dev/null; }
column_count() { jq -r '.areas["WAYLAND-1"].columns | length' "$GEOM" 2>/dev/null; }

wait_until 200 sh -c "[ \"\$(jq -r '.areas[\"WAYLAND-1\"].scene // empty' '$GEOM' 2>/dev/null)\" = 'code-deck' ]" ||
    e2e_fail "code-deck never published areas.WAYLAND-1 ($GEOM)"

[ "$(column_count)" -ge 1 ] || e2e_fail "code-deck published no columns"

# The alpha window's live rect must sit inside SOME published column's box —
# monitor-local, so this reads the window's `at` straight from `clients`
# without subtracting the monitor origin (WAYLAND-1 is at 0,0 on this host).
tile_x() { clients | jq -r '[.[] | select(.class == "e2e-proj-alpha-a") | .at[0]] | first // empty'; }
tile_y() { clients | jq -r '[.[] | select(.class == "e2e-proj-alpha-a") | .at[1]] | first // empty'; }

TX=$(tile_x)
TY=$(tile_y)
[ -n "$TX" ] && [ -n "$TY" ] || e2e_fail "no live rect for e2e-proj-alpha-a"

# The live window rect and the published column box both derive from the same
# layout pass, but differ by the workspace rule's inner gap/border
# (hypr/scene/dock_publish.lua's `settled` doc: measured ~21px on a real
# desk) -- a small margin absorbs that without hiding a real placement bug
# (which would be off by a whole column's width, not a border's worth).
MARGIN=24
contains_tile() {
    jq -e --argjson x "$TX" --argjson y "$TY" --argjson m "$MARGIN" '
      .areas["WAYLAND-1"].columns
      | to_entries
      | map(.value)
      | any(.top_left.x - $m <= $x and $x <= .top_right.x + $m
            and .top_left.y - $m <= $y and $y <= .bottom_left.y + $m)
    ' "$GEOM" >/dev/null 2>&1
}
contains_tile || e2e_fail "no published column contains the placed tile's corner ($TX,$TY): $(jq -c '.areas["WAYLAND-1"].columns' "$GEOM")"
e2e_log "PASS: code-deck's columns contain the placed tile at ($TX,$TY)"

# Switching scene on this monitor republishes: `loose` has no deck columns,
# so its area's `scene` field must flip and its columns must differ in shape.
go_workspace loose
wait_until 100 sh -c "[ \"\$(jq -r '.areas[\"WAYLAND-1\"].scene // empty' '$GEOM' 2>/dev/null)\" = 'loose' ]" ||
    e2e_fail "switching to loose never republished areas.WAYLAND-1 (scene still $(published_scene))"
e2e_log "PASS: switching scene republished areas.WAYLAND-1 (scene=$(published_scene))"
