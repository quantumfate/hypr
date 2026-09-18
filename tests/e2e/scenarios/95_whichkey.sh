#!/usr/bin/env bash
# WhichKey on-screen behaviour: submap tracking, dismissal, and the dump a
# withheld tree must never leak into.
#
# Honesty note (read before extending this scenario): quickshell is stubbed
# out in this sandbox (QF_E2E=1 skips it; `qs` resolves to
# tests/e2e/stubs/stub, which only logs its argv), so this cannot see the
# actual QML overlay's pixels, its dwell/fade timers, or the LEO-222 110ms
# wall-clock budget. Those live in quickshell/modules/whichkey and are
# pinned by quickshell's own tests/whichkey.test.js; the 110ms on-desk
# measurement stays a human pass per LEO-300's own comment thread. What IS
# real here, against the real hypr/lib/submap.lua and hypr/lib/whichkey.lua
# running in the nested compositor (no scene registers a submap tree by
# default under QF_E2E, so this scenario builds one of its own via
# `submap.tree`, the same public API `hypr/binds.lua` uses):
#
#   - entering a submap is a real Hyprland submap change, observed on the
#     compositor's own event socket (socket2) as "submap>>NAME" — the exact
#     event a peek/overlay listener subscribes to for its appear path;
#   - leaving (M.exit) sends the "whichkey dismiss" IPC and returns the
#     compositor to the tree's base submap, with no lingering intermediate
#     level and no timer anywhere in the leave call chain (checked both by
#     behaviour and by a static grep of submap.lua's leave functions, since
#     the async IPC spawn means wall-clock ordering between the stub log
#     write and the submap event isn't a safe thing to assert on over a
#     shared CI box — this is the "known intermittent flake" this suite's
#     Readme warns about elsewhere, and asserting a race like that here
#     would just relocate it into this scenario);
#   - a nested chain (tree -> group -> group) fully unwinds on one M.exit():
#     the compositor lands on the base submap, not stuck mid-chain;
#   - `hypr/lib/whichkey.lua`'s M.dump, which the overlay's document is
#     built from, never emits a withheld tree's keys — restating "no stale
#     submap visible" as the static document property that actually backs
#     it, and one this harness CAN fully exercise (M.dump is a pure file
#     write, no compositor round trip).
. "$(dirname "$0")/../lib.sh"

