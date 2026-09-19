#!/usr/bin/env bash
# Functional tests for `,proj.sh`: no tmux, no sockets — a
# project is a set of kitty windows Hyprland groups by class. This replaces
# the tmux-session-era version of this test: `pick`/`open` now spawn kitty
# windows directly and the project list comes from the store, so the fakes
# below are `hyprctl` (window state + dispatch), `kitty` (spawns are just
# logged + registered), `fzf` (a scripted pick) and `nvim` (a graceful-quit
# stand-in using a real AF_UNIX socket, so the `-S` check in `,proj.sh`
# exercises the real code path). Real `jq`/`fd`/`python3` are used — nothing
# else reaches outside PATH.

set -euo pipefail

ROOT_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJ_SH="$ROOT_REPO/bin/,proj.sh"
pass=0
fail=0

check() {
    local what=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        pass=$((pass + 1))
        printf '  ok   %s\n' "$what"
    else
        fail=$((fail + 1))
        printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$what" "$expected" "$actual"
    fi
}

contains() {
    local what=$1 needle=$2 haystack=$3
    case "$haystack" in
    *"$needle"*)
        pass=$((pass + 1))
        printf '  ok   %s\n' "$what"
        ;;
    *)
        fail=$((fail + 1))
        printf '  FAIL %s\n       %q not found in: %s\n' "$what" "$needle" "$haystack"
        ;;
    esac
}

not_contains() {
    local what=$1 needle=$2 haystack=$3
    case "$haystack" in
    *"$needle"*)
        fail=$((fail + 1))
        printf '  FAIL %s\n       %q unexpectedly found in: %s\n' "$what" "$needle" "$haystack"
        ;;
    *)
        pass=$((pass + 1))
        printf '  ok   %s\n' "$what"
        ;;
    esac
}

count_lines() { # $1 = file -> 0 for a missing/empty file
    [ -s "$1" ] || {
        echo 0
        return
    }
    wc -l <"$1"
}

# A scratch desk, a fake project, and a PATH holding only the real tools the
# script needs (fd, jq, python3, …) plus fakes for the four things a real
# desktop would supply: `kitty`, `fzf`, `hyprctl` and `nvim`.
setup() {
    ROOT=$(mktemp -d)
    export XDG_STATE_HOME="$ROOT/state"
    export XDG_CACHE_HOME="$ROOT/cache"
    export XDG_RUNTIME_DIR="$ROOT/run"
    export XDG_CONFIG_HOME="$ROOT/config"
    export QF_STORE="$XDG_STATE_HOME/quantum-store"
    mkdir -p "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR" \
        "$QF_STORE" "$XDG_CONFIG_HOME/tms"

    PROJDIR="$ROOT/repos/demo"
    mkdir -p "$PROJDIR/.git"
    cat >"$XDG_CONFIG_HOME/tms/config.toml" <<EOF
excluded_dirs = [".git"]
bookmarks = ["$PROJDIR"]
EOF

    FAKEBIN="$ROOT/bin"
    mkdir -p "$FAKEBIN"
    for tool in fd jq awk sed grep cut sort tr mktemp stat date cksum paste wc \
        mkdir cat mv rm touch readlink basename dirname tty pgrep pkill id env bash sh \
        printf true false python3 sleep seq xargs; do
        real=$(command -v "$tool" 2>/dev/null) || continue
        ln -sf "$real" "$FAKEBIN/$tool"
    done
    export SHELL="$FAKEBIN/bash"
    # An empty, isolated $HOME: `-ic` sources shell rc files, and the real
    # user's must not run against this cut-down PATH.
    export HOME="$ROOT/home"
    mkdir -p "$HOME"

    # --- fake hyprctl: window state lives in one JSON file, dispatches are
    # logged and mutate it exactly like the real compositor's effects would.
    HYPR_LOG="$ROOT/hyprctl.log"
    HYPR_CLIENTS="$ROOT/clients.json"
    HYPR_ACTIVE="$ROOT/active.txt"
    : >"$HYPR_LOG"
    printf '[]' >"$HYPR_CLIENTS"
    : >"$HYPR_ACTIVE"
    export HYPR_FAKE_LOG="$HYPR_LOG" HYPR_FAKE_CLIENTS="$HYPR_CLIENTS" HYPR_FAKE_ACTIVE="$HYPR_ACTIVE"
    cat >"$FAKEBIN/hyprctl" <<'FAKE_HYPRCTL'
#!/usr/bin/env python3
import json, os, re, subprocess, sys

LOG = os.environ["HYPR_FAKE_LOG"]
CLIENTS = os.environ["HYPR_FAKE_CLIENTS"]
ACTIVE = os.environ["HYPR_FAKE_ACTIVE"]

def clients():
    with open(CLIENTS) as f:
        return json.load(f)

def save(cs):
    with open(CLIENTS, "w") as f:
        json.dump(cs, f)

with open(LOG, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")

def unescape_lua_str(s):
    # Reverses proj.sh's `lua_str`: literal `\` doubled, literal `"` escaped
    # as `\"`. A left-to-right scan avoids any ambiguity a chained
    # str.replace would have between the two escapes.
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] in ('"', "\\"):
            out.append(s[i + 1])
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)

