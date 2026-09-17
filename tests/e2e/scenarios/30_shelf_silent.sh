#!/usr/bin/env bash
# A shelf app's window routes to its special workspace silently: it lands on
# special:shelf-signal and no special workspace is shown. No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace grouped
# conf/base.lua's signal shelf matches class "signal".
spawn_test_window signal

on_shelf() { client_of signal | jq -e '.workspace.name == "special:shelf-signal"' >/dev/null; }
wait_until 50 on_shelf || e2e_fail "signal did not route to its shelf: $(client_of signal)"
shown=$(hc -j monitors | jq -r 'map(.specialWorkspace.name) | map(select(. != "")) | join(",")')
assert_eq "$shown" "" "special workspace shown after a silent route"
assert_eq "$(hc -j activeworkspace | jq -r .name)" grouped "active workspace"
e2e_log "PASS shelf silent"
