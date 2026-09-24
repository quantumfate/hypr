#!/usr/bin/env bash
# recclip — record a Wayland screen region with gpu-screen-recorder (NVENC),
# then copy the resulting file to the clipboard as text/uri-list (paste as a
# file into Discord, browsers, file managers, chat apps, etc.).
#
# Uses gpu-screen-recorder because wl-screenrec cannot consume the NVIDIA
# proprietary driver's block-linear dmabuf capture formats.
#
# Usage:
#   recclip                 # slurp-select a region, record until Ctrl-C
#   recclip -o [MONITOR]    # record a whole monitor (default: first monitor)
#   recclip -a              # also record system audio (default output)
#   recclip -a mic          # record the microphone (default input) instead
#   recclip -a DEVICE       # record a specific pactl source (see --list-audio-devices)
#   recclip file.mp4        # explicit output path
#   recclip -o DP-1 -a clip.mp4
#
# Stop recording with Ctrl-C. On stop the file is copied to the clipboard.

set -euo pipefail

# Require core dependencies; report every missing one at once.
require() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        local msg="recclip: missing required command(s): ${missing[*]}"
        echo "$msg" >&2
        command -v notify-send >/dev/null 2>&1 &&
            ,notify screen-recorder "Recording copied" "$msg" -u critical || true
        exit 127
    fi
}

require gpu-screen-recorder slurp wl-copy

pidfile="${XDG_RUNTIME_DIR:-/tmp}/recclip.pid"

# Toggle: if a recorder is already running, this invocation stops it.
# SIGINT makes gpu-screen-recorder finalize the file; the recording process
# (still alive, blocked in `wait`) then runs its EXIT trap and copies.
if [ -f "$pidfile" ]; then
    rpid="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "$rpid" ] && kill -0 "$rpid" 2>/dev/null; then
        kill -INT "$rpid"
        exit 0
    fi
    rm -f "$pidfile" # stale
fi

outdir="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"
mkdir -p "$outdir"

file=""
whole=0
monitor=""
audio=""

while [ $# -gt 0 ]; do
    case "$1" in
    -o | --output)
        whole=1
        # optional monitor name follows -o if it's not a filename
        case "${2:-}" in
        "" | *.mp4 | *.mkv | -*) : ;;
        *)
            monitor="$2"
            shift
            ;;
        esac
        ;;
    -a | --audio)
        audio="default_output"
        # optional source follows -a if it's not a filename/flag
        case "${2:-}" in
        "" | *.mp4 | *.mkv | -*) : ;;
        mic)
            audio="default_input"
            shift
            ;;
        *)
            audio="$2"
            shift
            ;;
        esac
        ;;
    *) file="$1" ;;
    esac
    shift
done

[ -n "$file" ] || file="$outdir/rec-$(date +%Y%m%d-%H%M%S).mp4"

# Pick capture target
if [ "$whole" -eq 1 ]; then
    [ -n "$monitor" ] || monitor="$(gpu-screen-recorder --list-monitors 2>/dev/null | head -1 | cut -d'|' -f1)"
    target=(-w "$monitor")
else
    region="$(slurp -f '%wx%h+%x+%y')" || {
        echo "recclip: region selection cancelled" >&2
        exit 1
    }
    target=(-w region -region "$region")
fi

copy_to_clipboard() {
    [ -s "$file" ] || {
        echo "recclip: no output written" >&2
        return
    }
    # text/uri-list wants CRLF-terminated file:// URIs
    printf 'file://%s\r\n' "$file" | wl-copy -t text/uri-list
    echo "recclip: saved $file"
    echo "recclip: copied to clipboard (paste as file)"
    command -v notify-send >/dev/null &&
        ,notify screen-recorder "" "Recording copied to clipboard"$'\n'"$file" || true
}

args=("${target[@]}" -k h264 -f 60 -cursor yes)
[ -n "$audio" ] && args+=(-a "$audio")
args+=(-o "$file")

# Run detached so a later invocation can signal us to stop. The recorder
# finalizes the file on SIGINT; copy afterward. Clean the pidfile on exit.
gpu-screen-recorder "${args[@]}" &
rpid=$!
echo "$rpid" >"$pidfile"
trap 'rm -f "$pidfile"; copy_to_clipboard' EXIT

command -v notify-send >/dev/null &&
    ,notify screen-recorder "" "Recording started — run recclip again to stop" || true

wait "$rpid" || true