args = sys.argv[1:]
if args[:1] == ["clients"]:
    sys.stdout.write(json.dumps(clients()))
elif args[:1] == ["activewindow"]:
    addr = open(ACTIVE).read().strip()
    for c in clients():
        if c["address"] == addr:
            sys.stdout.write(json.dumps(c))
            break
    else:
        sys.stdout.write("{}")
elif args[:1] == ["dispatch"]:
    expr = args[1]
    m = re.match(r'hl\.dsp\.exec_cmd\("(.*)"\)$', expr, re.S)
    if m:
        cmd = unescape_lua_str(m.group(1))
        # Strip a leading "[workspace name:...]" placement prefix — not
        # meaningful outside a real compositor.
        cmd = re.sub(r'^\[[^\]]*\]\s*', "", cmd)
        subprocess.Popen(["bash", "-c", cmd], start_new_session=True)
    m = re.match(r'hl\.dsp\.window\.tag\(\{ window = "address:([^"]+)", tag = "\+([^"]+)" \}\)$', expr)
    if m:
        addr, tag = m.group(1), m.group(2)
        cs = clients()
        for c in cs:
            if c["address"] == addr:
                c.setdefault("tags", [])
                if tag not in c["tags"]:
                    c["tags"].append(tag)
        save(cs)
    m = re.match(r'hl\.dsp\.focus\(\{ window = "address:([^"]+)" \}\)$', expr)
    if m:
        open(ACTIVE, "w").write(m.group(1))
    m = re.match(r'hl\.dsp\.window\.close\("address:([^"]+)"\)$', expr)
    if m:
        addr = m.group(1)
        save([c for c in clients() if c["address"] != addr])
FAKE_HYPRCTL
    chmod +x "$FAKEBIN/hyprctl"

    # --- fake kitty: registers a client (class, fresh address) instead of
    # opening a real window, then runs its "-e" command like the old fake did
    # (so it can see straight through to what that command did).
    KITTY_LOG="$ROOT/kitty.log"
    : >"$KITTY_LOG"
    export KITTY_FAKE_LOG="$KITTY_LOG"
    cat >"$FAKEBIN/kitty" <<'FAKE_KITTY'
#!/usr/bin/env python3
import json, os, sys, itertools

