#!/usr/bin/env bash
# Boot and teardown: the nested compositor loads this config under the e2e
# host, answers on its own socket, and spawned nothing outside itself.
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
hc -j monitors | jq -e 'length >= 1' >/dev/null || e2e_fail "no monitors"
hc -j workspaces | jq -e 'map(.name) | index("grouped")' >/dev/null ||
    e2e_fail "workspace 'grouped' from conf/hosts/e2e.lua is missing"
if grep -qE '^uwsm |^qs -c quantumfate( kill)?$' "$E2E_STUB_LOG" 2>/dev/null; then
    e2e_fail "autostart reached the shell under QF_E2E: $(cat "$E2E_STUB_LOG")"
fi
e2e_log "PASS boot"
