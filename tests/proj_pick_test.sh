#!/usr/bin/env bash
# Functional tests for `,proj.sh pick` (LEO-377): no separate picker window.
#
# Inside tmux, fzf runs in a `tmux display-popup`. From a Hyprland bind with no
# terminal at all, exactly one project-classed window opens with fzf as its
# first screen, and that SAME window becomes the project session — never a
# picker window plus a second one.
#
# The real desktop is never touched: `tmux`, `kitty` and `fzf` are all faked
# via PATH, and PATH carries nothing else but the handful of real tools the
# script needs (real `hyprctl`/`notify-send`/`uwsm` are deliberately absent —
# there is no live compositor here, so the script must fall back cleanly, the
# same way it does on a bare tty).

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

# A scratch desk, a fake project, and a PATH holding only real tools the
# script actually needs plus three fakes: `tmux` (session bookkeeping, no
# real server), `kitty` (runs its `-e` command right here, no window), and
# `fzf` (prints $FZF_PICK_CHOICE, or "cancels" when unset).
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
    mkdir -p "$PROJDIR"
    cat >"$XDG_CONFIG_HOME/tms/config.toml" <<EOF
excluded_dirs = [".git"]
bookmarks = ["$PROJDIR"]
EOF

    FAKEBIN="$ROOT/bin"
    mkdir -p "$FAKEBIN"
    for tool in fd jq awk sed grep cut sort tr mktemp stat date cksum paste wc \
        mkdir cat mv rm touch readlink basename dirname tty pgrep id env bash sh printf true false; do
        real=$(command -v "$tool" 2>/dev/null) || continue
        ln -sf "$real" "$FAKEBIN/$tool"
    done
    export SHELL="$FAKEBIN/bash"
    # An empty, isolated $HOME: `-ic` sources shell rc files, and the real
    # user's must not run against this cut-down PATH.
    export HOME="$ROOT/home"
    mkdir -p "$HOME"

    TMUX_LOG="$ROOT/tmux.log"
    TMUX_STATE="$ROOT/tmux-state"
    mkdir -p "$TMUX_STATE"
    : >"$TMUX_LOG"
    export TMUX_FAKE_LOG="$TMUX_LOG" TMUX_FAKE_STATE="$TMUX_STATE"
    cat >"$FAKEBIN/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
# Fake tmux: no real server. Records every call and keeps just enough state
# (which session names exist per socket) for ,proj.sh's pick/open to run to
# completion without a terminal.
printf '%s\n' "$*" >>"$TMUX_FAKE_LOG"