log = os.environ["KITTY_FAKE_LOG"]
with open(log, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")

argv = sys.argv[1:]
klass = ""
cmd = []
i = 0
while i < len(argv):
    if argv[i] == "--class":
        klass = argv[i + 1]
        i += 2
    elif argv[i] == "-e":
        cmd = argv[i + 1 :]
        break
    else:
        i += 1

clients_path = os.environ["HYPR_FAKE_CLIENTS"]
with open(clients_path) as f:
    cs = json.load(f)
addr = "0x%x" % (len(cs) + 1)
cs.append({"address": addr, "class": klass, "tags": []})
with open(clients_path, "w") as f:
    json.dump(cs, f)

if cmd:
    os.execvp(cmd[0], cmd)
FAKE_KITTY
    chmod +x "$FAKEBIN/kitty"

    # --- fake fzf: prints $FZF_PICK_CHOICE, or "cancels" (exit 130) when unset.
    FZF_LOG="$ROOT/fzf.log"
    : >"$FZF_LOG"
    export FZF_FAKE_LOG="$FZF_LOG"
    cat >"$FAKEBIN/fzf" <<'FAKE_FZF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FZF_FAKE_LOG"
cat >/dev/null
if [[ -n ${FZF_PICK_CHOICE-} ]]; then
    printf '%s\n' "$FZF_PICK_CHOICE"
    exit 0
fi
exit 130
FAKE_FZF
    chmod +x "$FAKEBIN/fzf"

    # --- fake nvim: `--listen SOCK` binds a real AF_UNIX socket and holds it
    # open; `--server SOCK --remote-send ...` (,proj.sh's graceful-quit) drops
    # a request file the listener polls for. $NVIM_FAKE_UNSAVED=1 makes the
    # listener treat that request as an unsaved-buffer prompt: it stays open
    # instead of quitting, exactly like a real `:confirm qa` would.
    cat >"$FAKEBIN/nvim" <<'FAKE_NVIM'
#!/usr/bin/env python3
import os, socket, sys, time

argv = sys.argv[1:]
if argv[:1] == ["--listen"]:
    sock_path = argv[1]
    try:
        os.remove(sock_path)
    except FileNotFoundError:
        pass
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(sock_path)
    s.listen(1)
    req = sock_path + ".request"
    unsaved = os.environ.get("NVIM_FAKE_UNSAVED") == "1"
    for _ in range(200):  # ~10s ceiling so a stuck test fails fast, not hangs
        if os.path.exists(req):
            os.remove(req)
            if unsaved:
                open(sock_path + ".prompted", "w").close()
                continue  # stays open: the "confirm" dialog is up
            break
        time.sleep(0.05)
    s.close()
    try:
        os.remove(sock_path)
    except FileNotFoundError:
        pass
    # A clean quit ends nvim's process, which (since kitty execvp'd straight
    # into it) is the window's only process — so the window itself is gone
    # too, exactly like a real compositor would report it.
    clients_path = os.environ.get("HYPR_FAKE_CLIENTS")
    if clients_path:
        import json
        with open(clients_path) as f:
            cs = json.load(f)
        cs = [c for c in cs if "slot:nvim" not in c.get("tags", [])]
        with open(clients_path, "w") as f:
            json.dump(cs, f)
elif argv[:1] == ["--server"]:
    open(argv[1] + ".request", "w").close()
FAKE_NVIM
    chmod +x "$FAKEBIN/nvim"

    OLD_PATH=$PATH
    export PATH="$FAKEBIN"
}

teardown() {
    # nvim's fake listener may still be running (an "unsaved" test leaves it
    # deliberately blocked) — nothing but this test tree depends on it.
    pkill -f "$ROOT" 2>/dev/null || true
    export PATH="$OLD_PATH"
    unset FZF_PICK_CHOICE NVIM_FAKE_UNSAVED
    rm -rf "$ROOT"
}

clients_json() { cat "$HYPR_CLIENTS"; }

# The nvim role's fake daemon binds its socket a beat after the client entry
# appears (client registration happens before `nvim --listen` even starts) —
# `kill` must not race that, or it reads "no socket yet" as "not nvim".
wait_for_nvim_sock() { # $1 = class
    local sock="$XDG_RUNTIME_DIR/proj-nvim/$1.sock"
    for _ in $(seq 1 40); do
        [ -S "$sock" ] && return 0
        sleep 0.05
    done
    return 1
}

# `,proj.sh open` tags each spawned window one at a time, in the background
# (`spawn_missing`, so a client-count check alone can pass while a later role
# is still untagged) — anything that reads role tags (`kill` included) must
# wait for every expected tag, not just the window count.
wait_for_tags() { # $1 = expected "slot:a,slot:b,..." (sorted, comma-joined)
    for _ in $(seq 1 60); do
        [ "$(clients_json | jq -r '[.[].tags[]?] | sort | join(",")')" = "$1" ] && return 0
        sleep 0.05
    done
    return 1
}

# A full `open demo` template (all three default roles), fully spawned AND
# tagged. Anything that reads `demo`'s live windows by role must call this
# rather than just waiting on the client count.
wait_full_open() {
    for _ in $(seq 1 40); do
        [ "$(jq 'length' "$HYPR_CLIENTS")" = "3" ] && break
        sleep 0.05
    done
    wait_for_tags "slot:nvim,slot:run,slot:zsh"
}

