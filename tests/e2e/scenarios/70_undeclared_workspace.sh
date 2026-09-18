#!/usr/bin/env bash
# LEO-382: a window that opens on a plain workspace workspace_specs does not
# name (Hyprland's own numbered workspace, e.g. from a startup app racing a
# scene) moves, address-targeted, to that monitor's declared workspace. No
# eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace 5
spawn_test_window e2e-undeclared

on_grouped() { client_of e2e-undeclared | jq -e '.workspace.name == "grouped"' >/dev/null; }
wait_until 50 on_grouped ||
    e2e_fail "e2e-undeclared did not land on the primary's declared workspace: $(client_of e2e-undeclared)"
e2e_log "PASS undeclared workspace"