sock=default
rest=()
while [[ $# -gt 0 ]]; do
    if [[ $1 == -L ]]; then
        sock=$2
        shift 2
        continue
    fi
    rest+=("$1")
    shift
done
set -- "${rest[@]}"
sessions="$TMUX_FAKE_STATE/sessions-$sock"
touch "$sessions"

find_opt() { # $1 = flag, then "$@" to scan -> its value on stdout
    local flag=$1
    shift
    while [[ $# -gt 0 ]]; do
        if [[ $1 == "$flag" ]]; then
            printf '%s' "${2-}"
            return 0
        fi
        shift
    done
    return 1
}

cmd=${1-}
[[ $# -gt 0 ]] && shift
case "$cmd" in
has-session)
    t=$(find_opt -t "$@")
    t=${t#=}
    grep -qxF "$t" "$sessions"
    ;;
new-session)
    name=$(find_opt -s "$@")
    if [[ -n $name ]] && ! grep -qxF "$name" "$sessions"; then
        printf '%s\n' "$name" >>"$sessions"
    fi
    ;;
new-window | set-option | select-window | kill-session | detach-client | switch-client)
    exit 0
    ;;
list-sessions)
    while IFS= read -r s; do
        [[ -n $s ]] && printf '%s\t0\n' "$s"
    done <"$sessions"
    ;;
list-clients)
    exit 0
    ;;
attach-session)
    # No real client ever attaches in a test: fail fast, like a detached run.
    exit 1
    ;;
display-popup)
    while [[ $# -gt 0 && $1 != -- ]]; do
        shift
    done
    [[ $# -gt 0 ]] && shift
    "$@"
    ;;
*)
    exit 0
    ;;
esac
FAKE_TMUX
    chmod +x "$FAKEBIN/tmux"

    KITTY_LOG="$ROOT/kitty.log"
    : >"$KITTY_LOG"
    export KITTY_FAKE_LOG="$KITTY_LOG"
    cat >"$FAKEBIN/kitty" <<'FAKE_KITTY'
#!/usr/bin/env bash
# Fake kitty: never opens a real window. Runs its `-e` command right here, so
# a test can see straight through to what that command actually did.
printf '%s\n' "$*" >>"$KITTY_FAKE_LOG"
cmd=()
found=0
while [[ $# -gt 0 ]]; do
    if [[ $1 == -e ]]; then
        shift
        cmd=("$@")
        found=1
        break
    fi
    shift
done
((found)) || exit 0
exec "${cmd[@]}"
FAKE_KITTY
    chmod +x "$FAKEBIN/kitty"

    FZF_LOG="$ROOT/fzf.log"
    : >"$FZF_LOG"
    export FZF_FAKE_LOG="$FZF_LOG"
    cat >"$FAKEBIN/fzf" <<'FAKE_FZF'
#!/usr/bin/env bash
# Fake fzf: prints $FZF_PICK_CHOICE (simulating a pick), or "cancels" (fzf's
# own exit-130 convention) when it is unset.
printf '%s\n' "$*" >>"$FZF_FAKE_LOG"
# Drain stdin: real fzf always reads its whole input, and an upstream `cut`
# left writing into a closed pipe would SIGPIPE — a spurious pipefail failure
# that has nothing to do with the pick itself.
cat >/dev/null
if [[ -n ${FZF_PICK_CHOICE-} ]]; then
    printf '%s\n' "$FZF_PICK_CHOICE"
    exit 0
fi
exit 130
FAKE_FZF
    chmod +x "$FAKEBIN/fzf"

    OLD_PATH=$PATH
    export PATH="$FAKEBIN"
}

teardown() {
    export PATH="$OLD_PATH"
    unset FZF_PICK_CHOICE TMUX HERE INLINE
    rm -rf "$ROOT"
}

sessions_for() { # $1 = socket -> its session names, one per line
    cat "$TMUX_STATE/sessions-$1" 2>/dev/null
}

echo "inside tmux: pick opens a popup, never a picker window"
setup
export TMUX="$ROOT/tmux-default,1,0" # some OTHER session, not the new project's own
export FZF_PICK_CHOICE=demo
rc=0
"$PROJ_SH" pick </dev/null || rc=$?
check "pick exits clean" "0" "$rc"
contains "the popup is what shows fzf" "display-popup" "$(cat "$TMUX_LOG")"
check "kitty opened exactly once (the project, not a picker)" "1" "$(count_lines "$KITTY_LOG")"
not_contains "the one window opened is never the retired picker class" "Proj-Picker" "$(cat "$KITTY_LOG")"
not_contains "...nor its lowercase would-be successor" "Proj-picker" "$(cat "$KITTY_LOG")"
contains "it carries the project's own class" "--class Proj-demo" "$(cat "$KITTY_LOG")"
contains "the project session actually got created" "demo" "$(sessions_for "proj-demo")"
teardown

echo "no terminal at all: one project window, fzf as its first screen"
setup
unset TMUX
export FZF_PICK_CHOICE=demo
rc=0
"$PROJ_SH" pick </dev/null || rc=$?
check "pick exits clean" "0" "$rc"
not_contains "no tmux popup: there is no tmux client to pop over" "display-popup" "$(cat "$TMUX_LOG")"
check "exactly one window ever opens" "1" "$(count_lines "$KITTY_LOG")"
contains "it is the ordinary project class (matches config.apps.project.class), not a dedicated picker rule" \
    "--class Proj-picker" "$(cat "$KITTY_LOG")"
contains "and that SAME window becomes the project's session" \
    "demo" "$(sessions_for "proj-demo")"
teardown

echo "no terminal, cancelled pick: the window closes, nothing opens"
setup
unset TMUX
unset FZF_PICK_CHOICE
rc=0
"$PROJ_SH" pick </dev/null || rc=$?
check "a cancelled pick is not a failure" "0" "$rc"
check "still only the one (now-cancelled) window" "1" "$(count_lines "$KITTY_LOG")"
check "no project session was ever created" "" "$(sessions_for "proj-demo")"
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
