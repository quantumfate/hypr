#!/usr/bin/env bash
# ,proj.sh — one entry point for "put me in project X".
#
# A project is a set of kitty windows in one Hyprland group on the `code`
# scene (docs/scenes.md: the `code` block already groups `Proj-*`) — no
# sessions, no sockets, nothing tmux-shaped. A project ends
# when its last window closes; nothing is remembered, so reopening it starts
# fresh from its template. Opening a project that is already open refocuses
# it and spawns only whatever window its template says is missing, asked of
# Hyprland (`hyprctl clients -j`) rather than a socket.
#
# Projects live in the store ($QF_STORE/projects.json, schema in the
# quickshell repo, registry row in system-config/docs/stores.md): which
# projects exist, where each one lives, and its window template are read
# from there at runtime. The store is hand-curated and nothing here
# discovers projects: `,proj.sh add <name> [path]` is the one deliberate
# "this directory is a project now" gesture, `drop` the way out, and
# `sync` only refreshes what each stored project's own `.proj.toml`
# declares (windows/workspace/scopes; metadata fields — kind/study/
# priority — are left alone). The scan is gone along with the tms config
# it read: a project exists because someone added it. Run `sync` after
# editing a `.proj.toml`:
#
#   ,proj.sh sync
#
# Each window carries the class `Proj-<name>` (Hyprland matches classes as
# regex, kept to [A-Za-z0-9_-]) plus a launch-time role tag (`slot:nvim`,
# `slot:yazi`, `slot:zsh`, `slot:run`, stamped by `stamp_slot`) so a reopen
# can tell which template windows are already live. The template windows
# are the project's tabs — one Hyprland group, one tab per role; yazi is
# one of them, so a project has its file manager one tab away, and
# quitting yazi ends that tab the way quitting any terminal does.
#
#   ,proj.sh pick [window]        fzf over the store's projects: one
#                                 FLOATING kitty window on the code
#                                 workspace whose first screen IS fzf
#                                 (--inline: this process IS that window,
#                                 used internally to re-exec into it) — the
#                                 `code` scene groups one `Proj-<name>`
#                                 block per project, so a `Proj-picker`
#                                 window matches no block and the engine's
#                                 stray-float keeps it out of every group
#   ,proj.sh open <name> [window] open a project by its store name, or
#                                 focus/complete it if some of its windows
#                                 are already open
#   ,proj.sh open-one <name> <window>
#                                 open (or focus) exactly one of a
#                                 project's template windows, never the
#                                 whole template
#   ,proj.sh pick-window          fzf, inline, over the FOCUSED project's
#                                 template windows; the chosen one is
#                                 opened on its own (open-one, not `open`)
#   ,proj.sh list                 name<TAB>path, one per line, from the store
#   ,proj.sh add <name> [path]    deliberately make a directory a project:
#                                 writes path/windows/workspace/scopes into
#                                 the store from the repo's .proj.toml, or
#                                 the defaults where it says nothing
#   ,proj.sh sync                 refresh every stored project from its own
#                                 .proj.toml (windows/workspace/scopes);
#                                 discovers nothing — a directory that was
#                                 never added stays invisible
#   ,proj.sh kill [name]          close every window of a project (the
#                                 focused one if name is omitted); a window
#                                 running nvim is asked to quit gracefully
#                                 (see "nvim" below) and is never force-closed
#   ,proj.sh focus <role>         focus the FOCUSED project's <role>-tagged
#                                 window (e.g. "nvim", "run") — resolved from
#                                 whichever project's group is focused right
#                                 now, never a hardcoded name (bound as
#                                 SUPER+Space p n / p r; the Lua-side
#                                 equivalent hypr/lib/project.lua is what a
#                                 bind closure actually calls, this
#                                 subcommand exists for scripts/CLI use)
#   ,proj.sh pick-scope           fzf, inline, over the FOCUSED project's
#                                 declared scopes (see "scopes" below);
#                                 spawns or focuses the chosen one
#   ,proj.sh scope <name>         open the FOCUSED project's declared scope
#                                 <name> directly, no picker
#
# --- scopes: a project's own working context, on demand -------------------
#
# Beyond the fixed nvim/yazi/zsh/run template, a project can declare named
# scopes — a terminal with a command the project's own configuration
# carries, "like scenes but for projects". Declared in `.proj.toml`'s
# `[scopes]` table (repo root), one plain `name = "command"` per line, e.g.:
#
#   [scopes]
#   test = "just test"
#   logs = "journalctl --user -f"
#
# `sync` folds this into the store's `scopes` object the same way it folds
# `windows`/`workspace` (whole-table replace — see `load_project_conf`). A
# scope's role tag is `slot:<name>`, the same
# `slot:` vocabulary the fixed template uses, so `open`/`focus`/`kill` never
# need to know a window is a scope rather than a template role — the store
# and the live tag are the only difference.
#
# --- nvim: always prompts, never closed out from under you -----------------
#
# Quitting nvim through its own commands (`:q`, `:qa`, `:x`) already always
# refuses on an unsaved buffer (nvim's own E37, `:confirm qa` for the "save
# changes?" dialog) — nothing new needed there. The risk this chunk has to
# answer is a window closed FROM OUTSIDE nvim: the terminal is torn down
# (SIGHUP) before nvim can render anything, so a hard kill (a raw Hyprland
# `closewindow`, or `kitty --kill`) always throws unsaved work away no
# matter what nvim would have said.
#
# So an nvim slot window is launched with `--listen <sock>` (a per-window
# control socket under $XDG_RUNTIME_DIR/proj-nvim/, named after the window's
# own class — one nvim per project by construction) and `kill` asks it to
# quit THROUGH that socket (`nvim --server <sock> --remote-send
# ':confirm qa<CR>'`) instead of closing the window directly. If nvim has
# unsaved buffers it shows its own dialog and does not exit — `kill` waits a
# short beat, and a socket still alive after it means "still deciding" (or
# "said no"): that window is left exactly alone, never force-closed, and
# `kill` says so instead of silently taking the rest of the project down
# around it.
#
# What this does NOT cover: a generic window-close keybind (mod+q) still
# dispatches an ordinary Hyprland `closewindow`, which does not know about
# the nvim socket above and closes the terminal directly. Routing THAT
# through the same remote-quit path is a bindings-contract change (a
# contextual bind for `slot:nvim` windows), out of scope for a script-only
# chunk — flagged as a follow-up rather than silently left undocumented.
#
# Scene teardown (a mode switch away from `code`) never closes windows at
# all: docs/scenes.md's mode `apply` only relocates workspaces to monitors
# and applies holds; it has no path that kills a window. So a project's
# windows are already safe across a mode switch with no change here — this
# was verified by reading `hypr/hyprfocus/init.lua`'s `apply`, not assumed.
set -euo pipefail

