#!/usr/bin/env bash
# ,proj.sh — one entry point for "put me in project X, on tab Y".
#
# The project list is not a second source of truth: it is scraped from the tms
# config (~/.config/tms/config.toml), so tms's own picker and this one always
# agree on what a project is.
#
# A project is a tmux SESSION, and it starts life on a server of its own, socket
# `proj-<name>`. That keeps projects apart by default: opening one never touches
# another, and nothing arrives on a socket by accident — the tmux config's
# picker calls back into this script rather than letting `tms` attach whatever
# it likes to whichever server you happen to be sitting in.
#
# `--here` is the deliberate exception: it hosts the project you pick as a
# second session on the window's CURRENT server, so both are one `C-b C-s`
# apart in the same terminal. Because of that a socket's name says only where a
# project started, never what it holds now — so identity is resolved by session
# throughout (`locate_project`), and teardown kills sessions, never the server.
#
# Inside a project's server there is one session with the project's window
# template (nvim / zsh / run by default, see "per-project config" below); a
# second terminal on the same project gets a GROUPED session (`new-session -t
# <proj>`) — same windows, its own current-window — so the two windows stop
# fighting over the focus.
#
# Each window carries the class `Proj-<name>`, so Hyprland rules can address one
# project, and so `open` can re-focus a project that is already on screen rather
# than stacking another terminal on it.
#
# The servers are meant to be invisible. Nothing below takes a socket by hand:
# commands that act on "the current project" resolve it from $TMUX when run in a
# pane, and otherwise from the focused Hyprland window, by walking its process
# tree to the tmux client and reading the -L it was started with.
#
#   ,proj.sh pick [window]        fzf over all projects, in its own window
#   ,proj.sh open [-n] <path> [w] open a known path (-n: always a new window)
#   ,proj.sh ... --here           re-point THIS window at the project, instead
#                                 of opening another one: the window drops its
#                                 client and attaches to the other server
#   ,proj.sh close-window         close the focused window, offering to take the
#                                 whole project down with it
#   ,proj.sh list                 name<TAB>path, one per line
#   ,proj.sh running              project<TAB>socket<TAB>clients<TAB>windows
#   ,proj.sh window <name>        jump to a window in the current session
#   ,proj.sh close                detach this window's client — closes the
#                                 portal, leaves the project running
#   ,proj.sh kill                 kill the focused project (its sessions; the
#                                 server goes with it if it held nothing else)
#   ,proj.sh kill-all             kill every project server
#   ,proj.sh drift                 compare projects.json's project names
#                                 against this scan (see "projects.json" below)
#
# projects.json ($XDG_STATE_HOME/projects.json, schema in the quickshell repo)
# holds dashboard metadata this scan has no room for — kind, tmux window
# template for display, `study`, priority — keyed by project name. It does NOT
# carry a path: this scan is the only thing allowed to say where a project
# lives, on pain of the exact failure mode this header already warns about.
# `drift` is the check for the other half — a name in projects.json that this
# scan no longer produces (renamed, removed, typo'd).
#
# Per-project config — `.proj.toml` in the repo root, or a `[projects.<name>]`
# table in the tms config (the repo file wins):
#
#   windows   = ["nvim", "zsh", "run"]   window template, in order
#   workspace = "code"                   Hyprland workspace to open onto
#                                        (default: code — only the initial
#                                        placement, the window moves freely
#                                        afterwards)
#
# A template window named `nvim` is started on `nvim .`; the rest open a shell.
#
# `window` defaults to the first template window. `kill`/`kill-all` confirm
# first — on a tty by prompt, otherwise in a picker window, since they are also
# reachable from a keybind. `-y` skips the confirmation.
set -euo pipefail

TMS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/tms/config.toml"
PROJECTS_JSON="${XDG_STATE_HOME:-$HOME/.local/state}/projects.json"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/proj-list"
CACHE_TTL=300
TEMPLATE_WINDOWS=(nvim zsh run)
# Where a project window is mapped unless it asks for somewhere else. Both hosts
# name workspace 1 "code"; a project overrides it with `workspace =`.
DEFAULT_WORKSPACE=code
CLASS_PREFIX=Proj-
SOCKET_PREFIX=proj-
PICKER_CLASS=Proj-Picker
SELF=$(readlink -f "${BASH_SOURCE[0]}")
# One handoff file per terminal, named after the pty its tmux client sits on.
# That pty is the one thing the pane side and the loop side both know.
HANDOFF_DIR="${XDG_RUNTIME_DIR:-/tmp}/proj-handoff"
# Separator for grouped-session names. Stripped out of project names below, so
# `<base>%2` can never collide with a project actually called that.
GROUP_SEP='%'

# Most of the callers are keybindings: `run-shell -b` throws stderr away and a
# Hyprland exec has nowhere to write it at all, so a refusal used to be a window
# that simply did not appear. Say it where the user is looking.
die() {
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    if [[ -n ${TMUX-} ]]; then
        command tmux display-message "proj: $1" 2>/dev/null || true
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "proj" "$1" 2>/dev/null || true
    fi
    exit 1
}

# Every tmux call goes through here, so no command below has to remember which
# server it is talking to.
socket=""
tmux() { command tmux ${socket:+-L "$socket"} "$@"; }

socket_for() { printf '%s%s\n' "$SOCKET_PREFIX" "${1//\//_}"; }
# Hyprland matches classes as regex, so the class keeps to [A-Za-z0-9_-].
class_for() { printf '%s%s\n' "$CLASS_PREFIX" "${1//[^A-Za-z0-9_-]/_}"; }

# --- toml -------------------------------------------------------------------

# tms's toml is flat and hand-written, so a line scraper beats a toml parser
# here — no extra runtime dependency for a handful of keys.