echo "sync: populates the store from the tms scan, path included"
setup
"$PROJ_SH" sync >/dev/null
check "the project landed in the store" "demo" \
    "$(jq -r '.projects.demo.path' "$QF_STORE/projects.json" | xargs -I{} basename {})"
check "default window template" '["nvim","zsh","run"]' \
    "$(jq -c '.projects.demo.windows' "$QF_STORE/projects.json")"
check "default workspace" "code" "$(jq -r '.projects.demo.workspace' "$QF_STORE/projects.json")"
check "new project defaults to kind=repo" "repo" "$(jq -r '.projects.demo.kind' "$QF_STORE/projects.json")"
teardown

echo "sync: leaves hand-set dashboard metadata alone on a rerun"
setup
"$PROJ_SH" sync >/dev/null
jq '.projects.demo.study = true | .projects.demo.priority = 1' \
    "$QF_STORE/projects.json" >"$QF_STORE/projects.json.tmp"
mv "$QF_STORE/projects.json.tmp" "$QF_STORE/projects.json"
"$PROJ_SH" sync >/dev/null
check "study survives a resync" "true" "$(jq -r '.projects.demo.study' "$QF_STORE/projects.json")"
check "priority survives a resync" "1" "$(jq -r '.projects.demo.priority' "$QF_STORE/projects.json")"
teardown

echo "open: a fresh project spawns its whole window template"
setup
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
# The nvim window daemonizes and needs a beat to bind its socket.
wait_full_open
check "three windows, one per template entry" "3" "$(jq 'length' "$HYPR_CLIENTS")"
check "all carry the project's class" "3" \
    "$(clients_json | jq '[.[] | select(.class == "Proj-demo")] | length')"
check "every window got its role tag" "slot:nvim,slot:run,slot:zsh" \
    "$(clients_json | jq -r '[.[].tags[]?] | sort | join(",")')"
teardown

echo "open: reopening an already-open project spawns nothing new, just focuses"
setup
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
wait_full_open
"$PROJ_SH" open demo zsh >/dev/null
check "still exactly three windows (nothing re-spawned)" "3" "$(jq 'length' "$HYPR_CLIENTS")"
zsh_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:zsh") | .address')
check "the requested window took focus" "$zsh_addr" "$(cat "$HYPR_ACTIVE")"
teardown

echo "open: reopening with one window missing spawns only that one"
setup
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
wait_full_open
run_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:run") | .address')
jq --arg a "$run_addr" '[.[] | select(.address != $a)]' "$HYPR_CLIENTS" >"$HYPR_CLIENTS.tmp"
mv "$HYPR_CLIENTS.tmp" "$HYPR_CLIENTS"
"$PROJ_SH" open demo >/dev/null
wait_full_open
check "back up to three windows" "3" "$(jq 'length' "$HYPR_CLIENTS")"
teardown

echo "pick: no terminal at all opens one picker window, not a picker + a project window"
setup
"$PROJ_SH" sync >/dev/null
export FZF_PICK_CHOICE=demo
"$PROJ_SH" pick </dev/null >/dev/null
for _ in $(seq 1 40); do
    [ "$(jq 'length' "$HYPR_CLIENTS")" = "4" ] && break
    sleep 0.05
done
check "one picker window plus the three project windows" "4" "$(jq 'length' "$HYPR_CLIENTS")"
contains "the picker itself used the ordinary project class" "Proj-picker" "$(cat "$KITTY_LOG")"
teardown

echo "pick: cancelled — no project ever opens"
setup
"$PROJ_SH" sync >/dev/null
unset FZF_PICK_CHOICE
"$PROJ_SH" pick </dev/null >/dev/null
for _ in $(seq 1 40); do
    [ "$(jq 'length' "$HYPR_CLIENTS")" = "1" ] && break
    sleep 0.05
done
check "only the (cancelled) picker window" "1" "$(jq 'length' "$HYPR_CLIENTS")"
teardown

echo "kill: closes plain windows outright, asks nvim to quit gracefully"
setup
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
wait_full_open
wait_for_nvim_sock Proj-demo
ASSUME_YES=1 "$PROJ_SH" kill demo >/dev/null 2>&1
for _ in $(seq 1 60); do
    [ "$(jq 'length' "$HYPR_CLIENTS")" = "0" ] && break
    sleep 0.05