run_lua() {
    local result="$E2E_ROOT/whichkey-result.json"
    command rm -f -- "$result"
    local wrapped="package.path = package.path .. \";$E2E_REPO/?.lua\"
local json = require(\"hypr.lib.json\")
local function out(tbl)
  local f = assert(io.open(\"$result\", \"w\"))
  f:write(json.encode(tbl))
  f:close()
end
$1"
    hc eval "$wrapped" >/dev/null || e2e_fail "lua snippet failed: $1"
    wait_until 30 test -f "$result" || true
    [[ -f $result ]] && cat "$result" || echo '{}'
}

current_submap() { run_lua "out({ submap = hl.get_current_submap() })" | jq -r .submap; }

stub_calls() { grep -cE "^qs .*whichkey dismiss$" "$E2E_ROOT/stubs.log" 2>/dev/null || echo 0; }

e2e_start

# No timer anywhere in the leave path — static guard against LEO-300's own
# regret ("Do not add a Timer back"). Grep the three leave functions'
# bodies, not the whole file, so an unrelated Timer elsewhere (there is
# none today) would not false-fail this.
LEAVE_BODY=$(awk '/^function M\.(back|exit|reset)\(\)/,/^end$/' "$E2E_REPO/hypr/lib/submap.lua")
if grep -qiE 'timer|sleep|delay|wait' <<<"$LEAVE_BODY"; then
    e2e_fail "a timer/sleep/delay crept into submap.lua's leave path: $LEAVE_BODY"
fi

# Build a throwaway submap tree the same way hypr/binds.lua would, so the
# rest of this scenario drives the real public API rather than a fixture of
# its own invention. No `mods` (never bound to a real key): every entry
# below is driven by calling submap.lua's functions directly via `hc eval`,
# matching this suite's documented approach elsewhere (`hq key` does not
# fire this config's Lua-closure keybinds in this sandbox — see
# 60_navigation.sh and 90_deck.sh's headers) for the exact function bodies a
# keypress would run.
run_lua "
local submap = require('hypr.lib.submap')
submap.tree({
  name = 'e2ewk',
  entries = {
    { key = 'a', desc = 'Leaf A' },
    { key = 'b', desc = 'Nested', entries = {
        { key = 'c', desc = 'Leaf C' },
      },
    },
  },
})
out({ ok = true })
" >/dev/null

BASE=$(current_submap)
e2e_log "base submap before entering: '$BASE'"

# Listen on the compositor's own event socket for the submap changes an
# overlay's appear/leave listeners key off. Tagged with \$E2E_ROOT so the
# EXIT trap's \`pkill -f \$E2E_ROOT\` cleans it up like the suite's spawned
# test windows.
EVENTS_LOG="$E2E_ROOT/events.log"
: >"$EVENTS_LOG"
SOCKET2="$XDG_RUNTIME_DIR/hypr/$E2E_SIG/.socket2.sock"
[[ -S $SOCKET2 ]] || e2e_fail "no socket2 at $SOCKET2"
(exec -a "e2e-wk-events-$E2E_ROOT" socat -u "UNIX-CONNECT:$SOCKET2" - >"$EVENTS_LOG" 2>/dev/null) &
sleep 0.2 # let socat attach before we start dispatching

# --- Entering a submap is a real, observable submap change -----------------
run_lua "require('hypr.lib.submap').enter('e2ewk'); out({ ok = true })" >/dev/null
[[ $(current_submap) == e2ewk ]] || e2e_fail "expected submap 'e2ewk' after enter, got '$(current_submap)'"
wait_until 30 grep -q "submap>>e2ewk" "$EVENTS_LOG" ||
    e2e_fail "no submap>>e2ewk event on socket2 after entering (overlay's appear path has nothing to listen to): $(cat "$EVENTS_LOG")"
e2e_log "PASS enter publishes a submap>>e2ewk event"

# --- A nested submap chain unwinds completely on one exit -------------------
run_lua "require('hypr.lib.submap').enter('e2ewk-b'); out({ ok = true })" >/dev/null
[[ $(current_submap) == e2ewk-b ]] || e2e_fail "expected submap 'e2ewk-b' after nested enter, got '$(current_submap)'"

BEFORE_DISMISS=$(stub_calls)
run_lua "require('hypr.lib.submap').exit(); out({ ok = true })" >/dev/null
AFTER=$(current_submap)
[[ $AFTER == "$BASE" ]] ||
    e2e_fail "chain did not unwind to base '$BASE' on exit(): landed on '$AFTER'"
[[ $AFTER != e2ewk && $AFTER != e2ewk-b ]] || e2e_fail "exit() left the overlay's submap stuck at '$AFTER'"
wait_until 30 sh -c "[[ \$(grep -cE '^qs .*whichkey dismiss$' '$E2E_ROOT/stubs.log' 2>/dev/null || echo 0) -gt $BEFORE_DISMISS ]]" ||
    e2e_fail "exit() from a nested submap never called the whichkey dismiss IPC"
e2e_log "PASS nested chain (e2ewk -> e2ewk-b) unwinds to base '$BASE' in one exit(), dismiss sent"

# --- Leaving via a leaf action also dismisses with no stale overlay ---------
run_lua "require('hypr.lib.submap').enter('e2ewk'); out({ ok = true })" >/dev/null
BEFORE_DISMISS=$(stub_calls)
run_lua "require('hypr.lib.submap').reset(); out({ ok = true })" >/dev/null
AFTER=$(current_submap)
# hl.dsp.submap("reset") is Hyprland's own "leave every submap" dispatcher
# keyword, not a literal submap named "reset" — it reports back as the empty
# string, same as never having entered one.
[[ $AFTER == "" ]] || e2e_fail "reset() did not land back on the empty/root submap, got '$AFTER'"
wait_until 30 sh -c "[[ \$(grep -cE '^qs .*whichkey dismiss$' '$E2E_ROOT/stubs.log' 2>/dev/null || echo 0) -gt $BEFORE_DISMISS ]]" ||
    e2e_fail "reset() never called the whichkey dismiss IPC"
e2e_log "PASS reset() dismisses and lands back on the root submap, no stale submap"

# --- A withheld tree's keys never appear in the dump ------------------------
run_lua "
local whichkey = require('hypr.lib.whichkey')
whichkey.dump({ root = true })
out({ ok = true })
" >/dev/null
WITHOUT=$(jq -c 'keys' "$QF_STORE/whichkey.json")
if jq -e 'has("e2ewk")' "$QF_STORE/whichkey.json" >/dev/null; then
    e2e_fail "withheld tree 'e2ewk' still present in the dump: $WITHOUT"
fi
if jq -e '.reset.items // [] | any(.child == "e2ewk")' "$QF_STORE/whichkey.json" >/dev/null; then
    e2e_fail "a leaf into the withheld tree 'e2ewk' still appears in the dump"
fi
e2e_log "PASS withheld tree absent from the dump: $WITHOUT"

run_lua "
local whichkey = require('hypr.lib.whichkey')
whichkey.dump({ root = true, e2ewk = true })
out({ ok = true })
" >/dev/null
jq -e 'has("e2ewk") and (.e2ewk.items | map(.key) | index("a") != null)' "$QF_STORE/whichkey.json" >/dev/null ||
    e2e_fail "admitting 'e2ewk' did not bring its keys back into the dump"
e2e_log "PASS admitting the tree restores its keys in the dump"

e2e_log "PASS whichkey submap tracking, dismissal and dump admission"
