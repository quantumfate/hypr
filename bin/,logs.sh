#!/usr/bin/env bash
# ,logs.sh — log groups: one kitty per source, one Hyprland group per group,
# on the `logs` scene.
#
# A log group is a DECLARED GROUP (docs/declared-groups.md), the same object a
# project is: a document names an ordered set of windows, the desk
# instantiates it as one Hyprland group, and a deck column strips the groups
# one at a time. `,proj.sh` is the project front-end; this is the log one, and
# neither knows about the other — a `Log-hypr` and a `Proj-hypr` share a
# suffix because the subject matches, never because anything reads one from
# the other (docs/logs.md, "A log group stands alone").
#
# --- the document ----------------------------------------------------------
#
# Sources come from a repo's own `logs.toml`:
#
#   [sources]
#   build = "just check"
#   unit  = "journalctl --user -u hyprfocus -f"
#
# ...folded into the catalogue ($QF_STORE/logs.json) by `add`, exactly the way
# `,proj.sh add` folds a `.proj.toml`. A group with no repo (a machine, a
# unit, a device) is added with `add <name>` from anywhere and edits its
# sources in the catalogue. Nothing scans: a group exists because someone
# named it one.
#
# --- what a window is ------------------------------------------------------
#
# One kitty per source, classed `Log-<name>` so the scene's block folds them
# into one group, tagged `slot:<source>` at launch so `mod+j/k` walks them in
# the declared order and the bar can name the tab. The tmux-backed `logview`
# (system-config's `zsh` role) is untouched and still the working
# implementation of the fixed journal views; this covers declared sources,
# and docs/logs.md retires tmux only once this has replaced what it did.
#
# --- lifecycle -------------------------------------------------------------
#
# A group ends with its last window. There is no remembered membership set:
# the compositor is the only source for "what is open", the same rule projects
# follow, so closing the last window ends the group and reopening is a
# deliberate gesture.
set -euo pipefail

QF_ROOT="${QF_STORE:-${XDG_STATE_HOME:-$HOME/.local/state}/quantum-store}"
LOGS_JSON="$QF_ROOT/logs.json"
CLASS_PREFIX="Log-"
WORKSPACE=logs
SELF=$(readlink -f "${BASH_SOURCE[0]}")

# Keybind callers have nowhere to write stderr, so a refusal has to be said
# where the user is looking (same reasoning as `,proj.sh`'s `die`).
die() {
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        ,notify log-groups "" "$1" -u critical 2>/dev/null || true
    fi
    exit 1
}

need_jq() { command -v jq >/dev/null 2>&1 || die "jq is required"; }

store_read() {
    if [[ -s $LOGS_JSON ]]; then
        cat "$LOGS_JSON"
    else
        printf '{"groups":{}}\n'
    fi
}

store_write() { # stdin = the whole new document
    mkdir -p "${LOGS_JSON%/*}"
    local tmp
    tmp=$(mktemp "${LOGS_JSON}.XXXXXX")
    cat >"$tmp"
    mv "$tmp" "$LOGS_JSON"
}

group_of() { store_read | jq -c --arg n "$1" '.groups[$n] // empty'; }

# Hyprland matches classes as regex, so a group's class keeps to
# [A-Za-z0-9_-] — same rule `,proj.sh`'s `class_for` follows.
class_for() { printf '%s%s\n' "$CLASS_PREFIX" "${1//[^A-Za-z0-9_-]/_}"; }

# --- the document ----------------------------------------------------------

# `logs.toml` is flat and hand-written, so a line scraper beats a toml parser
# for a handful of keys (the argument `,proj.sh` already makes).
toml_section() { # $1 = file, $2 = table name
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

# "name = command" lines of a [sources] table, as a JSON object.
sources_json() { # section body on stdin
    jq -R -n '[inputs
      | select(test("^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*="))
      | capture("^[[:space:]]*(?<k>[A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*\"(?<v>.*)\"[[:space:]]*$")
      | select(.k != null)]
      | map({key: .k, value: .v}) | from_entries'
}

# --- commands --------------------------------------------------------------

list() {
    need_jq
    store_read | jq -r '.groups | to_entries[] | "\(.key)\t\((.value.sources // {}) | keys | join(","))"' | sort
}