done
check "nothing left standing once nvim quit clean" "0" "$(jq 'length' "$HYPR_CLIENTS")"
contains "the non-nvim windows were closed directly" "hl.dsp.window.close" "$(cat "$HYPR_LOG")"
teardown

echo "kill: an nvim window with unsaved buffers is never force-closed"
setup
"$PROJ_SH" sync >/dev/null
# The fake nvim daemon inherits its environment at spawn time, so the
# unsaved-buffer flag has to be set before `open`, not before `kill`.
export NVIM_FAKE_UNSAVED=1
"$PROJ_SH" open demo >/dev/null
wait_full_open
wait_for_nvim_sock Proj-demo
err=$(ASSUME_YES=1 "$PROJ_SH" kill demo 2>&1 >/dev/null) || true
check "nvim's window is still there" "1" \
    "$(clients_json | jq '[.[] | select(.tags[]? == "slot:nvim")] | length')"
contains "kill says so instead of pretending it worked" "still open" "$err"
teardown

echo "focus: resolves against whichever project's group is focused, not a hardcoded name"
setup
cat >"$PROJDIR/.proj.toml" <<EOF
[scopes]
test = "echo run-tests"
EOF
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
wait_full_open
zsh_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:zsh") | .address')
printf '%s' "$zsh_addr" >"$HYPR_ACTIVE" # focus starts on the shell window
"$PROJ_SH" focus nvim >/dev/null
nvim_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:nvim") | .address')
check "focus nvim lands on the nvim-tagged window" "$nvim_addr" "$(cat "$HYPR_ACTIVE")"
"$PROJ_SH" focus run >/dev/null
run_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:run") | .address')
check "focus run lands on the run-tagged window" "$run_addr" "$(cat "$HYPR_ACTIVE")"
teardown

echo "sync: folds a project's declared scopes into the store"
setup
cat >"$PROJDIR/.proj.toml" <<EOF
[scopes]
test = "echo run-tests"
logs = "echo tail-logs"
EOF
"$PROJ_SH" sync >/dev/null
check "both scopes landed, name to command" '{"logs":"echo tail-logs","test":"echo run-tests"}' \
    "$(jq -Sc '.projects.demo.scopes' "$QF_STORE/projects.json")"
teardown

echo "scope: spawns a declared scope with its own command and joins the group"
setup
cat >"$PROJDIR/.proj.toml" <<EOF
[scopes]
test = "echo run-tests"
EOF
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
wait_full_open
zsh_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:zsh") | .address')
printf '%s' "$zsh_addr" >"$HYPR_ACTIVE"
"$PROJ_SH" scope test >/dev/null
for _ in $(seq 1 40); do
    [ "$(jq 'length' "$HYPR_CLIENTS")" = "4" ] && break
    sleep 0.05
done
wait_for_tags "slot:nvim,slot:run,slot:test,slot:zsh"
check "the scope window joined the project's class" "4" \
    "$(clients_json | jq '[.[] | select(.class == "Proj-demo")] | length')"
contains "it spawned with the scope's own command" "run-tests" "$(cat "$KITTY_LOG")"
teardown

echo "scope: re-invoking an already-live scope focuses it instead of spawning again"
setup
cat >"$PROJDIR/.proj.toml" <<EOF
[scopes]
test = "echo run-tests"
EOF
"$PROJ_SH" sync >/dev/null
"$PROJ_SH" open demo >/dev/null
wait_full_open
zsh_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:zsh") | .address')
printf '%s' "$zsh_addr" >"$HYPR_ACTIVE"
"$PROJ_SH" scope test >/dev/null
for _ in $(seq 1 40); do
    [ "$(jq 'length' "$HYPR_CLIENTS")" = "4" ] && break
    sleep 0.05
done
wait_for_tags "slot:nvim,slot:run,slot:test,slot:zsh"
printf '%s' "$zsh_addr" >"$HYPR_ACTIVE"
"$PROJ_SH" scope test >/dev/null
check "still exactly four windows (nothing re-spawned)" "4" "$(jq 'length' "$HYPR_CLIENTS")"
test_addr=$(clients_json | jq -r '.[] | select(.tags[]? == "slot:test") | .address')
check "focused the existing scope window instead" "$test_addr" "$(cat "$HYPR_ACTIVE")"
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