# The shared quantum-store directory (QF_STORE).
QF_ROOT="${QF_STORE:-${XDG_STATE_HOME:-$HOME/.local/state}/quantum-store}"
PROJECTS_JSON="$QF_ROOT/projects.json"
TEMPLATE_WINDOWS=(nvim yazi zsh run)
# Where a project window is mapped unless it asks for somewhere else. Both
# hosts name workspace 1 "code"; a project overrides it with `workspace =`.
DEFAULT_WORKSPACE=code
CLASS_PREFIX=Proj-
SELF=$(readlink -f "${BASH_SOURCE[0]}")
NVIM_SOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/proj-nvim"

# Most callers are keybindings: a Hyprland exec has nowhere to write stderr
# at all, so a refusal used to be a window that simply did not appear. Say
# it where the user is looking.
die() {
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        ,notify project-manager "" "$1" -u critical 2>/dev/null || true
    fi
    exit 1
}

# Hyprland matches classes as regex, so the class keeps to [A-Za-z0-9_-].
class_for() { printf '%s%s\n' "$CLASS_PREFIX" "${1//[^A-Za-z0-9_-]/_}"; }

# --- store --------------------------------------------------------------

# The store is read-modify-written whole: it is small (per-project metadata,
# not window state) and jq has no in-place partial-write primitive that
# would be worth the complexity here.
store_read() {
    if [[ -s $PROJECTS_JSON ]]; then
        cat "$PROJECTS_JSON"
    else
        printf '{"projects":{}}\n'
    fi
}

store_write() { # stdin = the whole new document
    mkdir -p "${PROJECTS_JSON%/*}"
    local tmp
    tmp=$(mktemp "${PROJECTS_JSON}.XXXXXX")
    cat >"$tmp"
    mv "$tmp" "$PROJECTS_JSON"
}

# One project's object, or empty if it is not in the store.
store_project() { # $1 = name
    store_read | jq -c --arg n "$1" '.projects[$n] // empty'
}

store_field() { # $1 = name, $2 = jq filter over the project object
    store_project "$1" | jq -r "$2 // empty"
}

# --- toml (used only by `sync`/`add`) -------------------------------------

# The .proj.toml is flat and hand-written, so a line scraper beats a toml
# parser here — no extra runtime dependency for a handful of keys.

