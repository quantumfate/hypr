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
# from there at runtime. The store is the source of truth; it is no longer a
# metadata sidecar next to a filesystem scan. `sync` is the only thing that
# still scans (the tms config's project roots + bookmarks, same definition
# tms itself uses, plus each project's `.proj.toml`) — it populates the
# store, it is not consulted on every `open`/`pick`/`list`. Run it after
# adding, moving or renaming a repo, or after editing a `.proj.toml`:
#
#   ,proj.sh sync
#
# Each window carries the class `Proj-<name>` (Hyprland matches classes as
# regex, kept to [A-Za-z0-9_-]) plus a launch-time role tag (`slot:nvim`,
# `slot:zsh`, `slot:run`, stamped by `stamp_slot`) so a
# reopen can tell which template windows are already live.
#
#   ,proj.sh pick [window]        fzf over the store's projects: a kitty
#                                 window whose first screen IS fzf when
#                                 there is no terminal to run it in already
#                                 (--inline: this process IS that window,
#                                 used internally to re-exec into it)
#   ,proj.sh open <name> [window] open a project by its store name, or
#                                 focus/complete it if some of its windows
#                                 are already open
#   ,proj.sh list                 name<TAB>path, one per line, from the store
#   ,proj.sh sync                 rescan the tms roots + bookmarks and
#                                 .proj.toml, and write path/windows/
#                                 workspace into the store (metadata fields —
#                                 kind/study/priority — are left alone)
#   ,proj.sh kill [name]          close every window of a project (the
#                                 focused one if name is omitted); a window
#                                 running nvim is asked to quit gracefully
#                                 (see "nvim" below) and is never force-closed
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
TMS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/tms/config.toml"
TEMPLATE_WINDOWS=(nvim zsh run)
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
        ,notify proj -u critical "" "$1" 2>/dev/null || true
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

# --- toml (used only by `sync`) ------------------------------------------

# tms's toml is flat and hand-written, so a line scraper beats a toml parser
# here — no extra runtime dependency for a handful of keys.