add() { # $1 = name, $2 = path holding logs.toml (default: $PWD)
    need_jq
    local name=${1:?add: a group name is required}
    local path=${2:-$PWD}
    local sources="{}"
    if command -v readlink >/dev/null 2>&1; then
        path=$(readlink -f "$path") || true
    fi
    if [[ -f $path/logs.toml ]]; then
        sources=$(toml_section "$path/logs.toml" "sources" | sources_json)
    fi
    store_read | jq -c --arg n "$name" --arg p "$path" --argjson s "$sources" '
      .groups[$n] = ((.groups[$n] // {}) + {path: $p, sources: $s})' | jq . | store_write
    printf 'add: %s -> %s (%s source(s))\n' "$name" "$path" "$(printf '%s' "$sources" | jq 'length')"
}

drop() { # $1 = name
    need_jq
    local name=${1:?drop: a group name is required}
    store_read | jq -c --arg n "$name" 'del(.groups[$n])' | jq . | store_write
}

# Every live window of one group: "<source>\t<address>" per line, a window
# with no `slot:` tag yet counted as no source (it is still being stamped).
live_windows() { # $1 = class
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl clients -j 2>/dev/null | jq -r --arg c "$1" '
      .[] | select(.class == $c) as $w
      | ($w.tags // []) | map(select(startswith("slot:")))[]?
      | sub("^slot:"; "") + "\t" + $w.address'
}

# Stamp the launch-time role tag on the window just exec'd. Hyprland's exec
# rules do not carry the general windowrule vocabulary that far, so the tag is
# applied after the window maps — the same mechanism, and the same bounded
# wait, `,proj.sh`'s `stamp_slot` uses.
stamp_slot() { # $1 = class, $2 = source
    local class=$1 source=$2 addr tries
    for ((tries = 0; tries < 60; tries++)); do
        addr=$(hyprctl clients -j 2>/dev/null | jq -r --arg c "$class" '
          [.[] | select(.class == $c) | select((.tags // []) | map(startswith("slot:")) | any | not)]
          | first | .address // empty')
        if [[ -n $addr ]]; then
            hyprctl dispatch "hl.dsp.window.tag({ window = \"address:$addr\", tag = \"+slot:$source\" })" >/dev/null
            return 0
        fi
        sleep 0.05
    done
    return 1
}

spawn_source() { # $1 = class, $2 = source, $3 = command, $4 = path
    local class=$1 source=$2 cmd=$3 path=$4 launch
    launch="kitty --class $(printf '%q' "$class") --title $(printf '%q' "$source")"
    [[ -d $path ]] && launch="$launch --directory $(printf '%q' "$path")"
    launch="$launch -e $(printf '%q' "${SHELL:-/bin/sh}") -c $(printf '%q' "$cmd")"
    command -v uwsm >/dev/null 2>&1 && launch="uwsm app -- $launch"
    launch="[workspace name:$WORKSPACE] $launch"
    hyprctl dispatch "hl.dsp.exec_cmd(\"$(printf '%s' "$launch" | sed 's/\\/\\\\/g; s/"/\\"/g')\")" >/dev/null
}

# Spawns every missing source and stamps each before the next: `stamp_slot`
# picks "the untagged window of this class", which is only unambiguous with
# one untagged window in flight. Detached (`setsid`), because the caller is
# often a picker whose own window closes the instant it has a choice — a
# plain background job dies with it and the group opens half-built
# (`,proj.sh` learned this the hard way; docs/declared-groups.md rule 4).
spawn_missing() { # $1 = name, rest = sources
    local name=$1 class path doc source
    shift
    class=$(class_for "$name")
    doc=$(group_of "$name")
    path=$(printf '%s' "$doc" | jq -r '.path // empty')
    for source in "$@"; do
        local cmd
        cmd=$(printf '%s' "$doc" | jq -r --arg s "$source" '.sources[$s] // empty')
        [[ -n $cmd ]] || continue
        spawn_source "$class" "$source" "$cmd" "$path"
        stamp_slot "$class" "$source" || true
    done
    # One act at the end, never a focus dance per window: show the group and
    # land on it (docs/declared-groups.md rule 4).
    local addr
    addr=$(live_windows "$class" | head -1 | cut -f2)
    [[ -n $addr ]] && present_window "$addr"
    return 0
}

# Show the declared group this window belongs to, and focus it. The `logs`
# scene is a deck, so the group may be parked and a bare focus dispatch at a
# parked window does nothing at all: the engine scrolls its column and brings
# the whole thing home first.
present_window() { # $1 = address
    command -v hyprctl >/dev/null 2>&1 || return 1
    local shown
    shown=$(hyprctl eval "return tostring(require('hypr.scene.deck_provider').present('$1'))" 2>/dev/null) || shown=""
    case "$shown" in
    *true*) return 0 ;;
    esac
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null
}

open() { # $1 = group name, $2 = one source (optional)
    need_jq
    local name=${1:?open: a group name is required} want=${2-} class doc
    doc=$(group_of "$name")
    [[ -n $doc ]] || die "no such log group: $name (try: ,logs.sh add $name)"
    class=$(class_for "$name")

    local -A live=()
    local source addr
    while IFS=$'\t' read -r source addr; do
        [[ -n $source ]] && live[$source]=$addr
    done < <(live_windows "$class")

    local -a wanted=()
    if [[ -n $want ]]; then
        wanted=("$want")
    else
        mapfile -t wanted < <(printf '%s' "$doc" | jq -r '.sources | keys[]')
    fi
    ((${#wanted[@]})) || die "$name declares no sources (edit its logs.toml, then: ,logs.sh add $name)"

    local -a missing=()
    for source in "${wanted[@]}"; do
        [[ -z ${live[$source]-} ]] && missing+=("$source")
    done

    if ((${#missing[@]})); then
        if command -v setsid >/dev/null 2>&1; then
            setsid "$SELF" _spawn-missing "$name" "${missing[@]}" </dev/null >/dev/null 2>&1 &
        else
            "$SELF" _spawn-missing "$name" "${missing[@]}" </dev/null >/dev/null 2>&1 &
        fi
        disown
        return 0
    fi
    # Already open: this is "take me there", not "give me another window".
    present_window "${live[${wanted[0]}]}"
}

# Every group with at least one live window right now. A group IS its
# windows, so "open" is a question for the compositor, never a remembered set.
open_groups() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl clients -j 2>/dev/null | jq -r --arg p "$CLASS_PREFIX" '
      .[] | .class | select(startswith($p)) | ltrimstr($p)' | sort -u
}

FZF_OPTS=(--prompt=" Logs " --reverse --no-preview --height=100%)

# The picker offers what is NOT open: the bar is the way back to a group that
# already is, so the two never present the same choice twice (`,proj.sh`'s
# rule, and for the same reason).
fzf_pick() {
    local open_now
    open_now=$(open_groups)
    if [[ -n $open_now ]]; then
        list | cut -f1 | grep -Fxv -f <(printf '%s\n' "$open_now") | fzf "${FZF_OPTS[@]}"
    else
        list | cut -f1 | fzf "${FZF_OPTS[@]}"
    fi
}

# The workspace a picker opens on: the one you pressed the key in, falling
# back to the logs workspace itself off a compositor or on a special.
current_workspace() {
    local name
    command -v hyprctl >/dev/null 2>&1 || {
        printf '%s\n' "$WORKSPACE"
        return 0
    }
    name=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.name // empty')
    case "$name" in
    "" | special:*) printf '%s\n' "$WORKSPACE" ;;
    *) printf '%s\n' "$name" ;;
    esac
}

pick() {
    need_jq
    local choice
    if [[ ${INLINE-} == 1 || -t 0 ]]; then
        choice=$(fzf_pick) || exit 0
        [[ -n $choice ]] || exit 0
        open "$choice"
        return 0
    fi
    # A keybind, no terminal in sight: hand off to one whose first screen IS
    # fzf, the same inline-picker shape `,proj.sh` uses.
    local pick_cmd launch
    pick_cmd="QF_STORE=$(printf '%q' "$QF_ROOT") $(printf '%q pick --inline' "$SELF")"
    launch="kitty --class $(printf '%q' "$(class_for picker)") -e $(printf '%q' "${SHELL:-/bin/sh}") -ic $(printf '%q' "$pick_cmd")"
    command -v uwsm >/dev/null 2>&1 && launch="uwsm app -- $launch"
    launch="[workspace name:$(current_workspace)] $launch"
    hyprctl dispatch "hl.dsp.exec_cmd(\"$(printf '%s' "$launch" | sed 's/\\/\\\\/g; s/"/\\"/g')\")" >/dev/null
}

kill_group() { # $1 = group name (default: the focused one)
    need_jq
    local name=${1-} class addr
    if [[ -z $name ]]; then
        name=$(hyprctl activewindow -j 2>/dev/null | jq -r --arg p "$CLASS_PREFIX" '
          .class // "" | select(startswith($p)) | ltrimstr($p)')
    fi
    [[ -n $name ]] || die "kill: no log group named, and the focused window is not one"
    class=$(class_for "$name")
    # The table form: `hl.dsp.window.close("address:x")` ignores its argument
    # and closes the FOCUSED window instead (AGENTS.md, "Hyprland primitives").
    while read -r addr; do
        [[ -n $addr ]] && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null
    done < <(hyprctl clients -j 2>/dev/null | jq -r --arg c "$class" '.[] | select(.class == $c) | .address')
}

case "${1-pick}" in
list) list ;;
add) add "${2-}" "${3-}" ;;
drop) drop "${2-}" ;;
open) open "${2-}" "${3-}" ;;
pick)
    if [[ ${2-} == --inline ]]; then
        INLINE=1 pick
    else
        pick
    fi
    ;;
kill) kill_group "${2-}" ;;
# Private: `open` starts this detached so a group outlives the picker window
# that asked for it.
_spawn-missing)
    shift
    spawn_missing "$@"
    ;;
*) die "unknown command: $1" ;;
esac