# Lines belonging to one table. $2 empty means the top-level (pre-table) keys.
section() { # $1 = file, $2 = table name, e.g. "projects.foo"
    [[ -f $1 ]] || return 0
    awk -v want="$2" '
    /^[[:space:]]*\[/ {
      cur = $0
      sub(/^[[:space:]]*\[+/, "", cur)
      sub(/\]+[[:space:]]*$/, "", cur)
      next
    }
    cur == want
  ' "$1"
}

# Both read a section body on stdin.

# Values of an array key, one per line. Walks from the "[" to the matching "]"
# rather than using a sed range: a range's end is only looked for on the NEXT
# line, so a single-line array would swallow the rest of the table.
conf_array() { # $1 = key
    awk -v k="$1" '
    BEGIN { pat = "^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\\[" }
    !inside && $0 ~ pat { inside = 1; sub(/^[^\[]*\[/, "") }
    inside {
      close_at = index($0, "]")
      if (close_at) { $0 = substr($0, 1, close_at - 1); inside = 2 }
      buf = buf $0
      if (inside == 2) exit
    }
    END {
      n = split(buf, item, ",")
      for (i = 1; i <= n; i++) {
        gsub(/[[:space:]"]/, "", item[i])
        if (item[i] != "") print item[i]
      }
    }
  '
}
conf_str() { # $1 = key
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

toml_array() { section "$TMS_CONFIG" "" | conf_array "$1"; }

# Resolves the window template and target workspace for one project into
# PROJ_WINDOWS / PROJ_WORKSPACE. Later sources win, so the repo's own file
# overrides the central tms config.
PROJ_WINDOWS=()
PROJ_WORKSPACE=""
load_project_conf() { # $1 = project name, $2 = path
    PROJ_WINDOWS=("${TEMPLATE_WINDOWS[@]}")
    PROJ_WORKSPACE=$DEFAULT_WORKSPACE
    local body ws
    local -a bodies=() w=()
    bodies+=("$(section "$TMS_CONFIG" "projects.$1")")
    bodies+=("$(section "$2/.proj.toml" "")")
    for body in "${bodies[@]}"; do
        [[ -n $body ]] || continue
        w=()
        mapfile -t w < <(printf '%s\n' "$body" | conf_array windows)
        if ((${#w[@]})); then
            PROJ_WINDOWS=("${w[@]}")
        fi
        ws=$(printf '%s\n' "$body" | conf_str workspace)
        if [[ -n $ws ]]; then
            PROJ_WORKSPACE=$ws
        fi
    done
}

# --- project list -----------------------------------------------------------

scan() {
    local -a excludes=()
    local dir
    while read -r dir; do
        # ".git" is in tms's exclude list, but it is exactly what the scan matches
        # on — excluding it would find nothing.
        if [[ -n $dir && $dir != .git ]]; then
            excludes+=(--exclude "$dir")
        fi
    done < <(toml_array excluded_dirs)

    # A project is a git repo (tms's definition) …
    local path depth
    while read -r path depth; do
        [[ -d $path ]] || continue
        # No --type filter: a linked worktree's .git is a file, not a directory.
        fd --hidden --no-ignore --max-depth "$depth" \
            "${excludes[@]}" '^\.git$' "$path" 2>/dev/null |
            sed 's:/\.git/\?$::'
    done < <(awk '
    function flush() { if (path != "") print path, depth; path = ""; depth = 10 }
    function quoted(   s) {
      return (match($0, /"[^"]*"/)) ? substr($0, RSTART + 1, RLENGTH - 2) : ""
    }
    BEGIN                             { depth = 10 }
    /^\[/                             { flush() }
    /^[[:space:]]*path[[:space:]]*=/  { path = quoted() }
    /^[[:space:]]*depth[[:space:]]*=/ { depth = $0; gsub(/[^0-9]/, "", depth) }
    END                               { flush() }
  ' "$TMS_CONFIG")

    # … plus the bookmarks, which are plain directories.
    toml_array bookmarks
}

list() {
    if [[ ${1-} != --refresh && -f $CACHE ]] &&
        (($(date +%s) - $(stat -c %Y "$CACHE") < CACHE_TTL)); then
        cat "$CACHE"
        return
    fi
    mkdir -p "${CACHE%/*}"
    # Two projects can share a basename, so the display name falls back to
    # parent/name — and the session and socket names follow it.
    scan | sed 's:/*$::' | sort -u | awk -F/ '
    { name[NR] = $NF; path[NR] = $0; parent[NR] = $(NF-1); n = NR }
    END {
      for (i = 1; i <= n; i++) count[name[i]]++
      for (i = 1; i <= n; i++)
        printf "%s\t%s\n", (count[name[i]] > 1 ? parent[i] "/" name[i] : name[i]), path[i]
    }' | sort >"$CACHE"
    cat "$CACHE"
}

# Whatever the cache already knows, without ever rebuilding it. Anything on a
# keypress path (is_project, running) uses this: a stale answer now beats a
# correct one after an `fd` sweep of every repo.
list_cached() {
    if [[ -f $CACHE ]]; then
        cat "$CACHE"
    else
        list
    fi
}

lookup() { # $1 = awk field to match on, $2 = value, $3 = field to print
    list | awk -F'\t' -v f="$1" -v v="$2" -v o="$3" '$f == v { print $o; exit }'
}

# A miss is usually a repo created since the cache was written, so every lookup
# gets one forced rescan before it gives up. Without this a fresh project is
# invisible for up to CACHE_TTL — and, worse, gets a different session name from
# the fallback than it will have once the cache catches up.
lookup_fresh() { # $1 = field, $2 = value, $3 = field to print
    local hit
    hit=$(lookup "$@") || true
    [[ -n $hit ]] || {
        list --refresh >/dev/null
        hit=$(lookup "$@") || true
    }
    printf '%s\n' "$hit"
}

# tmux forbids "." and ":" in session names; GROUP_SEP is reserved for grouped
# sessions, so it goes too.
project_name() { # $1 = path
    local p=${1%/} name
    name=$(lookup_fresh 2 "$p" 1)
    [[ -n $name ]] || name=${p##*/}
    printf '%s\n' "${name//[.:$GROUP_SEP]/_}"
}

# tmux name sanitising is lossy — ".", ":" and "%" all become "_" — so
# `foo.bar` and `foo_bar` arrive as one name, and the second project opened
# would silently join the first. The session records the path it was built for;
# when a name is already taken by a DIFFERENT path, this suffixes it.
path_digest() { printf '%s' "$1" | cksum | cut -d' ' -f1; }

session_path() { # $1 = session name (on $socket)
    # Read through list-sessions: `show-options -t` does not resolve the "="
    # exact-match target, and returns empty for a user option that is plainly set.
    tmux list-sessions -F "#{session_name}$(printf '\t')#{@proj_path}" 2>/dev/null |
        awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'
}

# The session name this path owns: the plain one, unless someone else has it.
resolve_name() { # $1 = candidate name, $2 = path -> name
    local name=$1 path=$2 sock owner
    sock=$(locate_project "$name") || {
        printf '%s\n' "$name"
        return 0
    }
    local saved=$socket
    socket=$sock
    owner=$(session_path "$name")
    socket=$saved
    # No recorded path means a session from before this existed, or one a user
    # made by hand: leave it alone and share it, which is what used to happen.
    if [[ -z $owner || $owner == "$path" ]]; then
        printf '%s\n' "$name"
    else
        printf '%s-%s\n' "$name" "$(path_digest "$path")"
    fi
}

# A project is its SESSION. The socket it lives on is only where it was first
# opened: `open --here` hosts a second project on the window's current server,
# so `proj-a` can hold sessions `a` and `b`. Everything below therefore asks
# "which server has this session" rather than trusting the socket's name.
locate_project() { # $1 = project name -> the socket holding it
    local sock guest=""
    while read -r sock; do
        command tmux -L "$sock" has-session -t "=$1" 2>/dev/null || continue
        # Its own server wins over one it is only a guest on, so the answer stays
        # the same no matter what order the sockets come in.
        if [[ $sock == "$SOCKET_PREFIX"* ]]; then
            printf '%s\n' "$sock"
            return 0
        fi
        [[ -n $guest ]] || guest=$sock
    done < <(live_sockets)
    [[ -n $guest ]] || return 1
    printf '%s\n' "$guest"
}

# The session this pane belongs to. $TMUX's third field is its id; that is the
# only source that also works under `run-shell`, where display-message resolves
# nothing.
current_session() {
    [[ -n ${TMUX-} ]] || return 1
    local sess
    sess=$(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null |
        awk -v id="\$${TMUX##*,}" '$1 == id { print $2; exit }')
    if [[ -z $sess && -n ${TMUX_PANE-} ]]; then
        sess=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}' 2>/dev/null)
    fi
    [[ -n $sess ]] || return 1
    printf '%s\n' "$sess"
}

# Is this session one of ours? A server we did not create can hold a project
# (`--here` seats them anywhere), and a `proj-` server can hold nothing else —
# so the question is asked of both the socket and the name.
is_project() { # $1 = session name, $2 = socket
    [[ $2 == "$SOCKET_PREFIX"* ]] && return 0
    local name
    while read -r name; do
        [[ $name == "$1" ]] && return 0
    done < <(list_cached | cut -f1)
    return 1
}

# The project a session belongs to: grouped views are "<project>%2".
project_of_session() { printf '%s\n' "${1%%"$GROUP_SEP"*}"; }

# The session to act on from inside tmux. Normally the pane's own — when you
# press the key, the pane you are in is the one you can see. But a `run-shell`
# hook or a background script can be rooted in a pane nobody is looking at, and
# killing that project instead of the visible one is not a mistake you can undo.
# So an unattached pane defers to the server's client, when there is just one.
visible_session() {
    local sess clients
    sess=$(current_session) || return 1
    if [[ -z $(tmux list-clients -t "=$sess" 2>/dev/null) ]]; then
        clients=$(tmux list-clients -F '#{client_session}' 2>/dev/null)
        if [[ -n $clients && $(printf '%s\n' "$clients" | wc -l) -eq 1 ]]; then
            sess=$clients
        fi
    fi
    printf '%s\n' "$sess"
}

# The project a client is looking at.
client_project() { # $1 = client pid (on $socket)
    local sess
    sess=$(tmux list-clients -F '#{client_pid} #{client_session}' 2>/dev/null |
        awk -v p="$1" '$1 == p { print $2; exit }')
    [[ -n $sess ]] || return 1
    project_of_session "$sess"
}

# --- which server am I in ---------------------------------------------------

# The tmux client for a window is a descendant of it, not the window process
# itself (kitty -> $SHELL -c -> tmux attach), so this walks the tree. Prints
# "<pid>\t<socket>" for every tmux client under it that names a socket.
tmux_clients_under() { # $1 = root pid
    local -a queue=("$1") argv
    local pid i sock
    while ((${#queue[@]})); do
        pid=${queue[0]}
        queue=("${queue[@]:1}")
        [[ -r /proc/$pid/cmdline ]] || continue
        argv=()
        mapfile -d '' -t argv <"/proc/$pid/cmdline" 2>/dev/null || true
        # argv[0] may be a path ("/usr/bin/tmux"), so match on its basename.
        if ((${#argv[@]})) && [[ ${argv[0]##*/} == tmux ]]; then
            sock=""
            for ((i = 1; i < ${#argv[@]}; i++)); do
                if [[ ${argv[i]} == -L ]]; then
                    sock=${argv[i + 1]-}
                    break
                elif [[ ${argv[i]} == -L?* ]]; then
                    sock=${argv[i]#-L}
                    break
                fi
            done
            if [[ -n $sock ]]; then
                printf '%s\t%s\n' "$pid" "$sock"
            fi
        fi
        mapfile -t -O "${#queue[@]}" queue < <(pgrep -P "$pid" 2>/dev/null)
    done
}

# A window can hold more than one tmux process (its client, plus whatever a pane
# spawned), so take the shallowest — the client the window was built around.
# Preferring a `proj-` socket here used to look right, but a project can now
# live on any server, and a pane's stray `tmux -L proj-x` call would have
# outranked the window's actual client.
client_under() { # $1 = root pid -> "<client pid>\t<socket>"
    local line
    while IFS= read -r line; do
        printf '%s\n' "$line"
        return 0
    done < <(tmux_clients_under "$1")
    return 1
}

# This Hyprland runs a Lua config plugin, and it parses everything handed to
# `hyprctl dispatch` as Lua — classic dispatch strings ("closewindow
# address:0x…") come back as a syntax error, and `hyprctl keyword` is not a
# request it answers at all. So every dispatch below is written as the Lua the
# plugin expects.
hypr_dispatch() { # $1 = lua expression returning a dispatcher
    command -v hyprctl >/dev/null 2>&1 || return 1
    hyprctl dispatch "$1" >/dev/null
}

# The picker is a terminal, not a layer surface. A layer surface has no window
# to place: rofi chose its output from the POINTER (its default is -m -5), and
# when it unmapped Hyprland handed focus back to whatever held it before, which
# raced with our own focus call. A window has neither problem — Hyprland's rules
# place it, it takes focus on map, and closing it returns focus the normal way.
# Blocking on kitty is what makes the choice a plain value again.
menu() { # $1 = prompt, choices on stdin -> the chosen line on stdout
    local items out rc
    items=$(mktemp) || return 1
    out=$(mktemp) || return 1
    cat >"$items"
    # `-ic`: the shell's rc is where FZF_DEFAULT_OPTS lives, so the picker looks
    # like every other fzf in this setup.
    kitty --class "$PICKER_CLASS" --title "$1" \
        -o confirm_os_window_close=0 \
        -e "$SHELL" -ic "fzf --prompt='$1 ' --reverse --no-preview --height=100% <$items >$out" \
        >/dev/null 2>&1 || true
    # The answer is the file, never the exit status: a terminal emulator reports
    # its own fate, not fzf's, so a cancelled pick came back looking like a
    # choice — and `--here` then dutifully moved the window to it. fzf writes
    # nothing unless the user accepts, so an empty file IS the cancellation.
    rc=1
    if [[ -s $out ]]; then
        cat "$out"
        rc=0
    fi
    rm -f "$items" "$out"
    return "$rc"
}

# Focus one window, and make it stick. Closing the picker hands focus back to
# whatever held it before, and that can land after our dispatch, so the focus is
# re-asserted until the window is actually the active one.
focus_window() { # $1 = address
    local i active
    for ((i = 0; i < 10; i++)); do
        hypr_dispatch "hl.dsp.focus({ window = \"address:$1\" })" || return 1
        active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
        [[ $active == "$1" ]] && return 0
        sleep 0.05
    done
    # Never claim it worked: the caller treats success as "you are there now", and
    # a false yes leaves the user with neither a focused window nor a new one.
    return 1
}

# Escapes a shell command for embedding in a Lua double-quoted string.
lua_str() {
    local v=$1
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    printf '%s' "$v"
}

focused_pid() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    local pid
    pid=$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty')
    [[ -n $pid ]] || return 1
    printf '%s\n' "$pid"
}

# Resolution order: an explicit override, the pane we were run from, then the
# focused window. The last one is what makes a Hyprland bind act on the project
# you are looking at.
resolve_socket() {
    if [[ -n ${PROJ_SOCKET-} ]]; then
        socket=$PROJ_SOCKET
        return 0
    fi
    if [[ -n ${TMUX-} ]]; then
        # $TMUX is "<socket path>,<pid>,<session>"; the socket's basename is its -L.
        socket=$(basename "${TMUX%%,*}")
        return 0
    fi
    local pid info
    pid=$(focused_pid) || return 1
    info=$(client_under "$pid") || return 1
    socket=${info#*$'\t'}
}

# Any server, not just a `proj-` one: `--here` can seat a project next to
# whatever a window was already running, and teardown is per session anyway.
require_socket() { # $1 = what for
    resolve_socket || die "$1: no project window focused"
}

# --- sessions ---------------------------------------------------------------

# tmux's "=" exact-match target is only honoured on session targets here
# (has-session, list-clients, attach, switch-client); set-option and window
# targets take the bare name, so those are kept apart deliberately.
has_session() { tmux has-session -t "=$1" 2>/dev/null; }

# Create the session with the project's window template. Windows are addressed
# by name everywhere below, so the template can be reordered freely.
# The editor window runs its command as the window's own command instead of
# being typed into it: `send-keys` raced the shell's rc, and a prompt that is
# still initialising can swallow the line — an empty shell where nvim should be.
# `exec $SHELL` afterwards keeps the window when the editor quits.
window_command() { # $1 = window name -> the command, or nothing
    [[ $1 == nvim ]] || return 0
    printf '%s -ic %s\n' "$(printf '%q' "$SHELL")" \
        "$(printf '%q' "nvim .; exec $(printf '%q' "$SHELL")")"
}

create_session() { # $1 = name, $2 = path
    local name=$1 path=$2 w cmd
    cmd=$(window_command "${PROJ_WINDOWS[0]}")
    # An empty command must not become an empty argv entry, hence the two calls.
    if [[ -n $cmd ]]; then
        tmux new-session -d -s "$name" -c "$path" -n "${PROJ_WINDOWS[0]}" "$cmd"
    else
        tmux new-session -d -s "$name" -c "$path" -n "${PROJ_WINDOWS[0]}"
    fi
    tmux set-option -t "$name" @proj_path "$path" >/dev/null
    for w in "${PROJ_WINDOWS[@]:1}"; do
        cmd=$(window_command "$w")
        if [[ -n $cmd ]]; then
            tmux new-window -d -t "$name:" -c "$path" -n "$w" "$cmd"
        else
            tmux new-window -d -t "$name:" -c "$path" -n "$w"
        fi
    done
}

# A grouped view is cleaned up by the terminal that owns it (see `serve`). If
# that terminal is killed outright the view outlives it, and the next window
# skips to %3, %4, … So sweep the ones nothing is attached to — but only once
# they are old enough that they cannot be a view created seconds ago by an
# `open` whose terminal has not attached yet.
ORPHAN_GRACE=${ORPHAN_GRACE:-60}
reap_orphan_views() { # $1 = base session name
    local sess created now
    now=$(date +%s)
    while read -r sess created; do
        [[ $sess == "$1$GROUP_SEP"* ]] || continue
        ((now - created < ORPHAN_GRACE)) && continue
        [[ -n $(tmux list-clients -t "=$sess" 2>/dev/null) ]] && continue
        tmux kill-session -t "$sess" 2>/dev/null || true
    done < <(tmux list-sessions -F '#{session_name} #{session_created}' 2>/dev/null)
    return 0
}

# The session a new client should attach to: the project session itself while
# nobody is on it, otherwise a fresh member of its group.
attach_target() { # $1 = base session name
    local base=$1 clients i
    reap_orphan_views "$base"
    clients=$(tmux list-clients -t "=$base" 2>/dev/null | wc -l)
    if ((clients == 0)); then
        printf '%s\n' "$base"
        return
    fi
    for ((i = 2; ; i++)); do
        has_session "$base$GROUP_SEP$i" && continue
        tmux new-session -d -t "$base" -s "$base$GROUP_SEP$i"
        printf '%s\n' "$base$GROUP_SEP$i"
        return
    done
}

select_window() { # $1 = session, $2 = window name, $3 = cwd for a missing window
    tmux select-window -t "$1:$2" 2>/dev/null && return
    tmux new-window -t "$1:" -n "$2" -c "${3:-$HOME}"
}

# The project is already on screen: point that window's client at the window we
# were asked for and focus it, instead of stacking another terminal on it.
focus_existing() { # $1 = class, $2 = window, $3 = path, $4 = project, $5 = socket
    command -v hyprctl >/dev/null 2>&1 || return 1
    local addr pid info cpid sess
    # Candidates are every project terminal, its own class first. Class alone is
    # not proof: `open --here` re-points a window at another project and the class
    # it was mapped with stays behind. The socket its client is actually on is —
    # so that decides, and it also finds a handed-over window whose class still
    # names the project it used to hold.
    while read -r addr pid; do
        [[ -n $addr && -n $pid ]] || continue
        info=$(client_under "$pid") || continue
        [[ ${info#*$'\t'} == "$5" ]] || continue
        cpid=${info%%$'\t'*}
        socket=$5
        sess=$(tmux list-clients -F '#{client_pid} #{client_session}' 2>/dev/null |
            awk -v p="$cpid" '$1 == p { print $2; exit }')
        # One server can host several projects now, so "same socket" is not enough:
        # this window must be the one actually showing this project. A window parked
        # on a neighbouring project is left alone — hijacking it would lose the view
        # the user put there.
        [[ $(project_of_session "$sess") == "$4" ]] || continue
        select_window "$sess" "$2" "$3"
        focus_window "$addr"
        return 0
    done < <(hyprctl clients -j 2>/dev/null | jq -r --arg c "$1" --arg p "$CLASS_PREFIX" '
    map(select(.class | startswith($p)))
    | sort_by(.class != $c)
    | .[] | "\(.address) \(.pid)"')
    return 1
}

handoff_for() { printf '%s/%s\n' "$HANDOFF_DIR" "${1##*/}"; }

# What a project terminal actually runs. Attaching in a loop is what lets one
# window change projects: a client cannot move between tmux servers, but the
# shell that owns the window can drop one client and raise another. `open
# --here` writes the next target next to this terminal's pty and detaches; every
# other exit path leaves no file, so the loop ends and the window closes.
serve() { # $1 = socket, $2 = session
    local sock=$1 target=$2 base handoff
    # The pty is the key both sides agree on; without one (no terminal at all)
    # fall back to something unique rather than a name every loop would share.
    handoff=$(handoff_for "$(tty 2>/dev/null || printf 'pid-%s' "$$")")
    mkdir -p "$HANDOFF_DIR"
    while :; do
        rm -f "$handoff"
        command tmux -L "$sock" attach-session -t "=$target" || true
        # A grouped session is a throwaway view, so it dies with its client. Doing
        # it here rather than with destroy-unattached is deliberate: that option
        # would reap the session in the gap before the client ever attaches.
        base=${target%%"$GROUP_SEP"*}
        if [[ $target != "$base" ]]; then
            command tmux -L "$sock" kill-session -t "$target" 2>/dev/null || true
        fi
        [[ -f $handoff ]] || break
        IFS=$'\t' read -r sock target <"$handoff" || true
        rm -f "$handoff"
        [[ -n $sock && -n $target ]] || break
    done
}

# The terminal `open --here` is going to re-point: its pty, the server it is on
# now, and the client to detach. Captured BEFORE the picker opens, because the
# picker takes the focus `hyprctl activewindow` would otherwise report.
HERE_TTY=""
HERE_SOCKET=""
HERE_CLIENT=""
capture_here() {
    local pid info cpid sess base

    # From a pane first — it knows exactly which client asked. Note that
    # `display-message` is useless here: under `run-shell` (which is how the tmux
    # binding calls this) it resolves no target and returns empty for every field,
    # so the session comes out of $TMUX, whose third field is the session id.
    if [[ -n ${TMUX-} ]]; then
        socket=$(basename "${TMUX%%,*}")
        HERE_SOCKET=$socket
        sess=$(current_session) || sess=""
        # The client to move is whichever one is viewing this project — the session
        # itself or one of its grouped views.
        base=$(project_of_session "$sess")
        if [[ -n $base ]]; then
            read -r HERE_CLIENT HERE_TTY < <(tmux list-clients \
                -F '#{client_name} #{client_tty} #{client_session}' 2>/dev/null |
                awk -v b="$base" -v g="$GROUP_SEP" '{ s = $3; i = index(s, g);
          if (i) s = substr(s, 1, i - 1); if (s == b) { print $1, $2; exit } }') || true
        fi
    fi

    # Otherwise (a Hyprland bind has no $TMUX) the focused window is the client.
    if [[ -z $HERE_TTY || -z $HERE_CLIENT ]]; then
        pid=$(focused_pid) || die "here: run this from a project pane, or focus one"
        info=$(client_under "$pid") || die "here: the focused window holds no tmux client"
        cpid=${info%%$'\t'*}
        HERE_SOCKET=${info#*$'\t'}
        socket=$HERE_SOCKET
        read -r HERE_CLIENT HERE_TTY < <(tmux list-clients \
            -F '#{client_pid} #{client_name} #{client_tty}' 2>/dev/null |
            awk -v p="$cpid" '$1 == p { print $2, $3; exit }') || true
    fi

    # Any server will do. A project is a session now, and teardown is scoped to
    # sessions, so hosting one next to whatever this window already runs — even a
    # plain `tms` server — costs nothing and is exactly what was asked for.
    [[ -n $HERE_SOCKET ]] || die "here: cannot tell which tmux server this window is on"
    [[ -n $HERE_TTY && -n $HERE_CLIENT ]] || die "here: no tmux client to attach the project to"
}

open() { # $1 = path, $2 = window
    local path=${1%/} window=${2-} name class target
    [[ -d $path ]] || die "no such directory: $path"
    if [[ ${HERE-} == 1 && -z $HERE_TTY ]]; then
        capture_here
    fi
    name=$(project_name "$path")
    name=$(resolve_name "$name" "$path")
    # Wherever it already runs; its own socket only if it runs nowhere.
    socket=$(locate_project "$name") || socket=$(socket_for "$name")
    class=$(class_for "$name")
    load_project_conf "$name" "$path"
    window=${window:-${PROJ_WINDOWS[0]}}

    # Where a brand-new project should be born. `--here` puts it on the window's
    # current server so both projects sit side by side; this has to be decided
    # before the session exists, or it would be created on the wrong one.
    if [[ ${HERE-} == 1 && $socket == "$(socket_for "$name")" ]] && ! has_session "$name"; then
        socket=$HERE_SOCKET
    fi

    has_session "$name" || create_session "$name" "$path"

    # Run from a pane on this project's own server: move this client, no new
    # window. From anywhere else a window is what we came for.
    if [[ -n ${TMUX-} ]] && [[ $(basename "${TMUX%%,*}") == "$socket" ]]; then
        select_window "$name" "$window" "$path"
        # Name the client when we know it: under `run-shell` there is no "current"
        # one for tmux to guess at, and guessing would move somebody else's window.
        local -a client_arg=()
        if [[ -n $HERE_CLIENT ]]; then
            client_arg=(-c "$HERE_CLIENT")
        fi
        tmux switch-client "${client_arg[@]}" -t "=$name" ||
            die "could not switch this window to $name (its client went away?)"
        return
    fi

    # Re-point the window we came from instead of opening another one. The
    # window keeps the class it was mapped with, so it stays where it is on
    # screen — that is the point of asking for it here rather than in a new one.
    if [[ ${HERE-} == 1 ]]; then
        # The project lives on this window's own server: both are one `C-b C-s`
        # apart and the client never moves. Teardown is session-scoped (see `kill`),
        # so the neighbour survives.
        if [[ $socket == "$HERE_SOCKET" ]]; then
            select_window "$name" "$window" "$path"
            tmux switch-client -c "$HERE_CLIENT" -t "=$name" ||
                die "could not switch this window to $name (its client went away?)"
            return 0
        fi

        # It is already running on another server, and a client cannot straddle two.
        # So the window moves instead: its serve loop picks the handoff up and
        # re-attaches there.
        target=$(attach_target "$name")
        select_window "$target" "$window" "$path"
        mkdir -p "$HANDOFF_DIR"
        printf '%s\t%s\n' "$socket" "$target" >"$(handoff_for "$HERE_TTY")"
        socket=$HERE_SOCKET
        tmux detach-client -t "$HERE_CLIENT"
        return 0
    fi

    # … unless the project already has a window: then this is a "take me there",
    # not "give me another terminal". `-n` forces the second terminal.
    if [[ ${FORCE_NEW-} != 1 ]] && focus_existing "$class" "$window" "$path" "$name" "$socket"; then
        return 0
    fi
    # focus_existing repoints `socket` while it probes; put it back.
    socket=$(locate_project "$name") || socket=$(socket_for "$name")

    target=$(attach_target "$name")
    select_window "$target" "$window" "$path"

    # TMUX must not survive into the new terminal: opening project B from a pane
    # of project A would otherwise hand kitty a nested-attach refusal, and the
    # window would die on the spot.
    local serve_cmd launch_cmd
    serve_cmd=$(printf '%q serve %q %q' "$SELF" "$socket" "$target")
    launch_cmd="env -u TMUX -u TMUX_PANE kitty --class $(printf '%q' "$class")"
    launch_cmd="$launch_cmd -e $(printf '%q' "$SHELL") -c $(printf '%q' "$serve_cmd")"
    if command -v uwsm >/dev/null 2>&1; then
        launch_cmd="uwsm app -- $launch_cmd"
    fi

    # Placement rides on the exec itself. A `windowrule` would be the obvious
    # home for it, but this Hyprland answers no `keyword` request, so there is no
    # way to add one at runtime — and an exec rule is scoped to this launch
    # anyway, which a class rule never was.
    if command -v hyprctl >/dev/null 2>&1; then
        # Not `silent`: opening a project is a "take me there", so the workspace
        # comes forward and the new window takes focus, the way a bare launch does.
        if [[ -n $PROJ_WORKSPACE ]]; then
            launch_cmd="[workspace name:$PROJ_WORKSPACE] $launch_cmd"
        fi
        hypr_dispatch "hl.dsp.exec_cmd(\"$(lua_str "$launch_cmd")\")"
        return 0
    fi
    # Outside a Hyprland session the exec rule would just be noise in argv.
    exec "$SHELL" -c "$launch_cmd"
}

pick() { # $1 = window
    local choice path
    # Before the picker opens: it takes the focus `capture_here` reads from.
    if [[ ${HERE-} == 1 ]]; then
        capture_here
    fi
    choice=$(list | cut -f1 | menu " Project ") || exit 0
    [[ -n $choice ]] || exit 0
    # One path, even if two entries somehow share a display name — `open` takes a
    # single directory, and two lines here used to abort it.
    path=$(lookup_fresh 1 "$choice" 2)
    [[ -n $path ]] || die "no path for project: $choice"
    open "$path" "${1-}"
}

# A killed server leaves its socket file behind, so liveness is decided by
# actually talking to it — and the dead ones are swept while we are here.
#
# EVERY server, not just the `proj-` ones: since `--here` can seat a project on
# whatever server a window already had, that is where a project may have to be
# found. Looking only at `proj-*` made such a project invisible, and the next
# `open` of it built a second copy on its own socket.
live_sockets() {
    local sock saved=$socket
    for sock in "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/"*; do
        [[ -S $sock ]] || continue
        socket=${sock##*/}
        if tmux list-sessions >/dev/null 2>&1; then
            printf '%s\n' "$socket"
        else
            rm -f "$sock"
        fi
    done
    socket=$saved
}

# Only the servers this script creates. `kill-all` is about undoing its own
# work, so it must not reach a server that merely happens to host a project.
project_sockets() {
    local sock
    while read -r sock; do
        [[ $sock == "$SOCKET_PREFIX"* ]] && printf '%s\n' "$sock"
    done < <(live_sockets)
    return 0
}

# Servers are no longer one-to-one with projects, so this lists what each one
# actually holds.
running() {
    local sock sess
    # Scanning every server also turns up servers that are none of our business —
    # the log server, a stray `tms` one. A session there counts only if it is
    # actually a project, which is what `--here` would have seated.
    local -A known=()
    while read -r sess; do
        known[$sess]=1
    done < <(list_cached | cut -f1)

    while read -r sock; do
        socket=$sock
        while read -r sess; do
            [[ $sess == *"$GROUP_SEP"* ]] && continue
            [[ $sock == "$SOCKET_PREFIX"* || -n ${known[$sess]-} ]] || continue
            printf '%s\t%s\t%s client(s)\t%s window(s)\n' "$sess" "$sock" \
                "$(tmux list-clients -t "=$sess" 2>/dev/null | wc -l)" \
                "$(tmux list-windows -t "$sess" 2>/dev/null | wc -l)"
        done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    done < <(live_sockets)
}

# --- teardown ---------------------------------------------------------------

# Reachable from a keybind, where there is no tty to prompt on, so the same
# terminal picker stands in. Defaults to "no" in both forms.
# 0 = yes, 1 = no, 2 = cancelled. The third one matters: escaping a prompt must
# not be read as "no" and quietly do half the thing anyway.
confirm() { # $1 = question
    if [[ ${ASSUME_YES-} == 1 ]]; then
        return 0
    fi
    if [[ -t 0 ]]; then
        local answer
        read -r -p "$1 [y/N] " answer || return 2
        [[ $answer == [yY]* ]]
        return
    fi
    local picked
    picked=$(printf 'no\nyes\n' | menu "$1") || return 2
    [[ $picked == yes ]]
}

# Close the portal, not the project: detach the one client living in the
# focused window. Its kitty exits with it; the server keeps running.
close() {
    local pid info client want
    if [[ -n ${TMUX-} ]]; then
        resolve_socket
        tmux detach-client
        return
    fi
    pid=$(focused_pid) || die "close: no tty and no focused window"
    info=$(client_under "$pid") || die "close: focused window holds no tmux client"
    want=${info%%$'\t'*}
    socket=${info#*$'\t'}
    # Match on the client's own pid, so a project with several windows open loses
    # exactly the one you are looking at.
    client=$(tmux list-clients -F '#{client_pid} #{client_name}' |
        awk -v want="$want" '$1 == want { print $2 }')
    [[ -n $client ]] || die "close: no tmux client in the focused window"
    tmux detach-client -t "$client"
}

# The close bind. A window holding no project client just closes; one that does
# is offered the bigger hammer first, because closing it silently would leave a
# server running that nothing on screen points at any more. Answering no still
# closes the window — the project keeps running, same as `close`.
#
# Everything about the target is resolved BEFORE the prompt: the picker window
# takes the focus, so `hyprctl activewindow` would report it by the time we
# acted on the answer.
close_window() {
    local pid addr info cpid name client
    command -v hyprctl >/dev/null 2>&1 || die "close-window: no hyprctl"
    read -r addr pid < <(hyprctl activewindow -j 2>/dev/null |
        jq -r '. as $w | if $w.address then "\($w.address) \($w.pid)" else empty end') || true
    [[ -n ${addr-} && -n ${pid-} ]] || die "close-window: no window focused"

    # Any tmux client, on any socket: a project can be seated next to whatever a
    # window already ran, so the socket's name proves nothing either way.
    if ! info=$(client_under "$pid"); then
        hypr_dispatch "hl.dsp.window.close(\"address:$addr\")"
        return 0
    fi

    cpid=${info%%$'\t'*}
    socket=${info#*$'\t'}
    name=$(client_project "$cpid") || name=${socket#"$SOCKET_PREFIX"}
    client=$(tmux list-clients -F '#{client_pid} #{client_name}' 2>/dev/null |
        awk -v p="$cpid" '$1 == p { print $2; exit }')

    # A terminal that holds tmux but no project of ours — the log server, a bare
    # `tms` session — just closes. Offering to kill it would be answering a
    # question nobody asked.
    if ! is_project "$name" "$socket"; then
        hypr_dispatch "hl.dsp.window.close(\"address:$addr\")"
        return 0
    fi

    # The project this window shows — never the whole server, which may be hosting
    # another project alongside it. Escaping the prompt cancels the close as well:
    # the window you asked about is still there to ask again.
    local answer=0
    confirm "Closing $name — kill the project too (all its windows)?" || answer=$?
    case $answer in
    0) kill_sessions "$name" ;;
    2) return 0 ;;
    esac
    # Detaching this one client is what closes the window: its serve loop finds no
    # handoff waiting and ends, taking the terminal with it. After a kill the
    # client may already be gone, hence the fallback.
    if [[ -n $client ]] && tmux detach-client -t "$client" 2>/dev/null; then
        return 0
    fi
    hypr_dispatch "hl.dsp.window.close(\"address:$addr\")"
}

# Kill one project outright — server and all. Scoped by construction: this
# socket holds nothing but this project.
# Every session this project owns on the current server: the project session
# plus the grouped views extra windows attached to it.
project_sessions() { # $1 = project name
    tmux list-sessions -F '#{session_name}' 2>/dev/null |
        awk -v n="$1" -v g="$GROUP_SEP" 'index($0, n) == 1 &&
      (length($0) == length(n) || substr($0, length(n) + 1, 1) == g)'
}

# Kills the project, not the server. Since `open --here` a server can hold more
# than one project, and `kill-server` would take the neighbour with it. tmux
# exits on its own once the last session goes, so this still cleans up whole.
kill_sessions() { # $1 = project name
    local sess
    while read -r sess; do
        [[ -n $sess ]] && tmux kill-session -t "$sess" 2>/dev/null
    done < <(project_sessions "$1")
}

kill_project() {
    local pid info cpid name
    require_socket kill
    # Which project — the one the focused window is showing, not the one the
    # socket happens to be named after.
    if [[ -n ${TMUX-} ]]; then
        name=$(project_of_session "$(visible_session)")
    else
        pid=$(focused_pid) || die "kill: no project window focused"
        info=$(client_under "$pid") || die "kill: no project window focused"
        cpid=${info%%$'\t'*}
        name=$(client_project "$cpid") || die "kill: that window shows no project"
    fi
    confirm "Kill project $name (all its windows)?" || exit 0
    kill_sessions "$name"
}

kill_all() {
    local -a socks=()
    mapfile -t socks < <(project_sockets)
    ((${#socks[@]})) || die "no project servers running"
    confirm "Kill all ${#socks[@]} project server(s)?" || exit 0
    for socket in "${socks[@]}"; do
        tmux kill-server 2>/dev/null || true
    done
}

# The other half of "not a second source of truth": projects.json carries
# metadata this scan cannot, keyed by a name it must still recognise. A name
# that survives here after the project is gone from the scan is stale
# metadata nobody will notice until the dashboard shows a repo that no longer
# exists.
drift() {
    [[ -f $PROJECTS_JSON ]] || {
        echo "no projects.json at $PROJECTS_JSON (nothing to check)"
        return 0
    }
    command -v jq >/dev/null 2>&1 || die "drift: jq is required"
    local -a known=() stale=()
    mapfile -t known < <(jq -r '.projects | keys[]' "$PROJECTS_JSON")
    local name
    for name in "${known[@]}"; do
        if [[ -z $(lookup 1 "$name" 1) ]]; then
            stale+=("$name")
        fi
    done
    if ((${#stale[@]} == 0)); then
        echo "projects.json: no drift (${#known[@]} project(s) checked)"
        return 0
    fi
    printf 'projects.json: %d stale entr%s not in the current scan:\n' \
        "${#stale[@]}" "$([[ ${#stale[@]} == 1 ]] && echo y || echo ies)"
    printf '  %s\n' "${stale[@]}"
    return 1
}

# Flags are accepted on either side of the subcommand, so `open -n <path>`
# reads the way the usage above spells it.
FLAGS_EATEN=0
parse_flags() {
    FLAGS_EATEN=0
    while [[ ${1-} == -y || ${1-} == --yes || ${1-} == -n || ${1-} == --new ||
        ${1-} == --here ]]; do
        case $1 in
        -y | --yes) ASSUME_YES=1 ;;
        -n | --new) FORCE_NEW=1 ;;
        --here) HERE=1 ;;
        esac
        shift
        FLAGS_EATEN=$((FLAGS_EATEN + 1))
    done
}

parse_flags "$@"
shift "$FLAGS_EATEN"

case "${1-pick}" in
list) list "${2-}" ;;
running) running ;;
drift) drift ;;
pick)
    shift
    parse_flags "$@"
    shift "$FLAGS_EATEN"
    pick "${1-}"
    ;;
open)
    shift
    parse_flags "$@"
    shift "$FLAGS_EATEN"
    open "$@"
    ;;
window)
    [[ -n ${TMUX-} ]] || die "window: not inside tmux"
    resolve_socket
    select_window "$(current_session)" "${2:?window name}" "$PWD"
    ;;
close) close ;;
close-window) close_window ;;
serve)
    shift
    serve "${1:?socket}" "${2:?session}"
    ;;
kill) kill_project ;;
kill-all) kill_all ;;
*) die "unknown command: $1" ;;
esac