section() { # $1 = file, $2 = table name, e.g. "projects.foo" ("" = top level)
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

# The project scan: a project is a git repo under one of tms's roots (its own
# definition, so tms and this stay in agreement), plus its bookmarks — the
# same rule `,proj.sh` used before the store existed. Only `sync` calls this
# now; nothing on the `open`/`pick`/`list` path scans the filesystem.
scan() {
    local -a excludes=()
    local dir
    while read -r dir; do
        # ".git" is in tms's exclude list, but it is exactly what the scan
        # matches on — excluding it would find nothing.
        if [[ -n $dir && $dir != .git ]]; then
            excludes+=(--exclude "$dir")
        fi
    done < <(toml_array excluded_dirs)

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

# name<TAB>path for every repo the scan finds, deduping basenames the same
# way the pre-store scan did (parent/name once a basename collides).
scan_named() {
    scan | sed 's:/*$::' | sort -u | awk -F/ '
    { name[NR] = $NF; path[NR] = $0; parent[NR] = $(NF-1); n = NR }
    END {
      for (i = 1; i <= n; i++) count[name[i]]++
      for (i = 1; i <= n; i++)
        printf "%s\t%s\n", (count[name[i]] > 1 ? parent[i] "/" name[i] : name[i]), path[i]
    }' | sort
}

# Rescans and writes path/windows/workspace into the store, one project at a
# time. Dashboard metadata (kind/study/priority) is left untouched for a
# project already in the store, and defaulted for one that is new. Nothing
# is ever removed here: a repo the scan no longer finds just keeps its last
# known path, which `sync`'s own report below flags as stale so a human
# decides whether to drop it (`,proj.sh drop <name>`).
sync() {
    command -v jq >/dev/null 2>&1 || die "sync: jq is required"
    local doc name path added=0 updated=0 stale=0
    doc=$(store_read)
    while IFS=$'\t' read -r name path; do
        [[ -n $name && -n $path ]] || continue
        load_project_conf "$name" "$path"
        local windows_json workspace_json existing
        windows_json=$(printf '%s\n' "${PROJ_WINDOWS[@]}" | jq -R . | jq -sc .)
        workspace_json=$(printf '%s' "$PROJ_WORKSPACE" | jq -R .)
        existing=$(printf '%s' "$doc" | jq -c --arg n "$name" '.projects[$n] // empty')
        if [[ -z $existing ]]; then
            added=$((added + 1))
        else
            updated=$((updated + 1))
        fi
        doc=$(printf '%s' "$doc" | jq -c \
            --arg n "$name" --arg p "$path" \
            --argjson w "$windows_json" --argjson ws "$workspace_json" '
        .projects[$n] = (
          (.projects[$n] // {kind: "repo", study: false, priority: 5})
          + {path: $p, windows: $w, workspace: $ws}
        )')
    done < <(scan_named)

    # Report (never prune): a stored project whose path no longer resolves.
    local stale_names=""
    while read -r name; do
        path=$(printf '%s' "$doc" | jq -r --arg n "$name" '.projects[$n].path')
        if [[ ! -d $path ]]; then
            stale=$((stale + 1))
            stale_names="$stale_names  $name -> $path (missing)\n"
        fi
    done < <(printf '%s' "$doc" | jq -r '.projects | keys[]')

    printf '%s\n' "$doc" | jq . | store_write
    printf 'sync: %d added, %d updated\n' "$added" "$updated"
    if ((stale > 0)); then
        printf 'sync: %d stale entr%s (path no longer exists — nothing removed automatically):\n' \
            "$stale" "$([[ $stale == 1 ]] && echo y || echo ies)"
        printf '%b' "$stale_names"
    fi
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
stamp_slot() { # $1 = class, $2 = role
    local class=$1 role=$2 addr tries
    for ((tries = 0; tries < 40; tries++)); do
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

# --- window template ---------------------------------------------------------

# nvim gets a control socket (see the header comment on nvim quitting); every
# other role opens a plain shell for the user to run something in.
nvim_sock_for() { printf '%s/%s.sock\n' "$NVIM_SOCK_DIR" "$1"; } # $1 = class

window_command() { # $1 = role, $2 = class, $3 = path -> the command, or nothing
    [[ $1 == nvim ]] || return 0
    mkdir -p "$NVIM_SOCK_DIR"
    local sock
    sock=$(nvim_sock_for "$2")
    rm -f "$sock"
    printf '%s -ic %s\n' "$(printf '%q' "$SHELL")" \
        "$(printf '%q' "nvim --listen $(printf '%q' "$sock") .")"
}

# Execs one project window for the given role, on `workspace`. Does not tag
# it — see `spawn_missing` for why stamping is never backgrounded per-window.
spawn_window() { # $1 = class, $2 = role, $3 = path, $4 = workspace
    local class=$1 role=$2 path=$3 workspace=$4 cmd launch_cmd
    cmd=$(window_command "$role" "$class" "$path")
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
spawn_missing() { # $1 = class, $2 = path, $3 = workspace, roles...
    local class=$1 path=$2 workspace=$3
    shift 3
    local role
    for role in "$@"; do
        spawn_window "$class" "$role" "$path" "$workspace"
        stamp_slot "$class" "$role"
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
        (spawn_missing "$class" "$path" "$workspace" "${missing[@]}" &)
        # A brand-new or partially-spawned project already took the workspace
        # (and with it, focus) via the first spawn's `[workspace ...]` exec
        # prefix — nothing further to do until spawn_missing's tagging lands,
        # which runs backgrounded on purpose.
        return 0
    fi

    # Nothing was missing: the project was already fully open, so this is a
    # "take me there", not "give me another window" — focus the requested
    # slot if it is already live.
    if [[ -n ${live[$window]-} ]]; then
        focus_window "${live[$window]}"
    fi
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

fzf_pick() { list | cut -f1 | fzf "${FZF_PICK_OPTS[@]}"; }

# No terminal at all (a Hyprland bind). Opens exactly one project-classed
# window — `class_for picker` matches the ordinary project rule, so it tiles
# like any other project terminal, no dedicated rule needed — running
# `pick --inline`, whose fzf IS that window's first screen.
launch_inline_picker() { # $1 = window
    local window=${1-} pick_cmd launch_cmd
    pick_cmd=$(printf '%q pick --inline' "$SELF")
    [[ -n $window ]] && pick_cmd="$pick_cmd $(printf '%q' "$window")"
    launch_cmd="kitty --class $(printf '%q' "$(class_for picker)")"
    launch_cmd="$launch_cmd -e $(printf '%q' "$SHELL") -ic $(printf '%q' "$pick_cmd")"
    if command -v uwsm >/dev/null 2>&1; then
        launch_cmd="uwsm app -- $launch_cmd"
    fi
    if command -v hyprctl >/dev/null 2>&1; then
        launch_cmd="[workspace name:$DEFAULT_WORKSPACE] $launch_cmd"
        hypr_dispatch "hl.dsp.exec_cmd(\"$(lua_str "$launch_cmd")\")"
        return 0
    fi
    exec "$SHELL" -c "$launch_cmd"
}

pick() { # $1 = window
    local choice
    if [[ ${INLINE-} == 1 ]]; then
        # This process IS the terminal (`launch_inline_picker` spawned it):
        # fzf is its first screen.
        choice=$(fzf_pick) || exit 0
    elif [[ -t 0 ]]; then
        choice=$(fzf_pick) || exit 0
    else
        # A Hyprland bind, no terminal in sight — hand off to one.
        launch_inline_picker "${1-}"
        return
    fi
    [[ -n $choice ]] || exit 0
    open "$choice" "${1-}"
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
kill_project() { # $1 = project name (optional)
    local name=${1-}
    if [[ -z $name ]]; then
        local class
        class=$(focused_class) || die "kill: no project window focused"
        [[ $class == "$CLASS_PREFIX"* ]] || die "kill: focused window is not a project"
        name=${class#"$CLASS_PREFIX"}
    fi
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
            hypr_dispatch "hl.dsp.window.close(\"address:$addr\")" || true
        fi
    done < <(live_windows "$class")
    if ((${#blocked[@]})); then
        printf '%s: %s still open — nvim has unsaved changes or is waiting on an answer\n' \
            "${0##*/}" "${blocked[*]}" >&2
    fi
}

case "${1-pick}" in
list) list ;;
sync) sync ;;
drop) drop "${2-}" ;;
pick)
    shift
    # `--inline`: this process IS the picker window `launch_inline_picker`
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
kill) kill_project "${2-}" ;;
*) die "unknown command: $1" ;;
esac