section() { # $1 = file, $2 = table name ("" = top level)
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

conf_array() { # $1 = key, section body on stdin
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
conf_str() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; } # $1 = key, section body on stdin

# `[scopes]`'s body, as name<TAB>command per declared scope (quoted-string
# assignments only — a nested table would need its own `[scopes.x]` section,
# which this flat reader does not descend into).
conf_kv() { # section body on stdin -> "key<TAB>value" per line
    sed -n 's/^[[:space:]]*\([A-Za-z0-9_.-]*\)[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1\t\2/p'
}

# {"name":"cmd",...} for a project's `[scopes]` body on stdin, or "{}" for a
# body that declares none.
scopes_json() {
    conf_kv | jq -R 'split("\t") | {(.[0]): .[1]}' | jq -sc 'add // {}'
}

# Resolves the window template, target workspace and declared scopes for one
# project into PROJ_WINDOWS / PROJ_WORKSPACE / PROJ_SCOPES: what its own
# .proj.toml declares, the defaults where it says nothing.
PROJ_WINDOWS=()
PROJ_WORKSPACE=""
PROJ_SCOPES="{}"
load_project_conf() { # $1 = project path
    PROJ_WINDOWS=("${TEMPLATE_WINDOWS[@]}")
    PROJ_WORKSPACE=$DEFAULT_WORKSPACE
    PROJ_SCOPES="{}"
    local body ws sc
    local -a w=()
    body=$(section "$1/.proj.toml" "")
    if [[ -n $body ]]; then
        mapfile -t w < <(printf '%s\n' "$body" | conf_array windows)
        if ((${#w[@]})); then
            PROJ_WINDOWS=("${w[@]}")
        fi
        ws=$(printf '%s\n' "$body" | conf_str workspace)
        if [[ -n $ws ]]; then
            PROJ_WORKSPACE=$ws
        fi
    fi
    # `[scopes]` is its own top-level table — read separately from the flat
    # body above since `section()` only ever returns one named table.
    sc=$(section "$1/.proj.toml" "scopes" | scopes_json)
    if [[ $sc != "{}" ]]; then
        PROJ_SCOPES=$sc
    fi
}

# Writes one project's template fields into the store document: its path
# (re-pointed, so `add` on a moved repo relocates it), windows, workspace
# and scopes — what the repo's own .proj.toml declares, the defaults where
# it says nothing. Dashboard metadata (kind/study/priority) is kept for a
# project already there and defaulted for a new one.
fold_project() { # $1 = document, $2 = name, $3 = path -> new document on stdout
    local doc=$1 name=$2 path=$3 windows_json workspace_json
    load_project_conf "$path"
    windows_json=$(printf '%s\n' "${PROJ_WINDOWS[@]}" | jq -R . | jq -sc .)
    workspace_json=$(printf '%s' "$PROJ_WORKSPACE" | jq -R .)
    printf '%s' "$doc" | jq -c \
        --arg n "$name" --arg p "$path" \
        --argjson w "$windows_json" --argjson ws "$workspace_json" --argjson sc "${PROJ_SCOPES}" '
    .projects[$n] = (
      (.projects[$n] // {kind: "repo", study: false, priority: 5})
      + {path: $p, windows: $w, workspace: $ws, scopes: $sc}
    )'
}

# ,proj.sh add <name> [path]: the one deliberate way a project enters the
# store. No scan runs anywhere in this script — a directory is a project
# because someone named it one, so the picker's list stays exactly as long
# as the person tending the store wants it.
add() { # $1 = name, $2 = path (default: $PWD)
    command -v jq >/dev/null 2>&1 || die "add: jq is required"
    local name=${1:?add: project name required}
    local path=${2:-$PWD}
    if command -v readlink >/dev/null 2>&1; then
        path=$(readlink -f "$path") || true
    fi
    if [[ ! -d $path ]]; then
        die "add: not a directory, no project was added: $path"
    fi
    fold_project "$(store_read)" "$name" "$path" | jq . | store_write
    printf 'add: %s -> %s\n' "$name" "$path"
}

# Refreshes every project already in the store from its own .proj.toml
# (windows/workspace/scopes rewritten; kind/study/priority untouched). It
# discovers nothing: a directory that was never added stays invisible, and
# an entry whose path no longer resolves is reported — never pruned — so a
# human decides whether to drop it (`,proj.sh drop <name>`).
sync() {
    command -v jq >/dev/null 2>&1 || die "sync: jq is required"
    local doc name path refreshed=0 stale=0
    local -a names=()
    doc=$(store_read)
    mapfile -t names < <(printf '%s' "$doc" | jq -r '.projects | keys[]')
    for name in "${names[@]}"; do
        path=$(printf '%s' "$doc" | jq -r --arg n "$name" '.projects[$n].path // empty')
        if [[ -z $path ]]; then
            printf 'sync: %s has no path yet (use: ,proj.sh add %s <path>)\n' "$name" "$name" >&2
            continue
        fi
        if [[ ! -d $path ]]; then
            stale=$((stale + 1))
            printf 'sync: %s -> %s (missing; use: ,proj.sh drop %s)\n' "$name" "$path" "$name" >&2
            continue
        fi
        doc=$(fold_project "$doc" "$name" "$path")
        refreshed=$((refreshed + 1))
    done

    printf '%s\n' "$doc" | jq . | store_write
    printf 'sync: %d refreshed\n' "$refreshed"
}

drop() { # $1 = name — remove one project from the store by hand
    local name=${1:?drop: project name required}
    command -v jq >/dev/null 2>&1 || die "drop: jq is required"
    store_read | jq -c --arg n "$name" 'del(.projects[$n])' | jq . | store_write
}

list() { # name<TAB>path, from the store
    command -v jq >/dev/null 2>&1 || die "list: jq is required"
    store_read | jq -r '.projects | to_entries[] | "\(.key)\t\(.value.path)"' | sort
}

# --- hyprland ---------------------------------------------------------------

# This Hyprland runs a Lua config plugin, and it parses everything handed to
# `hyprctl dispatch` as Lua — classic dispatch strings come back as a syntax
# error, and `hyprctl keyword` is not a request it answers at all. So every
# dispatch below is written as the Lua the plugin expects.
hypr_dispatch() { # $1 = lua expression returning a dispatcher
    command -v hyprctl >/dev/null 2>&1 || return 1
    hyprctl dispatch "$1" >/dev/null
}

# Stamps the launch-time role tag on the window `open` just
# exec'd, e.g. `slot:nvim` on a project's editor window. A bracket exec rule
# ("[tag:+slot:x] cmd") does not apply — Hyprland's exec-rule syntax does not
# carry the general windowrule vocabulary that far (verified live,
# tests/e2e/hq); a dispatch-time `window.tag` by address, once the window
# exists, is the only path that sticks. `$class` is this project's own class
# (`Proj-<name>`, already distinct per project), so within it "the untagged
# one" is unambiguous in the common case of one launch in flight at a time.
# Runs backgrounded — the exec dispatch above returns before the window
# maps, so this polls for it — and `open` must not block a keybind on that
# poll.
# How long `stamp_slot` waits for a launch to map. A kitty window behind
# `uwsm app` and an interactive shell rc is routinely slower than the two
# seconds this used to allow, and a timeout here used to cost the rest of the
# template (see `spawn_missing`), so the budget is generous on purpose.
STAMP_TRIES=160

stamp_slot() { # $1 = class, $2 = role
    local class=$1 role=$2 addr tries
    for ((tries = 0; tries < STAMP_TRIES; tries++)); do
        addr=$(hyprctl clients -j 2>/dev/null | jq -r --arg c "$class" '
            [.[] | select(.class == $c) | select((.tags // []) | map(startswith("slot:")) | any | not)]
            | last | .address // empty')
        if [[ -n $addr ]]; then
            hypr_dispatch "hl.dsp.window.tag({ window = \"address:$addr\", tag = \"+slot:$role\" })"
            return 0
        fi
        sleep 0.05
    done
    return 1
}

# Live, slotted windows of one project: "<role>\t<address>" per line. A
# window with no `slot:` tag yet (still being stamped) counts as no role —
# `open` would rather spawn a possible duplicate for a role it briefly can't
# see than skip a role that really is missing.
live_windows() { # $1 = class -> "<slot>\t<address>" per live, slotted window
    hyprctl clients -j 2>/dev/null | jq -r --arg c "$1" '
    .[] | select(.class == $c) as $w
    | ($w.tags // []) | map(select(startswith("slot:")))[]?
    | sub("^slot:"; "") + "\t" + $w.address'
}

# Escapes a shell command for embedding in a Lua double-quoted string.
lua_str() {
    local v=$1
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    printf '%s' "$v"
}

focused_class() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    local class
    class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
    [[ -n $class ]] || return 1
    printf '%s\n' "$class"
}

# Focus one window, and make it stick. A focus dispatch can land after
# whatever the caller does next re-steals it, so this re-asserts until the
# window is actually the active one.
focus_window() { # $1 = address
    local i active
    for ((i = 0; i < 10; i++)); do
        hypr_dispatch "hl.dsp.focus({ window = \"address:$1\" })" || return 1
        active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
        [[ $active == "$1" ]] && return 0
        sleep 0.05
    done
    return 1
}

# The address of the window this process is itself running inside. Not
# `$PPID`-based: Hyprland is a subreaper, so a `kitty -e` child is reparented
# to the compositor itself the moment kitty's own launch wrapper exits,
# leaving `$PPID` naming Hyprland, not kitty (verified live) — no pid link
# back to "which client is this" survives that. So this reads `activewindow`
# and checks it against OUR OWN class — `class_for picker` is a fixed, known
# literal, so "the focused window is the picker" is unambiguous.
#
# Call this only AFTER the picker's fzf has returned a choice, never before
# it paints: by then the user has typed into this very window, so focus has
# demonstrably settled here and one read answers. Called up front instead it
# would have to poll against focus still in transit, and those round-trips
# are latency the user spends staring at an empty picker. The few retries
# below cover only a compositor that has not caught up within a frame.
own_window_address() {
    local class tries addr
    class=$(class_for picker)
    for ((tries = 0; tries < 5; tries++)); do
        addr=$(hyprctl activewindow -j 2>/dev/null | jq -r --arg c "$class" 'select(.class == $c) | .address // empty')
        if [[ -n $addr ]]; then
            printf '%s\n' "$addr"
            return 0
        fi
        sleep 0.05
    done
    return 1
}

# The picker window closing (kitty's own close-on-child-exit, once `pick`
# returns) is itself a background group member closing, and that can steal
# focus back from the window `open`/`scope_open` just focused even though
# `focus_window` above already confirmed it stuck first — verified live,
# tests/e2e/scenarios/97_project_picker.sh. `focus_window`'s own reassert
# loop cannot cover this: it runs and returns before the picker's window is
# gone, and the picker process is dead the moment its window closes, so
# nothing left inside `,proj.sh` can react to the close itself. The caller
# starts this via `setsid $SELF _reassert-focus ...` rather than a plain
# backgrounded `&` job: a bare `&` still shares the picker's controlling
# terminal, and the pty hangup from the picker's own window closing
# (SIGHUP) killed it right when it needed to still be waiting (verified
# live) — `setsid` gives it its own session before that signal can reach
# it. This function itself just waits for the picker's address to actually
# leave `hyprctl clients`, then re-asserts focus once more.
reassert_focus_after_picker_closes() { # $1 = picker's own address, $2 = target address
    local picker_addr=$1 addr=$2 tries
    [[ -n $addr ]] || return 0
    # Not knowing which window the picker was is not a reason to skip the
    # re-assert: `own_window_address` comes back empty whenever focus has
    # already moved off the picker, and treating that as "nothing to do" is
    # exactly the case where focus ends up somewhere the user did not ask
    # for. Without an address to watch, wait a beat for the picker's own
    # close to settle and then assert anyway -- `focus_window` re-asserts on
    # its own, so a slightly early first attempt costs nothing.
    if [[ -z $picker_addr ]]; then
        sleep 0.3
        focus_window "$addr"
        return 0
    fi
    for ((tries = 0; tries < 40; tries++)); do
        if hyprctl clients -j 2>/dev/null | jq -e --arg a "$picker_addr" \
            '[.[] | select(.address == $a)] | length == 0' >/dev/null 2>&1; then
            focus_window "$addr"
            return 0
        fi
        sleep 0.05
    done
}

# The live address of a project's <role> window (or its template's first,
# same default `open` uses), waiting a bounded beat for a spawn that is
# still mapping — the exec dispatch returns long before the window does, so
# a picker needs this to name what it just asked for. Nonzero when the role
# never shows: no address, no reassert-focus dance scheduled.
current_role_address() { # $1 = project name, $2 = window (role), optional
    local name=$1 window=${2-} class addr tries
    class=$(class_for "$name")
    local -a windows=()
    mapfile -t windows < <(store_project "$name" | jq -r '.windows[]')
    if ((${#windows[@]} == 0)); then
        windows=("${TEMPLATE_WINDOWS[@]}")
    fi
    window=${window:-${windows[0]}}
    for ((tries = 0; tries < 40; tries++)); do
        addr=$(live_windows "$class" | awk -F'\t' -v r="$window" '$1 == r { print $2; exit }')
        if [[ -n $addr ]]; then
            printf '%s\n' "$addr"
            return 0
        fi
        sleep 0.05
    done
    return 1
}

# --- window template ---------------------------------------------------------

# nvim gets a control socket (see the header comment on nvim quitting) and
# yazi IS the tab it opens (quitting yazi ends the window, the way a file
# manager tab ends); every other role opens a plain shell for the user to
# run something in.
nvim_sock_for() { printf '%s/%s.sock\n' "$NVIM_SOCK_DIR" "$1"; } # $1 = class

window_command() { # $1 = role, $2 = class, $3 = path -> the command, or nothing
    if [[ $1 == nvim ]]; then
        mkdir -p "$NVIM_SOCK_DIR"
        local sock
        sock=$(nvim_sock_for "$2")
        rm -f "$sock"
        printf '%s -ic %s\n' "$(printf '%q' "$SHELL")" \
            "$(printf '%q' "nvim --listen $(printf '%q' "$sock") .")"
        return 0
    fi
    if [[ $1 == yazi ]]; then
        printf 'yazi\n'
    fi
    return 0
}

# Execs one project window for the given role, on `workspace`. Does not tag
# it — see `spawn_missing` for why stamping is never backgrounded per-window.
spawn_window() { # $1 = class, $2 = role, $3 = path, $4 = workspace, $5 = explicit command (a scope's own; unset uses window_command's template rule)
    local class=$1 role=$2 path=$3 workspace=$4 explicit=${5-} cmd launch_cmd
    cmd=${explicit:-$(window_command "$role" "$class" "$path")}
    launch_cmd="kitty --class $(printf '%q' "$class") --directory $(printf '%q' "$path")"
    if [[ -n $cmd ]]; then
        launch_cmd="$launch_cmd -e $(printf '%q' "$SHELL") -c $(printf '%q' "$cmd")"
    fi
    if command -v uwsm >/dev/null 2>&1; then
        launch_cmd="uwsm app -- $launch_cmd"
    fi
    if command -v hyprctl >/dev/null 2>&1; then
        launch_cmd="[workspace name:$workspace] $launch_cmd"
        hypr_dispatch "hl.dsp.exec_cmd(\"$(lua_str "$launch_cmd")\")"
        return 0
    fi
    exec "$SHELL" -c "$launch_cmd"
}

# Spawns every role in "$@" and tags each one before the next is spawned —
# `stamp_slot` picks "the untagged one of this class", which is only
# unambiguous with at most one untagged window in flight at a time. Opening
# several missing roles in the same `open` call used to background a
# `stamp_slot` per spawn, and two windows racing to map at once could both
# still be untagged when the second poll ran, so one window got both tags
# and the other got none (caught live in tests/e2e/scenarios/95_project_group.sh,
# not by the shell-level test, which never spawns two roles close enough
# together to race). Run as one background job so a keybind still never
# blocks, but the spawns inside it are strictly one-at-a-time.
#
# A stamp that times out must not take the rest of the template with it: this
# script runs under `set -e`, so the bare `stamp_slot` call this loop used to
# make aborted the whole subshell the first time a window was slow to map —
# a project opened two of its four windows and the user saw a half-built
# group (caught live: two `Proj-hypr` windows, the second carrying no
# `slot:` tag at all). The failure is recorded and the loop goes on, and
# `reconcile_slots` below gives the untagged window its role afterwards.
spawn_missing() { # $1 = class, $2 = path, $3 = workspace, $4 = role to land on ("" for none), roles...
    local class=$1 path=$2 workspace=$3 land=$4
    shift 4
    local role
    local -a unstamped=()
    for role in "$@"; do
        spawn_window "$class" "$role" "$path" "$workspace"
        if ! stamp_slot "$class" "$role"; then
            unstamped+=("$role")
        fi
    done
    ((${#unstamped[@]})) && reconcile_slots "$class" "${unstamped[@]}"
    # Focus once, at the end, on the tab that was actually asked for. The
    # windows themselves map unfocused (`project-window-no-steal` in
    # hypr/windowrules.lua): a project opens because a PROJECT was asked for,
    # and letting each terminal take focus as it maps drags the keyboard
    # along behind the spawn order and leaves it wherever the last one landed.
    if [[ -n $land ]]; then
        local addr
        addr=$(live_windows "$class" | awk -F'\t' -v r="$land" '$1 == r { print $2; exit }')
        [[ -n $addr ]] && focus_window "$addr"
    fi
    return 0
}

# Give a role to every window of `class` that mapped too late for its own
# `stamp_slot` to catch it. Untagged windows are taken in the order Hyprland
# lists them and matched against the roles that never got stamped, so a
# template whose windows all arrive late still ends up fully slotted rather
# than invisible to `live_windows` (and so respawned on the next `open`).
reconcile_slots() { # $1 = class, roles...
    local class=$1
    shift
    local -a pending=("$@") addrs=()
    local tries
    for ((tries = 0; tries < STAMP_TRIES; tries++)); do
        mapfile -t addrs < <(hyprctl clients -j 2>/dev/null | jq -r --arg c "$class" '
            .[] | select(.class == $c)
            | select((.tags // []) | map(startswith("slot:")) | any | not)
            | .address')
        ((${#addrs[@]} >= ${#pending[@]})) && break
        sleep 0.05
    done
    local i=0 addr
    for addr in "${addrs[@]}"; do
        ((i < ${#pending[@]})) || break
        hypr_dispatch "hl.dsp.window.tag({ window = \"address:$addr\", tag = \"+slot:${pending[i]}\" })"
        ((i++))
    done
}

# open <name> [window]: spawns whatever the template says is missing, then
# focuses the requested window (or the template's first) — a Hyprland
# `[workspace name:...]` exec already brings the workspace and its group
# forward, so a fresh project needs no extra focus call; a project that was
# already fully open does.
open() { # $1 = project name, $2 = window (role) to land on
    local name=${1:?open: project name required} window=${2-}
    local path class workspace
    path=$(store_field "$name" '.path')
    [[ -n $path ]] || die "open: no such project in the store: $name (try: ,proj.sh sync)"
    [[ -d $path ]] || die "open: $name's path no longer exists: $path"
    workspace=$(store_field "$name" '.workspace')
    workspace=${workspace:-$DEFAULT_WORKSPACE}
    class=$(class_for "$name")

    local -a windows=()
    mapfile -t windows < <(store_project "$name" | jq -r '.windows[]')
    ((${#windows[@]})) || windows=("${TEMPLATE_WINDOWS[@]}")
    window=${window:-${windows[0]}}

    local -A live=()
    local role addr
    while IFS=$'\t' read -r role addr; do
        [[ -n $role ]] && live[$role]=$addr
    done < <(live_windows "$class")

    local -a missing=()
    for role in "${windows[@]}"; do
        [[ -z ${live[$role]-} ]] && missing+=("$role")
    done

    if ((${#missing[@]})); then
        # Backgrounded on purpose: a keybind must not block on the spawn and
        # tag polls. The `[workspace ...]` exec prefix still brings the
        # workspace forward; focus is `spawn_missing`'s last act, on the role
        # that was asked for, once the template has finished arriving.
        (spawn_missing "$class" "$path" "$workspace" "$window" "${missing[@]}" &)
        return 0
    fi

    # Nothing was missing: the project was already fully open, so this is a
    # "take me there", not "give me another window" — focus the requested
    # slot if it is already live.
    if [[ -n ${live[$window]-} ]]; then
        focus_window "${live[$window]}"
    fi
}

# open-one <name> <window>: exactly ONE template window, never the whole
# template (`open` completes; this is the single-tab gesture) — focus it
# when it is already live, otherwise spawn it into the project's group and
# tag it. Backgrounded like `scope_open` so a keybind never blocks on the
# tag poll; `pick-window` (terminal-side) waits for the address itself when
# it needs it for the reassert-focus dance.
open_one() { # $1 = project name, $2 = window (role)
    local name=${1:?open-one: project name required}
    local role=${2:?open-one: window role required}
    local path class workspace addr known=0 w
    path=$(store_field "$name" '.path')
    [[ -n $path ]] || die "open-one: no such project in the store: $name (try: ,proj.sh add $name <path>)"
    [[ -d $path ]] || die "open-one: $name's path no longer exists: $path"
    class=$(class_for "$name")

    local -a windows=()
    mapfile -t windows < <(store_project "$name" | jq -r '.windows[]')
    if ((${#windows[@]} == 0)); then
        windows=("${TEMPLATE_WINDOWS[@]}")
    fi
    for w in "${windows[@]}"; do
        if [[ $w == "$role" ]]; then
            known=1
            break
        fi
    done
    if ((known == 0)); then
        die "open-one: $name's template has no '$role' window (has: ${windows[*]})"
    fi

    addr=$(live_windows "$class" | awk -F'\t' -v r="$role" '$1 == r { print $2; exit }')
    if [[ -n $addr ]]; then
        focus_window "$addr"
        return 0
    fi
    workspace=$(store_field "$name" '.workspace')
    workspace=${workspace:-$DEFAULT_WORKSPACE}
    (
        spawn_window "$class" "$role" "$path" "$workspace"
        stamp_slot "$class" "$role"
    ) &
}

# --- picker -------------------------------------------------------------

# `confirm`'s non-tty yes/no prompt. A terminal, not a layer surface — see
# the historical note this replaces: a layer surface has no window to place,
# a window is placed by the ordinary project window rule and closing it
# returns focus the normal way.
menu() { # $1 = prompt, choices on stdin -> the chosen line on stdout
    local items out rc
    items=$(mktemp) || return 1
    out=$(mktemp) || return 1
    cat >"$items"
    kitty --class "$(class_for confirm)" --title "$1" \
        -o confirm_os_window_close=0 \
        -e "$SHELL" -ic "fzf --prompt='$1 ' --reverse --no-preview --height=100% <$items >$out" \
        >/dev/null 2>&1 || true
    rc=1
    if [[ -s $out ]]; then
        cat "$out"
        rc=0
    fi
    rm -f "$items" "$out"
    return "$rc"
}

FZF_PICK_OPTS=(--prompt=" Project " --reverse --no-preview --height=100%)

# Every project that has at least one live window right now, one per line.
# A project IS its windows, so "open" is a question for the compositor, not
# for any remembered set.
open_projects() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl clients -j 2>/dev/null | jq -r --arg p "$CLASS_PREFIX" '
        .[] | .class | select(startswith($p)) | ltrimstr($p)' | sort -u
}

# The picker opens projects; it does not switch between the ones already
# open. Those are on the bar, which shows what is running and which is
# focused, and clicking one is how you go to it -- so listing them here as
# well would be offering the same thing twice, and the list a picker is most
# useful with is the one it can actually act on.
fzf_pick() {
    local open
    open=$(open_projects)
    # Plain if/else, not `A && B || C`: `grep -Fxv` exits 1 when it prints
    # nothing, which is exactly the case where EVERY project is already open
    # — and the `|| cat` fallback then listed all of them unfiltered, the one
    # situation the filter exists for.
    if [[ -n $open ]]; then
        list | cut -f1 | grep -Fxv -f <(printf '%s\n' "$open") | fzf "${FZF_PICK_OPTS[@]}"
    else
        list | cut -f1 | fzf "${FZF_PICK_OPTS[@]}"
    fi
}

# One inline-picker spawner for every picker (project, scope, window): one
# kitty window classed `Proj-picker`, running `$SELF <subcmd> --inline <args>`
# whose fzf IS that window's first screen. Floating needs no picker-specific
# code: the `code` scene groups one literal `Proj-<name>` block per project,
# so `Proj-picker` matches none of them — `hypr/scene/strays.lua` floats any
# window whose class matches no block on a `strays = "float"` scene, sized a
# fraction of the monitor and centered, outside every project group. Nothing
# here asks for that, and nothing must: a picker that joined a project's
# group would reorder its tabs while it is only a prompt. (The nested e2e's
# `code` fixture declares the same shape, so 97_project_picker.sh pins this.)
#
# Closing cleanly is not quite as free: the caller dispatches focus to the
# chosen window and `focus_window` confirms it stuck, but kitty then closes
# the picker window once its own shell exits, and closing that window can
# still steal focus back even though it was never the active one — verified
# live, this was NOT a race (`focus_window`'s reassert had already
# succeeded) but a real Hyprland group-close behaviour
# (tests/e2e/scenarios/97_project_picker.sh caught it).
# `reassert_focus_after_picker_closes`, backgrounded and decoupled from the
# picker's own process (which is dead the instant its window closes), waits
# for that close and re-asserts focus once more.
launch_inline() { # $1 = subcommand, $2 = workspace, rest = its inline args
    local sub=$1 workspace=$2
    shift 2
    local pick_cmd launch_cmd arg
    # The picker runs under `$SHELL -ic`, and an interactive shell's startup
    # files can rewrite QF_STORE (the live desk's ~/.zshenv exports it back
    # to $XDG_STATE_HOME/quantum-store), silently pointing every store read
    # inside the picker at a different tree. Hand the store this process
    # resolved down as an env prefix, which the rc cannot reach.
    pick_cmd="QF_STORE=$(printf '%q' "$QF_ROOT") $(printf '%q %q --inline' "$SELF" "$sub")"
    for arg in "$@"; do
        pick_cmd="$pick_cmd $(printf '%q' "$arg")"
    done
    launch_cmd="kitty --class $(printf '%q' "$(class_for picker)")"
    launch_cmd="$launch_cmd -e $(printf '%q' "$SHELL") -ic $(printf '%q' "$pick_cmd")"
    if command -v uwsm >/dev/null 2>&1; then
        launch_cmd="uwsm app -- $launch_cmd"
    fi
    if command -v hyprctl >/dev/null 2>&1; then
        launch_cmd="[workspace name:$workspace] $launch_cmd"
        hypr_dispatch "hl.dsp.exec_cmd(\"$(lua_str "$launch_cmd")\")"
        return 0
    fi
    exec "$SHELL" -c "$launch_cmd"
}

# The FOCUSED project's name (never an explicit argument — every scope/focus
# entry point resolves against whatever project's group is focused right
# now, per LEO-311 chunk D). Dies with a clear message off a project window.
project_of_focused() {
    local class
    class=$(focused_class) || die "no project window focused"
    [[ $class == "$CLASS_PREFIX"* ]] || die "focused window is not a project"
    printf '%s\n' "${class#"$CLASS_PREFIX"}"
}

# Focuses the FOCUSED project's <role>-tagged window (hypr/lib/project.lua's
# Lua-side twin of this; a bind closure calls that directly, this exists for
# scripts/CLI use of the same resolution).
focus_role() { # $1 = role
    local role=${1:?focus: role required} name class addr
    name=$(project_of_focused)
    class=$(class_for "$name")
    addr=$(live_windows "$class" | awk -F'\t' -v r="$role" '$1 == r { print $2; exit }')
    [[ -n $addr ]] || die "focus: $name has no live '$role' window"
    focus_window "$addr"
}

# A project's declared scope command, or empty if it has none by that name.
store_scope_cmd() { # $1 = project name, $2 = scope name
    store_project "$1" | jq -r --arg s "$2" '(.scopes // {})[$s] // empty'
}

# Every declared scope name of a project, one per line.
store_scope_names() { # $1 = project name
    store_project "$1" | jq -r '.scopes // {} | keys[]'
}

# A project's declared scopes that are not already open: same rule as the
# project picker, one level down. A live scope is a tab you reach with the
# project's own keys, not something to spawn a second time.
unopened_scope_names() { # $1 = project name
    local name=$1 class live
    class=$(class_for "$name")
    live=$(live_windows "$class" | cut -f1 | sort -u)
    # Same reason as `fzf_pick`: an empty grep result is exit 1, not a reason
    # to fall back to the unfiltered list.
    if [[ -n $live ]]; then
        store_scope_names "$name" | grep -Fxv -f <(printf '%s\n' "$live")
    else
        store_scope_names "$name"
    fi
}

# Opens the FOCUSED project's declared scope <name>: focuses it if a
# `slot:<name>` window is already live, otherwise spawns it with the scope's
# own command and tags it — joining the group by construction, since it
# shares the project's class. Runs backgrounded (like `spawn_missing`) so a
# keybind never blocks on the tag poll.
scope_open() { # $1 = project name, $2 = scope name
    local name=$1 scope=$2 class cmd path workspace addr
    class=$(class_for "$name")
    cmd=$(store_scope_cmd "$name" "$scope")
    [[ -n $cmd ]] || die "scope: $name has no declared scope '$scope'"
    addr=$(live_windows "$class" | awk -F'\t' -v r="$scope" '$1 == r { print $2; exit }')
    if [[ -n $addr ]]; then
        focus_window "$addr"
        return 0
    fi
    path=$(store_field "$name" '.path')
    workspace=$(store_field "$name" '.workspace')
    workspace=${workspace:-$DEFAULT_WORKSPACE}
    (
        spawn_window "$class" "$scope" "$path" "$workspace" "$cmd"
        stamp_slot "$class" "$scope"
        # A scope window maps unfocused like every other project window
        # (`project-window-no-steal`), and this one WAS asked for by name, so
        # it is focused here rather than left for the user to go and find.
        addr=$(live_windows "$class" | awk -F'\t' -v r="$scope" '$1 == r { print $2; exit }')
        [[ -n $addr ]] && focus_window "$addr"
    ) &
}

# fzf, inline, over one project's declared scopes — the same "this process
# IS the picker window" shape as the project picker (`pick`), except the
# project name is resolved and handed down BEFORE the picker window spawns
# and steals focus, since by the time it exists the focused window has
# already changed.
launch_inline_scope_picker() { # $1 = project name
    launch_inline pick-scope "$DEFAULT_WORKSPACE" "$1"
}

pick_scope() { # $1 = project name (resolved by the caller, before the picker spawned)
    local name=${1:?pick-scope: project name required} choice own_addr addr
    choice=$(unopened_scope_names "$name" | fzf "${FZF_PICK_OPTS[@]}" --prompt="$name scope ") || exit 0
    [[ -n $choice ]] || exit 0
    # Before `scope_open` moves focus off this window — see `own_window_address`.
    own_addr=$(own_window_address) || true
    scope_open "$name" "$choice"
    # A live scope answers at once; a fresh spawn is still mapping, and
    # `current_role_address` waits a bounded beat for it.
    addr=$(current_role_address "$name" "$choice") || addr=""
    if [[ -n $addr ]]; then
        setsid "$SELF" _reassert-focus "${own_addr-}" "$addr" </dev/null >/dev/null 2>&1 &
        disown
    fi
}

# A Hyprland bind, no terminal in sight: resolve the focused project NOW
# (before anything spawns and steals focus), then hand off to a picker
# window that already knows which project it's picking a scope for.
cmd_pick_scope() {
    local name
    name=$(project_of_focused)
    launch_inline_scope_picker "$name"
}

# --- window picker ---------------------------------------------------------

# fzf, inline, over ONE project's template windows — the scope picker's twin,
# one tab at a time instead of `open`'s complete-the-template: the choice is
# handed to `open_one`, which focuses a live window or spawns exactly that
# one. The project name is resolved and handed down before the picker window
# spawns, same as the scope picker.
pick_window() { # $1 = project name (resolved by the caller, before the picker spawned)
    local name=${1:?pick-window: project name required} choice own_addr addr
    local -a windows=()
    mapfile -t windows < <(store_project "$name" | jq -r '.windows[]')
    if ((${#windows[@]} == 0)); then
        windows=("${TEMPLATE_WINDOWS[@]}")
    fi
    choice=$(printf '%s\n' "${windows[@]}" | fzf "${FZF_PICK_OPTS[@]}" --prompt="$name window ") || exit 0
    [[ -n $choice ]] || exit 0
    # Before `open_one` moves focus off this window — see `own_window_address`.
    own_addr=$(own_window_address) || true
    open_one "$name" "$choice"
    # A live window is already focused by `open_one`; a fresh spawn is still
    # mapping, and `current_role_address` waits a bounded beat for it.
    addr=$(current_role_address "$name" "$choice") || addr=""
    if [[ -n $own_addr && -n $addr ]]; then
        setsid "$SELF" _reassert-focus "$own_addr" "$addr" </dev/null >/dev/null 2>&1 &
        disown
    fi
}

# A Hyprland bind, no terminal in sight: resolve the focused project NOW
# (before the picker spawns and steals focus), then hand off to a picker
# window that already knows which project it's picking a template window
# for.
cmd_pick_window() {
    local name workspace
    name=$(project_of_focused)
    workspace=$(store_field "$name" '.workspace')
    launch_inline pick-window "${workspace:-$DEFAULT_WORKSPACE}" "$name"
}

pick() { # $1 = window
    local choice own_addr target inline=0
    if [[ ${INLINE-} == 1 ]]; then
        # This process IS the terminal (`launch_inline` spawned it):
        # fzf is its first screen, so nothing may delay reaching it.
        inline=1
        choice=$(fzf_pick) || exit 0
    elif [[ -t 0 ]]; then
        choice=$(fzf_pick) || exit 0
    else
        # A Hyprland bind, no terminal in sight — hand off to one.
        launch_inline pick "$DEFAULT_WORKSPACE" ${1:+"$1"}
        return
    fi
    [[ -n $choice ]] || exit 0
    # Read this window's own address before `open` moves focus off it, and
    # only now that fzf has returned — see `own_window_address`.
    ((inline)) && { own_addr=$(own_window_address) || true; }
    open "$choice" "${1-}"
    if ((inline)); then
        # A live window's address answers at once; a fresh project's first
        # spawn is still mapping, and `current_role_address` waits for it.
        target=$(current_role_address "$choice" "${1-}") || target=""
        if [[ -n $target ]]; then
            setsid "$SELF" _reassert-focus "${own_addr-}" "$target" \
                </dev/null >/dev/null 2>&1 &
            disown
        fi
    fi
}

# --- teardown -----------------------------------------------------------

# Reachable from a keybind, where there is no tty to prompt on, so the same
# terminal picker stands in. Defaults to "no". 0 = yes, 1 = no, 2 =
# cancelled — escaping a prompt must not be read as "no" and quietly do half
# the thing anyway.
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

# Ask a `slot:nvim` window to quit through its own confirm-quit path instead
# of closing it outright (see the header comment). Returns 0 once the
# window is actually gone, 1 if it is still standing (nvim is showing its
# own prompt, or the user said no) — the caller must never force past a 1.
quit_nvim_window() { # $1 = class, $2 = address
    local class=$1 addr=$2 sock i
    sock=$(nvim_sock_for "$class")
    if [[ -S $sock ]] && command -v nvim >/dev/null 2>&1; then
        nvim --server "$sock" --remote-send '<C-\><C-n>:confirm qa<CR>' 2>/dev/null || true
    fi
    # Give nvim a moment to either exit clean or put its dialog up; either
    # way this never force-closes what it finds still there afterward.
    for ((i = 0; i < 20; i++)); do
        [[ -S $sock ]] || return 0
        sleep 0.1
    done
    hyprctl clients -j 2>/dev/null | jq -e --arg a "$addr" '.[] | select(.address == $a)' \
        >/dev/null 2>&1 || return 0
    return 1
}

# Every project window, name resolved from an explicit argument or the
# focused window's class.
kill_project() { # $1 = project name (optional; defaults to the focused project)
    local name=${1:-$(project_of_focused)}
    confirm "Kill project $name (all its windows)?" || exit 0
    local class
    class=$(class_for "$name")
    local -a blocked=()
    local role addr
    while IFS=$'\t' read -r role addr; do
        [[ -n $addr ]] || continue
        if [[ $role == nvim ]]; then
            quit_nvim_window "$class" "$addr" || {
                blocked+=("$role")
                continue
            }
        else
            # Table form, never `hl.dsp.window.close("address:...")` — a bare
            # string arg is ignored by the Lua plugin (the selector upval ends
            # up nil) and the dispatch closes the FOCUSED window instead,
            # which could take down a live nvim slot right next to the one
            # being spared (AGENTS.md, "Hyprland primitives").
            hypr_dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" || true
        fi
    done < <(live_windows "$class")
    if ((${#blocked[@]})); then
        printf '%s: %s still open — nvim has unsaved changes or is waiting on an answer\n' \
            "${0##*/}" "${blocked[*]}" >&2
    fi
}

case "${1-pick}" in
list) list ;;
add) add "${2-}" "${3-}" ;;
sync) sync ;;
drop) drop "${2-}" ;;
pick)
    shift
    # `--inline`: this process IS the picker window `launch_inline`
    # spawned (`pick_cmd`, above) — re-exec'd here instead of parsed as a
    # project argument.
    if [[ ${1-} == --inline ]]; then
        INLINE=1
        shift
    fi
    pick "${1-}"
    ;;
open)
    shift
    open "${1-}" "${2-}"
    ;;
open-one) open_one "${2-}" "${3-}" ;;
kill) kill_project "${2-}" ;;
focus) focus_role "${2-}" ;;
scope) scope_open "$(project_of_focused)" "${2-}" ;;
pick-window)
    shift
    # `--inline`: this process IS the picker window `cmd_pick_window`
    # spawned — its project name travels as an explicit argument since the
    # focused window has already changed by the time this runs.
    if [[ ${1-} == --inline ]]; then
        shift
        pick_window "${1-}"
    else
        cmd_pick_window
    fi
    ;;
pick-scope)
    shift
    # `--inline`: this process IS the picker window `launch_inline_scope_picker`
    # spawned — its project name travels as an explicit argument since the
    # focused window has already changed by the time this runs.
    if [[ ${1-} == --inline ]]; then
        shift
        pick_scope "${1-}"
    else
        cmd_pick_scope
    fi
    ;;
# Private: `pick`/`pick_scope` below launch this detached (`setsid`) rather
# than call `reassert_focus_after_picker_closes` in a plain backgrounded
# subshell — a bare `&` job still shares the picker's controlling terminal,
# and the pty hangup from the picker's own window closing (SIGHUP) killed it
# right when it needed to still be waiting (verified live). Not a public
# subcommand: it exists only so `setsid $SELF ...` has a fresh process to
# start, detached from that session before it can be hung up.
_reassert-focus) reassert_focus_after_picker_closes "${2-}" "${3-}" ;;
*) die "unknown command: $1" ;;
esac
