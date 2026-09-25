#!/usr/bin/env bash
# ,theme.sh — one palette, every surface.
#
# Quickshell, Hyprland and nvim watch $XDG_STATE_HOME/theme.json directly and
# react on their own (nvim follows the store's `resolved` palette — the value
# in effect under a mode lease, written beside the baseline `palette` on every
# apply). Everything else — kitty, GTK, Qt, Kvantum, the wallpaper — needs a
# process to poke it, and that is all this script is: the fan-out for the
# surfaces that cannot read a JSON file for themselves.
#
# It is a script rather than a Quickshell service for three reasons: the theme
# has to apply while the shell is restarting, `kitty` and `gsettings` need to be
# executed either way, and a theme you cannot set from a tmux pane at 2am is not
# finished.
#
#   ,theme.sh apply                 fan the current theme.json out to everything
#   ,theme.sh set <palette>         pick a palette (pins mode=manual) and apply
#   ,theme.sh auto                  hand the choice back to the sun and apply
#   ,theme.sh toggle                swap between the day and night palettes
#   ,theme.sh get                   print the resolved palette
#   ,theme.sh wallpaper F [P]       bind a wallpaper to a palette (default: current)
#   ,theme.sh wallpaper list [P]    print the palette's set and each monitor's pick (JSON)
#   ,theme.sh wallpaper next|prev|random [P] [--output NAME]
#                                   cycle the palette's set, shuffled, one pick per monitor
#                                   (only from the subset that fits that monitor's real
#                                   pixel size — see FIT_ASPECT_TOLERANCE/FIT_MIN_SCALE)
#   ,theme.sh status                print what each surface is currently set to
#
# Writes go through the same store the shell uses, so setting a palette here and
# setting it from the bar are the same operation.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The shared quantum-store directory: every state file this desk keeps lives
# under one root the environment names (QF_STORE), so a runtime that migrates
# or relocates its stores does not become a find across $XDG_STATE_HOME.
ROOT="${QF_STORE:-${XDG_STATE_HOME:-$HOME/.local/state}/quantum-store}"
LEGACY="${XDG_STATE_HOME:-$HOME/.local/state}/theme.json"
STATE="$ROOT/theme.json"
RESULT="$ROOT/theme.result.json"
# The mode pointer and the declaration live in the same store the shell keeps
# (the lease is read there, never written — a mode leases, a user points).
LEGACY_FOCUS="${XDG_STATE_HOME:-$HOME/.local/state}/focus.json"
FOCUS="$ROOT/focus.json"
DECLARATION="$ROOT/hyprfocus.json"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wallpapers"

# The accent is a mode-scoped store field, not a hardcoded name: every focus
# mode declares an `accent_role` in `hyprfocus.json`'s `presentation` block
# (the same field `hypr/themes/colors.lua` resolves for window borders), and
# `accent_role()` below reads it for whichever mode currently holds the lease.
# ACCENT is the surface-name role (the installed variant naming scheme, e.g.
# "catppuccin-<palette>-mauve"), which stays mauve — swapping it would mean
# shipping a full icon/GTK/Qt asset set per accent, which nobody has done.
ACCENT="mauve"

PALETTES=(latte frappe macchiato mocha)
# Which flavours are light. Drives GTK's color-scheme, which is a separate
# setting from the theme name and is what applications actually branch on.
LIGHT=(latte)

# `baseline`'s own auto-mode fallbacks (day/night, below) default the sun's
# pair to latte/macchiato — frappe and mocha stay leasable by a mode or a
# manual `set`, but auto's day/night split does not default to them.

die() {
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

# --- the variant registry (LEO-210's harder half) ----------------------------

# Where the packs ship. The shell's own assets are read from the config root,
# so the script reads the same documents the Quickshell singletons do — one
# registry, two readers, no second table to drift apart.
# Where the packs ship. The shell's own assets are read from the config root,
# so the script reads the same documents the Quickshell singletons do — one
# registry, two readers, no second table to drift apart. An override names the
# packs directory itself (the tests use it); unadorned, the deployment shape
# is the config root's assets.
PACKS="${THEME_PACKS_DIR:-}"
if [ -z "$PACKS" ]; then
    candidate="$CONFIG/quickshell/quantumfate/assets/packs"
    [ -d "$candidate" ] && PACKS="$candidate" || PACKS=""
fi

# The pack that owns a variant, and the template it names the variant with on
# a surface. Output is either "" (the pack carries no names for that surface —
# partial coverage, the applier keeps its own shape) or the raw template.
surface_template() {
    local variant=$1 surface=$2 f
    [ -d "$PACKS" ] || return 0
    for f in "$PACKS"/*.json; do
        [ -f "$f" ] || continue
        if jq -e --arg v "$variant" '.variants[$v] != null' "$f" >/dev/null 2>&1; then
            jq -r --arg s "$surface" '.surfaces[$s] // ""' "$f"
            return
        fi
    done
}

# Convert #rrggbb to rgba(r,g,b,a). GTK CSS accepts either form.
hex_to_rgba() {
    local hex=$1 alpha=$2
    hex=${hex#"#"}
    printf 'rgba(%d, %d, %d, %s)' \
        $((16#${hex:0:2})) \
        $((16#${hex:2:2})) \
        $((16#${hex:4:2})) \
        "$alpha"
}

# "#rrggbb" as the decimal "r;g;b" triple SGR colour escapes take, which is
# what the LS_COLORS/EZA_COLORS grammar carries.
hex_to_dec() {
    local hex=${1#\#}
    printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# A ready-made SGR foreground escape, for the termcap variables less reads.
sgr_fg() { # $1 = hex, $2 = optional attribute (bold|underline)
    local attr
    case ${2-} in
    bold) attr='01;' ;;
    underline) attr='04;' ;;
    *) attr='' ;;
    esac
    printf '\033[%s38;2;%sm' "$attr" "$(hex_to_dec "$1")"
}

# `$1` mixed `$3` percent of the way toward `$2`. Diff backgrounds are a tint
# of the flavour's own base rather than a palette colour, so they have to be
# computed per flavour instead of listed.
blend_hex() { # $1 = from hex, $2 = toward hex, $3 = percent
    local a=${1#\#} b=${2#\#} pct=$3 i out='#' x y
    for i in 0 2 4; do
        x=$((16#${a:i:2}))
        y=$((16#${b:i:2}))
        out+=$(printf '%02x' $(((x * (100 - pct) + y * pct) / 100)))
    done
    printf '%s' "$out"
}

# Read one base24 slot or ramp value from the pack that owns a variant.
# Prints the hex or nothing if the pack/slot is missing.
pack_slot() {
    local variant=$1 slot=$2 f
    [ -d "$PACKS" ] || return 0
    for f in "$PACKS"/*.json; do
        [ -f "$f" ] || continue
        if jq -e --arg v "$variant" '.variants[$v] != null' "$f" >/dev/null 2>&1; then
            jq -r --arg v "$variant" --arg s "$slot" '.variants[$v].slots[$s] // .variants[$v].ramp[$s] // empty' "$f"
            return 0
        fi
    done
}

# The name a variant carries on a surface. Falls back to the template below
# when the pack does not name it — Catppuccin's shape, which is exactly what
# the shipped surface assets implement. Substitutes the variant's id, kind and
# accent so every surface reads its own vocabulary from data, not from these
# appliers hardcoding one ecosystem's name shape.
resolve_surface() {
    local variant=$1 kind=$2 accent=$3 surface=$4 fallback=$5 name
    name=$(surface_template "$variant" "$surface")
    [ -n "$name" ] || name="$fallback"
    name="${name/"{variant}"/$variant}"
    name="${name/"{kind}"/$kind}"
    name="${name/"{accent}"/$accent}"
    printf '%s' "$name"
}

# --- the store ---------------------------------------------------------------

# Reads one field. jq is a hard dependency of the shell already. The legacy
# store is the one step back: a store not migrated yet still answers, and the
# next put moves it.
get() {
    local key=$1 fallback=${2-}
    [ -f "$STATE" ] || {
        [ ! -f "$LEGACY" ] || jq -r --arg k "$key" --arg d "$fallback" '.[$k] // $d' "$LEGACY" 2>/dev/null && return
        printf '%s' "$fallback"
        return
    }
    jq -r --arg k "$key" --arg d "$fallback" '.[$k] // $d' "$STATE" 2>/dev/null || printf '%s' "$fallback"
}

# Merges a patch. Atomic: the shell is watching this file, and a half-written
# one is a palette nobody asked for.
put() {
    local patch=$1 tmp
    mkdir -p "$(dirname "$STATE")"
    [ -f "$STATE" ] || printf '{}' >"$STATE"
    tmp=$(mktemp "$STATE.XXXXXX")
    jq --argjson p "$patch" '. * $p' "$STATE" >"$tmp"
    mv -f "$tmp" "$STATE"
}

# --- the result --------------------------------------------------------------
#
# The adapter-result contract (schemas/adapter-result.schema.json): appliers
# below call these as they go, so the summary reflects what each one actually
# did rather than a second pass re-guessing it from the human output.
RESULT_APPLIED=()
RESULT_PENDING=()
RESULT_FAILED=()
# One entry per monitor a wallpaper command actually resolved (cycled or
# bound), across the whole run — separate from applied/pending/failed since a
# wallpaper pick is "what was chosen", not "did a surface accept it".
RESULT_WALLPAPER=()

record_applied() { RESULT_APPLIED+=("$(jq -n --arg s "$1" --arg t "$2" '{surface: $s, tier: $t}')"); }
record_pending() { RESULT_PENDING+=("$(jq -n --arg s "$1" --arg t "$2" --arg r "$3" '{surface: $s, tier: $t, reason: $r}')"); }
record_failed() { RESULT_FAILED+=("$(jq -n --arg s "$1" --arg r "$2" '{surface: $s, reason: $r}')"); }

# jq -s over one-per-line input, so an empty bash array still yields `[]`
# rather than jq choking on zero arguments.
json_array() {
    local -n arr=$1
    [ ${#arr[@]} -eq 0 ] && {
        printf '[]'
        return
    }
    printf '%s\n' "${arr[@]}" | jq -s .
}

# Written once per `apply`, atomically for the same reason theme.json is: a
# reader (AdapterResult.qml) may be watching this file mid-write.
write_result() {
    local ok=true tmp
    [ ${#RESULT_FAILED[@]} -eq 0 ] || ok=false
    mkdir -p "$ROOT"
    tmp=$(mktemp "$RESULT.XXXXXX")
    jq -n \
        --argjson ok "$ok" \
        --argjson ts "$(date +%s)" \
        --arg adapter theme \
        --argjson applied "$(json_array RESULT_APPLIED)" \
        --argjson pending "$(json_array RESULT_PENDING)" \
        --argjson failed "$(json_array RESULT_FAILED)" \
        --argjson wallpaper "$(json_array RESULT_WALLPAPER)" \
        '{ok: $ok, ts: $ts, adapter: $adapter, applied: $applied, pending: $pending, failed: $failed, wallpaper: $wallpaper}' >"$tmp"
    mv -f "$tmp" "$RESULT"
}

is_palette() {
    local p=$1 f
    for known in "${PALETTES[@]}"; do [ "$p" = "$known" ] && return 0; done
    # The packs widen the vocabulary (LEO-210/289): any variant the packs
    # carry is nameable. The appliers' own presence checks hold whether the
    # surface assets actually exist for it — a leasable name is not a
    # promise that every surface has the theme.
    if [ -d "$PACKS" ]; then
        for f in "$PACKS"/*.json; do
            [ -f "$f" ] || continue
            jq -e --arg p "$p" '.variants[$p] != null' "$f" >/dev/null 2>&1 && return 0
        done
    fi
    return 1
}

is_light() {
    local p=$1
    for l in "${LIGHT[@]}"; do [ "$p" = "$l" ] && return 0; done
    return 1
}

# --- which palette --------------------------------------------------------

# The pointer, resolved exactly like the mode policy reads it everywhere else:
# the held mode, falling back to `work` at rest. A timed mode whose `until`
# already passed resolves to its `previous` mode (the one it was layered
# over) if the pointer carries one, else to `work`. `neutral` is never a
# fallback — it is a hidden recovery mode, reached only deliberately. Shared
# by both lease applications (the palette and the wallpaper) so two readers
# can never disagree about which mode is on.
lease_state() {
    local mode until until_ms previous file="$FOCUS"
    [ -f "$file" ] || { [ ! -f "$LEGACY_FOCUS" ] || file="$LEGACY_FOCUS"; }
    [ -f "$file" ] && mode=$(jq -r '.mode // "work"' "$file" 2>/dev/null) || mode=work
    until=$(jq -r '.until // ""' "$file" 2>/dev/null)
    if [ -n "$until" ]; then
        until_ms=$(date -d "$until" +%s%3N 2>/dev/null || echo 0)
        if [ "$(date +%s%3N)" -gt "$until_ms" ]; then
            previous=$(jq -r '.previous // "work"' "$file" 2>/dev/null)
            mode="$previous"
        fi
    fi
    printf '%s' "$mode"
}

# The palette a mode leases while it runs (LEO-288). The declaration names a
# day/night pair (or one palette for both) in the mode's `presentation`; the
# pointer (focus.json) says which mode is on, resolved by `lease_state`
# (timed-expiry aware). Work still leases a palette like any other mode. The
# pair follows `daytime`, so the sun timer flips a mode's palette exactly as
# it flips the baseline. "" means no lease held, and an unknown lease palette
# reads as no lease: resolution never fails.
lease() {
    local mode palette half=night
    mode=$(lease_state)
    ! daytime || half=day
    palette=$(jq -r --arg m "$mode" --arg h "$half" \
        '.modes[$m].presentation.palette // "" | if type == "object" then .[$h] // "" else . end' \
        "$DECLARATION" 2>/dev/null) || return 0
    is_palette "$palette" && printf '%s' "$palette" || return 0
}

# The baseline: the palette the desk shows when no lease is held. `mode: auto`
# means the sun decides; `manual` means a deliberate pick stands until it is
# handed back. Resolving here rather than in the timer keeps every entry point
# agreeing on what "now" looks like.
baseline() {
    local mode palette
    mode=$(get mode auto)
    if [ "$mode" = "auto" ]; then
        if daytime; then get day latte; else get night macchiato; fi
    else
        palette=$(get palette macchiato)
        is_palette "$palette" && printf '%s' "$palette" || printf 'macchiato'
    fi
}

resolve() {
    local lease
    lease=$(lease)
    if [ -n "$lease" ]; then printf '%s' "$lease"; else baseline; fi
}

# Sunrise/sunset without a network call or a geolocation dependency: the hours
# are close enough for a colour scheme, and being wrong by twenty minutes at the
# equinox costs nothing.
#
# THEME_HOUR overrides the clock, the same injection pattern as THEME_GSETTINGS
# below: tests need to force day/night deterministically rather than waiting for
# the clock to agree.
daytime() {
    local hour
    hour=${THEME_HOUR:-$(date +%-H)}
    [ "$hour" -ge 7 ] && [ "$hour" -lt 19 ]
}

# --- the surfaces ------------------------------------------------------------
#
# Each applier is best-effort and independent: a missing tool must not stop the
# rest of the desk from changing colour. They report what they did so `apply`
# can summarise.

# gsettings is the one applier that does NOT respect $XDG_CONFIG_HOME: the write
# goes over D-Bus to the dconf service, which uses its own environment. Pointing
# XDG_CONFIG_HOME at a scratch tree therefore does not sandbox it — it changes
# the live session. Everything else here edits files under $CONFIG and is
# contained by that variable alone.
#
# So the call is injectable. Tests set THEME_GSETTINGS to a recorder and assert
# on what it was told; nothing else should ever override it.
GSETTINGS=${THEME_GSETTINGS:-gsettings}

# Same injection point, for the same reason: tests need to force the
# "ImageMagick missing" path deterministically rather than hoping the machine
# running them lacks it.
MAGICK=${THEME_MAGICK:-magick}

# awww (swww's maintained continuation, see theming role defaults for why) is
# two binaries: the client that sets an image, and the daemon it needs already
# running. Both injectable for the same reason as MAGICK — a test must be able
# to force "not installed" and "daemon not up yet" without touching the host.
AWWW=${THEME_AWWW:-awww}
AWWW_DAEMON=${THEME_AWWW_DAEMON:-awww-daemon}

# Injectable for the same reason as AWWW: a test must be able to record
# `hyprctl` invocations (the reload-suppression assertion below) without
# touching a live compositor.
HYPRCTL=${THEME_HYPRCTL:-hyprctl}

# The nvim poke goes straight to a binary that is never on the sandbox path, so
# it is injectable like gsettings: a recorder answers in its place, and the
# sandbox holds it back unless THEME_NVIM names one.
NVIM=${THEME_NVIM:-nvim}

# The same hazard, three more times: hyprctl, pkill and awww all address the
# live session by name and ignore $XDG_CONFIG_HOME entirely. Setting
# THEME_GSETTINGS at all means "this is a test run" and holds every one of them
# back, so a test can never repaint the desk it is running on.
sandboxed() { [ -n "${THEME_GSETTINGS-}" ]; }

apply_kitty() {
    local palette=$1 conf="$CONFIG/kitty/current-theme.conf" theme
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" kitty "$palette")
    [ -f "$CONFIG/kitty/themes/$theme.conf" ] || {
        echo "kitty: no theme for $theme"
        record_failed kitty "no theme for $theme"
        return
    }
    # Remote control is deliberately off in kitty.conf, so this is a file swap
    # plus SIGUSR1, which kitty answers by re-reading its config. Every running
    # window changes colour; no sockets, no open port.
    ln -sfn "themes/$theme.conf" "$conf"
    sandboxed || pkill -USR1 -x kitty 2>/dev/null || true
    echo "kitty: $theme"
    record_applied kitty immediate
}

# Every configured nvim follows the store itself (nvim/lua/theme/store.lua
# watches theme.json, so a socketless editor still switches from the same write
# this fan-out triggered). The poke below is the *synchronous* half: it talks
# to the control sockets a live editor already listens on -- `bin/,proj.sh`
# gives each project's nvim slot a `--listen` socket under
# `$XDG_RUNTIME_DIR/proj-nvim`, and a plain `nvim` writes its own under
# `$XDG_RUNTIME_DIR`. There is no config file to swap here -- catppuccin.nvim
# registers one colorscheme per flavour, so switching is a command, and a
# `--remote-expr` runs it without touching the editor's current mode (a
# `--remote-send` would type into whatever buffer was open).
#
# A socket whose nvim has since exited is a dead file: the send fails, which
# is why each is tried independently and a failure is not the surface's.
# `immediate` is claimed only when a socket actually switched; otherwise the
# editor still catches the same write through its own watcher, so the run
# reports it as pending, never as applied-by-us.
apply_nvim() {
    local palette=$1 theme sock sent=0 miss=""
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" nvim "catppuccin-$palette")
    if ! have "$NVIM"; then
        return
    fi
    if sandboxed && [ -z "${THEME_NVIM-}" ]; then
        echo "nvim: skipped (sandboxed)"
        record_pending nvim next-launch "no nvim poke in a sandboxed run"
        return
    fi
    for sock in "${XDG_RUNTIME_DIR:-/tmp}"/proj-nvim/*.sock "${XDG_RUNTIME_DIR:-/tmp}"/nvim.*; do
        [ -S "$sock" ] || continue
        # --remote-expr prints the expression's result: `execute()` returns an
        # empty string for a real switch, and the "E185: Cannot find color
        # scheme '…'" text for a lazy unloaded catppuccin — while the remote
        # call itself exits 0 either way. Judge by what came back, not the
        # status: a swallowed E185 must not count as a switch. Anything that is
        # not an empty answer, including a connector that cannot reach the
        # editor behind a socket file, lands in `miss` and is surfaced. The
        # `|| true` is load-bearing: nvim exits 2 on E247 (connect refused —
        # a stale socket file left by an exited editor), and under set -e that
        # exit status rides the assignment and killed the whole apply
        # mid-flight — which is why gtk/zen/obsidian/linear stopped flipping
        # whenever one stale socket lingered. A dead socket is a miss, not
        # the theme's failure. The timeout covers the third shape, a socket
        # whose editor accepts but never answers (a wedged process): without
        # it the poke blocks forever, and the desk waits on one stuck editor
        # instead of switching. THEME_NVIM_TIMEOUT exists for the tests.
        answer=$(timeout "${THEME_NVIM_TIMEOUT:-5}" "$NVIM" --server "$sock" --remote-expr "execute('colorscheme $theme')" 2>&1) || true
        if [ -z "$(printf '%s' "$answer" | tr -d '[:space:]')" ]; then
            sent=$((sent + 1))
        else
            [ -n "$miss" ] || miss=$(printf '%s' "$answer" | head -1)
        fi
    done
    if [ "$sent" -gt 0 ]; then
        echo "nvim: $theme ($sent live)"
        record_applied nvim immediate
    elif [ -n "$miss" ]; then
        echo "nvim: $theme (no socket switched: $miss)"
        record_pending nvim next-launch "no socket switched: $miss"
    else
        echo "nvim: $theme (no sockets; the editor follows the store itself)"
        record_pending nvim next-launch "no control socket; the editor follows theme.json itself"
    fi
}

apply_gtk() {
    local palette=$1 theme scheme
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" gtk "catppuccin-$palette-$ACCENT-standard+default")
    if [ ! -d "/usr/share/themes/$theme" ] && [ ! -d "$HOME/.themes/$theme" ]; then
        echo "gtk: $theme not installed (see the theming role)"
        record_failed gtk "$theme not installed"
        return
    fi
    is_light "$palette" && scheme="prefer-light" || scheme="prefer-dark"
    if have "$GSETTINGS"; then
        "$GSETTINGS" set org.gnome.desktop.interface gtk-theme "$theme"
        "$GSETTINGS" set org.gnome.desktop.interface color-scheme "$scheme"
    fi
    # Icons are a separate setting from the theme, and were never switched at
    # all: a light palette kept Papirus-Dark, which is why the tray and menus
    # stayed dark against light chrome.
    local icons
    is_light "$palette" && icons="Papirus-Light" || icons="Papirus-Dark"
    if have "$GSETTINGS"; then
        "$GSETTINGS" set org.gnome.desktop.interface icon-theme "$icons"
    fi

    # GTK4 ignores the theme name and reads this instead.
    mkdir -p "$CONFIG/gtk-4.0"
    ln -sfn "/usr/share/themes/$theme/gtk-4.0/gtk.css" "$CONFIG/gtk-4.0/gtk.css" 2>/dev/null || true

    # The gsettings writes are live, but the declaration files the theming
    # role seeded keep the palette the machine was installed with. A light
    # switch therefore left native GTK menus — which Zen draws with the theme
    # GTK hands it — still announcing a dark theme: bright menu text on the
    # mod's light panel background. Write the same values into every file a
    # reader could be looking at, so no consumer can disagree about what is on.
    local dark=0
    is_light "$palette" || dark=1
    for c in "$CONFIG/gtk-3.0/settings.ini" "$CONFIG/gtk-4.0/settings.ini"; do
        [ -f "$c" ] || continue
        # prefer-dark is what flips the theme variant GTK serves; 1 hands
        # every app the dark look whatever the declared theme name says.
        sed -i "s|^gtk-theme-name=.*|gtk-theme-name=$theme|" "$c"
        sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=$icons|" "$c"
        sed -i "s|^gtk-application-prefer-dark-theme=.*|gtk-application-prefer-dark-theme=$dark|" "$c"
    done
    # XWayland toolkits learn the theme from this. The HUP is what makes
    # already-running ones re-read — the same poke apply_qt sends.
    if [ -f "$CONFIG/xsettingsd/xsettingsd.conf" ]; then
        sed -i "s|^Net/ThemeName .*|Net/ThemeName \"$theme\"|" "$CONFIG/xsettingsd/xsettingsd.conf"
        sed -i "s|^Net/IconThemeName .*|Net/IconThemeName \"$icons\"|" "$CONFIG/xsettingsd/xsettingsd.conf"
        sandboxed || pkill -HUP -x xsettingsd 2>/dev/null || true
    fi
    # GTK2 reads this fallback next to ~/.gtkrc-2.0 (nwg-look owns that one).
    # The file lives in the home directory, so by default the write is held
    # back under sandbox like the other live surfaces: a test must not repaint
    # the desk it runs on. THEME_GTKRC_MINE redirects it, the same escape hatch
    # THEME_AWWW gives the wallpaper recorder.
    if [ -n "${THEME_GTKRC_MINE-}" ] || ! sandboxed; then
        local mine="${THEME_GTKRC_MINE:-$HOME/.gtkrc-2.0.mine}"
        if [ -f "$mine" ]; then
            sed -i 's|^gtk-theme-name=.*|gtk-theme-name="'"$theme"'"|' "$mine"
            sed -i 's|^gtk-icon-theme-name=.*|gtk-icon-theme-name="'"$icons"'"|' "$mine"
        fi
    fi
    # The nwg-look store is the declaration its GUI renders from, and a click
    # on Apply there re-exports every file this function just wrote — from the
    # store. If the store still named the palette the machine was installed
    # with, Apply would paint the old scheme back over the desk; keep its
    # scheme in agreement with the apply. Same home-directory escape hatch as
    # the .gtkrc file above.
    if [ -n "${THEME_NWG_GSETTINGS-}" ] || ! sandboxed; then
        local nwg="${THEME_NWG_GSETTINGS:-$HOME/.local/share/nwg-look/gsettings}"
        if [ -f "$nwg" ]; then
            sed -i "s|^gtk-theme=.*|gtk-theme=$theme|" "$nwg"
            sed -i "s|^icon-theme=.*|icon-theme=$icons|" "$nwg"
            sed -i "s|^color-scheme=.*|color-scheme=$scheme|" "$nwg"
        fi
    fi
    echo "gtk: $theme ($scheme, $icons; settings.ini + xsettingsd + .gtkrc + nwg-look follow)"
    record_applied gtk immediate
}

apply_qt() {
    local palette=$1
    # Separate declarations: within one `local`, the earlier assignment has not
    # taken effect yet, so $palette would be empty here.
    local colors
    colors=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" qt "catppuccin-$palette-$ACCENT")
    local applied=()
    for v in qt5ct qt6ct; do
        local conf="$CONFIG/$v/$v.conf" scheme="$CONFIG/$v/colors/$colors.conf"
        [ -f "$conf" ] || continue
        [ -f "$scheme" ] || {
            echo "$v: no colour scheme $colors"
            continue
        }
        # sed in place on one key: the rest of the file is qt5ct's own state and
        # is none of our business.
        sed -i "s|^color_scheme_path=.*|color_scheme_path=$scheme|" "$conf"
        applied+=("$v")
    done

    local kv="$CONFIG/Kvantum/kvantum.kvconfig"
    if [ -f "$kv" ] && [ -d "$CONFIG/Kvantum/$colors" ]; then
        sed -i "s|^theme=.*|theme=$colors|" "$kv"
        applied+=(kvantum)
    fi

    # xsettingsd is what tells already-running toolkits to re-read; without the
    # HUP the change waits for the next launch.
    sandboxed || pkill -HUP -x xsettingsd 2>/dev/null || true
    echo "qt: $colors [${applied[*]:-none}]"
    if [ ${#applied[@]} -eq 0 ]; then
        record_failed qt "no colour scheme $colors installed"
    else
        record_applied qt immediate
    fi
}

# Everything below was installed in all four flavours and switched in none of
# them: the assets were there, the selector line was not. Each is one line in a
# config file, and each was a surface that stayed Macchiato while the desk moved.

# btop names its theme file outright.
apply_btop() {
    local palette=$1 theme conf="$CONFIG/btop/btop.conf"
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" btop "catppuccin_$palette")
    [ -f "$conf" ] || return 0
    [ -f "$CONFIG/btop/themes/$theme.theme" ] || return 0
    sed -i "s|^color_theme = .*|color_theme = \"$theme.theme\"|" "$conf"
    echo "btop: $theme"
    record_applied btop immediate
}

# yazi's theme is one 880-line document, most of it a per-filename icon table
# that no palette switch has any business regenerating. Every colour in it is
# a Catppuccin role, though, so the swap is mechanical: the shipped template
# (assets/yazi/theme.toml, Macchiato) is read role by role and each hex is
# rewritten to the resolved flavour's own. Adding a colour to the template is
# free; adding a ROLE means adding it to `accent_hex`, which is where every
# other adapter reads its colours from too.
#
# yazi reads the file at launch, so a running instance keeps the old palette —
# the same tier as Zen and Obsidian, and reported as such.
YAZI_ROLES="rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender text subtext1 subtext0 overlay2 overlay1 overlay0 surface2 surface1 surface0 base mantle crust"

apply_yazi() {
    local palette=$1 conf="$CONFIG/yazi/theme.toml" template flavor
    template="$SCRIPT_DIR/../assets/yazi/theme.toml"
    [ -f "$template" ] || {
        record_failed yazi "no theme template at $template"
        echo "yazi: no theme template"
        return 0
    }
    [ -d "$CONFIG/yazi" ] || return 0

    case "$palette" in
    latte) flavor="Latte" ;;
    frappe) flavor="Frappe" ;;
    mocha) flavor="Mocha" ;;
    *) flavor="Macchiato" ;;
    esac

    # One sed script, built role by role. The template is Macchiato, so its own
    # hex is what each rule matches.
    local script="" role from to
    for role in $YAZI_ROLES; do
        from=$(accent_hex macchiato "$role")
        to=$(accent_hex "$palette" "$role")
        script="$script;s|${from}|${to}|Ig"
    done
    # bat's tmTheme carries yazi's syntax highlighting, and ships per flavour.
    script="$script;s|Catppuccin Macchiato\.tmTheme|Catppuccin ${flavor}.tmTheme|g"

    sed "${script#;}" "$template" >"$conf.tmp" && mv -f "$conf.tmp" "$conf"
    echo "yazi: $flavor (applies on next launch)"
    record_pending yazi next-launch "theme.toml is read at launch"
}

# zathura includes a file by bare name.
apply_zathura() {
    local palette=$1 theme conf="$CONFIG/zathura/zathurarc"
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" zathura "catppuccin-$palette")
    [ -f "$conf" ] || return 0
    [ -f "$CONFIG/zathura/$theme" ] || return 0
    sed -i "s|^include catppuccin-.*|include $theme|" "$conf"
    echo "zathura: $theme"
    record_applied zathura immediate
}

# rofi's `@theme` in config.rasi names the USER'S own theme (custom.rasi), which
# then @imports a palette. Rewriting @theme threw that away along with every
# override in it — the launcher came back as stock Catppuccin and, on a light
# palette, cream. The palette seam is the @import line inside custom.rasi.
apply_rofi() {
    local palette=$1 conf="$CONFIG/rofi/config.rasi" icons
    local custom="$HOME/.local/share/rofi/themes/custom.rasi"
    [ -f "$conf" ] || return 0
    is_light "$palette" && icons="Papirus-Light" || icons="Papirus-Dark"
    sed -i "s|^\( *icon-theme: *\).*|\1\"$icons\";|" "$conf"
    local rasi
    rasi=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" rofi "catppuccin-$palette")
    if [ -f "$custom" ] && [ -f "$HOME/.local/share/rofi/themes/$rasi.rasi" ]; then
        sed -i "s|^@import .*|@import \"$rasi\"|" "$custom"
    fi
    echo "rofi: $rasi ($icons)"
    record_applied rofi immediate
}

# wlogout needs both its icon flavour and its CSS colours rewritten to follow
# the active palette. The applier owns the whole file: it is regenerated every
# time so the paths and colours stay in sync and no hand-edits can drift.
apply_wlogout() {
    local palette=$1 role=${2:-$ACCENT} kind theme css="$CONFIG/wlogout/style.css"
    local icon_dir icon_ext="svg"
    kind=$(is_light "$palette" && echo light || echo dark)
    theme=$(resolve_surface "$palette" "$kind" "$role" wlogout "$palette")

    # Prefer the Catppuccin icon set if it is provisioned, otherwise fall back
    # to the system wlogout icons so the menu is never blank.
    icon_dir="$CONFIG/wlogout/catppuccin/icons/wlogout/$theme"
    if [ ! -d "$icon_dir" ]; then
        for d in /usr/share/wlogout/icons /usr/local/share/wlogout/icons; do
            if [ -f "$d/lock.png" ]; then
                icon_dir="$d"
                icon_ext="png"
                break
            fi
        done
    fi
    [ -n "$icon_dir" ] || return 0

    # Read the palette's own slots; fall back to Macchiato if the pack is gone.
    local base01 base02 base03 base05 accent
    base01=$(pack_slot "$palette" "base01")
    base01=${base01:-#1e2030}
    base02=$(pack_slot "$palette" "base02")
    base02=${base02:-#363a4f}
    base03=$(pack_slot "$palette" "base03")
    base03=${base03:-#494d64}
    base05=$(pack_slot "$palette" "base05")
    base05=${base05:-#cad3f5}
    accent=$(accent_hex "$palette" "$role")

    # Alpha-scrimmed surfaces: keep tiles subtle on every palette.
    local btn_bg btn_border btn_hover
    btn_bg=$(hex_to_rgba "$base01" 0.82)
    btn_border=$(hex_to_rgba "$base03" 0.55)
    btn_hover=$(hex_to_rgba "$base02" 0.92)

    # Hover icons: use the accent flavour when the Catppuccin set is present,
    # otherwise tint the same neutral icon via the hover colour.
    local hover_dir
    if [ "$icon_ext" = "svg" ] && [ -d "$CONFIG/wlogout/catppuccin/icons/wlogout/$theme/$role" ]; then
        hover_dir="$CONFIG/wlogout/catppuccin/icons/wlogout/$theme/$role"
    else
        hover_dir="$icon_dir"
    fi

    mkdir -p "$(dirname "$css")"
    cat >"$css" <<EOF
# ~/.config/wlogout/style.css — rendered by roles/theming and recoloured by
# \`,theme.sh apply_wlogout'. Do not edit by hand; the next palette change
# overwrites this file.

* {
  font-family: "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono";
  font-weight: 600;
  font-size: 15px;
  background-image: none;
  box-shadow: none;
  transition: all 0.2s ease;
}

window {
  background-color: transparent;
}

button {
  color: $base05;
  background-color: $btn_bg;
  border: 1px solid $btn_border;
  border-radius: 18px;
  margin: 10px;
  background-repeat: no-repeat;
  background-position: center 30%;
  background-size: 26%;
  outline: none;
}

button:hover {
  color: $accent;
  background-color: $btn_hover;
  border-color: $accent;
}

/* default (neutral) icons */
#lock      { background-image: url("$icon_dir/lock.$icon_ext"); }
#logout    { background-image: url("$icon_dir/logout.$icon_ext"); }
#suspend   { background-image: url("$icon_dir/suspend.$icon_ext"); }
#hibernate { background-image: url("$icon_dir/hibernate.$icon_ext"); }
#shutdown  { background-image: url("$icon_dir/shutdown.$icon_ext"); }
#reboot    { background-image: url("$icon_dir/reboot.$icon_ext"); }

/* accent icons on hover */
#lock:hover      { background-image: url("$hover_dir/lock.$icon_ext"); }
#logout:hover    { background-image: url("$hover_dir/logout.$icon_ext"); }
#suspend:hover   { background-image: url("$hover_dir/suspend.$icon_ext"); }
#hibernate:hover { background-image: url("$hover_dir/hibernate.$icon_ext"); }
#shutdown:hover  { background-image: url("$hover_dir/shutdown.$icon_ext"); }
#reboot:hover    { background-image: url("$hover_dir/reboot.$icon_ext"); }
EOF

    echo "wlogout: $theme (${icon_dir##*/})"
    record_applied wlogout immediate
}

# Zen reads user.js once at launch, so the prefs land on the next restart.
# The chrome CSS is provisioned by system-config's `roles/browser` and read at
# launch too; nothing here overwrites it, so a per-profile CSS edit (Browser
# Toolbox, a userstyle manager) survives every apply. This applier owns the two
# runtime seams: the accent Zen reads from user.js, and the palette file the
# chrome CSS @imports. A running Zen still needs a restart to pick up either.
apply_zen() {
    local palette=$1 role=$2 accent
    local zen_dir="$CONFIG/zen/shared"
    local js="$zen_dir/user.js"
    [ -f "$js" ] || return 0
    mkdir -p "$zen_dir"
    accent=$(accent_hex "$palette" "$role")

    sed -i "s|^user_pref(\"zen.theme.accent-color\".*|user_pref(\"zen.theme.accent-color\", \"$accent\");|" "$js"
    sed -i "s|^user_pref(\"layout.css.prefers-color-scheme.content-override\".*|user_pref(\"layout.css.prefers-color-scheme.content-override\", 3); // follow system|" "$js"
    sed -i "s|^user_pref(\"theme-better_find_bar-enable_custom_background\".*|user_pref(\"theme-better_find_bar-enable_custom_background\", false);|" "$js"

    printf '@media (prefers-color-scheme: light) { :root { --qf-accent: %s; } }\n@media (prefers-color-scheme: dark) { :root { --qf-accent: %s; } }\n' "$accent" "$accent" >"$zen_dir/zen-palette.css"
    chmod 644 "$zen_dir/zen-palette.css"

    echo "zen: $accent (palette + user.js accent; CSS is provisioned by roles/browser)"
    record_pending zen next-launch "Zen reads user.js and the provisioned CSS at launch"
}

# Obsidian reads its vault's appearance.json at launch, so this lands on the
# next restart — the same tier zen lives on. The mapping is the palette's
# accent plus Obsidian's own adapt-to-system key: the CSS theme stays
# Catppuccin (already chosen in the vault), which is what makes a manual
# retheme afterwards an error worth avoiding.
#
# `theme` is always forced to "system", not a fixed moonstone/obsidian base:
# writing a light/dark base here fought Obsidian's own Adapt to system
# setting on every palette switch. "system" keeps this adapter's ownership of
# the key while making Obsidian follow the desktop colour scheme (which
# apply_gtk already sets via gsettings) — any outside change to the key is
# corrected at the next apply instead of compounded.
#
# The vault is nameable rather than discovered: a single declared vault keeps
# the adapter one edit behind the truth instead of guessing which of several
# looks themed. `bin/,obsidian-cli-wrapper.sh` names the same Main vault, so
# the two paths already agree on the source.
apply_obsidian() {
    local palette=$1 role=$2 vault="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian/Main}" appearance
    appearance="$vault/.obsidian/appearance.json"
    [ -f "$appearance" ] || {
        echo "obsidian: $appearance not found"
        record_failed obsidian "vault appearance.json not found"
        return 0
    }
    if ! jq --arg accent "$(accent_hex "$palette" "$role")" \
        '.theme = "system" | .accentColor = $accent' "$appearance" >"$appearance.tmp" ||
        ! mv -f "$appearance.tmp" "$appearance"; then
        record_failed obsidian "appearance.json is not writable"
        return 0
    fi
    echo "obsidian: adapt-to-system + accent (applies on next launch)"
    record_pending obsidian next-launch "appearance.json is read at launch"
}

# fzf's colour list, derived from the palette rather than spelled out: one
# accent (mauve), the scene's own surface, and overlay0 for the quiet text.
fzf_colors() {
    local p=$1
    printf 'bg+:%s,fg:%s,fg+:%s,hl:%s,hl+:%s,pointer:%s,prompt:%s,marker:%s,spinner:%s,info:%s,header:%s,gutter:-1,border:%s' \
        "$(accent_hex "$p" surface0)" "$(accent_hex "$p" text)" "$(accent_hex "$p" text)" \
        "$(accent_hex "$p" mauve)" "$(accent_hex "$p" mauve)" "$(accent_hex "$p" mauve)" \
        "$(accent_hex "$p" mauve)" "$(accent_hex "$p" green)" "$(accent_hex "$p" mauve)" \
        "$(accent_hex "$p" overlay0)" "$(accent_hex "$p" overlay0)" "$(accent_hex "$p" surface0)"
}

# zsh and fzf read no store and no live D-Bus signal — the desk's every other
# surface either watches theme.json itself (Quickshell, Hyprland) or gets
# poked by a call in this file. A generated, sourced file is the equivalent
# poke for a shell: written on every apply, so it always matches the palette
# every OTHER adapter just applied — day and night, exactly like the rest of
# this fan-out and never a second route a shell config has to remember to run
# on its own. `bin/Readme.md` documents the one line the zsh role's rc file
# sources it with; a running shell picks up the new file the next time it
# starts a prompt that re-sources it (or on its own next launch), same tier
# kitty's re-exec-on-signal alternative would be for a shell if one existed.
apply_shell() {
    local palette=$1 conf="$CONFIG/zsh/theme.zsh" flavor
    case "$palette" in
    latte) flavor="Latte" ;;
    frappe) flavor="Frappe" ;;
    macchiato) flavor="Macchiato" ;;
    mocha) flavor="Mocha" ;;
    *) flavor="Macchiato" ;;
    esac
    mkdir -p "$CONFIG/zsh"

    # Every colour below comes from accent_hex, the one palette table this
    # script keeps, so the shell cannot drift from the surfaces themed beside
    # it. Named locals rather than repeated calls: this function spells out a
    # lot of colour and the names are what make it readable.
    local text subtext0 overlay0 surface0 surface1 surface2 base mantle
    local mauve red maroon peach yellow green teal lavender
    text=$(accent_hex "$palette" text)
    subtext0=$(accent_hex "$palette" subtext0)
    overlay0=$(accent_hex "$palette" overlay0)
    surface0=$(accent_hex "$palette" surface0)
    surface1=$(accent_hex "$palette" surface1)
    surface2=$(accent_hex "$palette" surface2)
    base=$(accent_hex "$palette" base)
    mantle=$(accent_hex "$palette" mantle)
    mauve=$(accent_hex "$palette" mauve)
    red=$(accent_hex "$palette" red)
    maroon=$(accent_hex "$palette" maroon)
    peach=$(accent_hex "$palette" peach)
    yellow=$(accent_hex "$palette" yellow)
    green=$(accent_hex "$palette" green)
    teal=$(accent_hex "$palette" teal)
    lavender=$(accent_hex "$palette" lavender)

    # delta paints added and removed lines on a tinted background rather than a
    # palette colour: a blend of the flavour's own base toward green and red.
    local minus_bg plus_bg minus_emph plus_emph
    minus_bg=$(blend_hex "$base" "$red" 25)
    minus_emph=$(blend_hex "$base" "$red" 45)
    plus_bg=$(blend_hex "$base" "$green" 25)
    plus_emph=$(blend_hex "$base" "$green" 45)

    local bat_theme="Catppuccin $flavor"
    local delta_opts
    delta_opts="--navigate --line-numbers --hyperlinks --syntax-theme='$bat_theme'"
    delta_opts="$delta_opts --true-color=always"
    delta_opts="$delta_opts --minus-style='syntax $minus_bg' --minus-non-emph-style='syntax $minus_bg'"
    delta_opts="$delta_opts --minus-emph-style='syntax $minus_emph' --minus-empty-line-marker-style='syntax $minus_bg'"
    delta_opts="$delta_opts --plus-style='syntax $plus_bg' --plus-non-emph-style='syntax $plus_bg'"
    delta_opts="$delta_opts --plus-emph-style='syntax $plus_emph' --plus-empty-line-marker-style='syntax $plus_bg'"
    delta_opts="$delta_opts --zero-style='syntax' --whitespace-error-style='$base $red'"
    delta_opts="$delta_opts --file-style='bold $mauve' --file-decoration-style='$surface1 ul'"
    delta_opts="$delta_opts --hunk-header-style='file line-number syntax'"
    delta_opts="$delta_opts --hunk-header-decoration-style='$surface1 box'"
    delta_opts="$delta_opts --hunk-header-file-style='$lavender' --hunk-header-line-number-style='$teal'"
    delta_opts="$delta_opts --line-numbers-minus-style='$red' --line-numbers-plus-style='$green'"
    delta_opts="$delta_opts --line-numbers-zero-style='$overlay0'"
    delta_opts="$delta_opts --line-numbers-left-style='$surface2' --line-numbers-right-style='$surface2'"
    delta_opts="$delta_opts --blame-palette='$base $mantle $surface0 $surface1' --blame-code-style='syntax'"
    delta_opts="$delta_opts --merge-conflict-begin-symbol='~' --merge-conflict-end-symbol='~'"
    delta_opts="$delta_opts --merge-conflict-ours-diff-header-style='$yellow bold'"
    delta_opts="$delta_opts --merge-conflict-theirs-diff-header-style='$yellow bold'"

    # eza and ls read the same SGR grammar, in decimal triples.
    local eza_colors
    eza_colors="da=38;2;$(hex_to_dec "$overlay0"):uu=38;2;$(hex_to_dec "$overlay0")"
    eza_colors="$eza_colors:gu=38;2;$(hex_to_dec "$overlay0"):ur=38;2;$(hex_to_dec "$mauve")"
    eza_colors="$eza_colors:uw=38;2;$(hex_to_dec "$yellow"):ux=38;2;$(hex_to_dec "$green")"
    eza_colors="$eza_colors:sn=38;2;$(hex_to_dec "$teal"):sb=38;2;$(hex_to_dec "$overlay0")"
    eza_colors="$eza_colors:xx=38;2;$(hex_to_dec "$surface1"):di=38;2;$(hex_to_dec "$mauve")"
    eza_colors="$eza_colors:ln=38;2;$(hex_to_dec "$peach"):ex=38;2;$(hex_to_dec "$green")"

    # fzf's bindings are structure, not palette, so they stay fixed while the
    # --color list moves with the flavour.
    local fzf_opts
    fzf_opts="--bind='tab:toggle+down,btab:up,ctrl-/:toggle-preview'"
    fzf_opts="$fzf_opts --layout=reverse --info=inline --border=none --pointer='▌' --marker='▌'"
    fzf_opts="$fzf_opts --color=$(fzf_colors "$palette")"

    {
        printf '# generated by `,theme.sh apply` -- do not edit by hand\n'
        printf '# palette: %s\n\n' "$palette"

        printf '# bat, and everything that pages through it (man, lessfilter).\n'
        printf 'export BAT_THEME=%q\n\n' "$bat_theme"

        printf '# delta, as git'\''s pager and for hand-piped diffs. Its syntax\n'
        printf '# theme is BAT_THEME, so bat and git diffs move together.\n'
        printf 'export DELTA_OPTS=%q\n' "$delta_opts"
        printf 'export GIT_PAGER=%q\n\n' "delta $delta_opts"

        printf '# difftastic colours itself and only needs the background'\''s polarity.\n'
        printf 'export DFT_BACKGROUND=%q\n\n' "$(is_light "$palette" && echo light || echo dark)"

        printf 'export LS_COLORS=%q\n' "$eza_colors"
        printf 'export EZA_COLORS=%q\n\n' "$eza_colors"

        printf 'export FZF_DEFAULT_OPTS=%q\n\n' "$fzf_opts"

        printf '# less, for man pages and anything else it renders.\n'
        printf 'export LESS_TERMCAP_mb=%q\n' "$(sgr_fg "$red" bold)"
        printf 'export LESS_TERMCAP_md=%q\n' "$(sgr_fg "$mauve" bold)"
        printf 'export LESS_TERMCAP_me=%q\n' "$(printf '\033[0m')"
        printf 'export LESS_TERMCAP_so=%q\n' "$(printf '\033[38;2;%s;48;2;%sm' "$(hex_to_dec "$base")" "$(hex_to_dec "$yellow")")"
        printf 'export LESS_TERMCAP_se=%q\n' "$(printf '\033[0m')"
        printf 'export LESS_TERMCAP_us=%q\n' "$(sgr_fg "$teal" underline)"
        printf 'export LESS_TERMCAP_ue=%q\n\n' "$(printf '\033[0m')"

        # zsh-syntax-highlighting is read at prompt setup, so the whole map is
        # written here rather than left hardcoded in the rc file (where it
        # could only ever name one flavour).
        printf 'ZSH_HIGHLIGHT_HIGHLIGHTERS=(main cursor)\n'
        printf 'typeset -gA ZSH_HIGHLIGHT_STYLES\n'
        local role
        for role in alias suffix-alias global-alias function command builtin reserved-word hashed-command; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$green"
        done
        printf "ZSH_HIGHLIGHT_STYLES[precommand]='fg=%s,italic'\n" "$green"
        printf "ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=%s,italic'\n" "$peach"
        for role in single-hyphen-option double-hyphen-option; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$peach"
        done
        for role in back-quoted-argument history-expansion; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$mauve"
        done
        for role in commandseparator back-quoted-argument-delimiter back-double-quoted-argument back-dollar-quoted-argument; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$red"
        done
        for role in command-substitution-quoted command-substitution-delimiter-quoted single-quoted-argument double-quoted-argument rc-quote; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$yellow"
        done
        for role in single-quoted-argument-unclosed double-quoted-argument-unclosed dollar-quoted-argument-unclosed back-quoted-argument-unclosed unknown-token; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$maroon"
        done
        for role in command-substitution-delimiter command-substitution-delimiter-unquoted process-substitution-delimiter \
            dollar-quoted-argument dollar-double-quoted-argument assign named-fd numeric-fd globbing redirection arg0 default cursor; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s'\n" "$role" "$text"
        done
        for role in path path_prefix; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s,underline'\n" "$role" "$text"
        done
        for role in path_pathseparator path_prefix_pathseparator; do
            printf "ZSH_HIGHLIGHT_STYLES[%s]='fg=%s,underline'\n" "$role" "$red"
        done
        printf "ZSH_HIGHLIGHT_STYLES[comment]='fg=%s'\n" "$subtext0"
    } >"$conf.tmp"
    mv -f "$conf.tmp" "$conf"

    # Same three-tier reach apply_cursor uses: the file above is what a fresh
    # shell (or one that re-sources rc) reads; set-environment is what makes
    # anything uwsm spawns AFTER this point (a new terminal window, most
    # notably) pick it up without waiting on that re-source.
    sandboxed || systemctl --user set-environment \
        "BAT_THEME=$bat_theme" "FZF_DEFAULT_OPTS=$fzf_opts" \
        "LS_COLORS=$eza_colors" "EZA_COLORS=$eza_colors" \
        "DELTA_OPTS=$delta_opts" 2>/dev/null || true
    echo "shell: $flavor (bat, delta, eza, fzf, less, zsh highlighting)"
    record_applied shell immediate
}

# Linear has no config file this adapter can write: it follows the system
# colour scheme, which apply_gtk's gsettings call already moved. Recording it
# is what keeps the tier summary able to say so, instead of nothing appearing
# and a reader assuming "themed". A scheme change reaches an Electron surface
# when it restarts, hence the tier.
apply_linear() {
    local palette=$1 scheme
    scheme=$(is_light "$palette" && echo light || echo dark)
    echo "linear: follows the system colour scheme ($scheme) (applies on next launch)"
    record_pending linear next-launch "follows the system colour scheme"
}

# The cursor is the one thing that used to need a re-login.#
# XCURSOR_THEME lived in ~/.config/environment.d, which systemd --user reads at
# login and never again — so a palette switch could not move it. Three writes
# replace that, covering three different audiences:
#
#   hyprctl setcursor          the compositor, and every surface it draws now
#   systemctl --user set-env   apps launched AFTER this point, since uwsm app
#                              scopes inherit the user manager's environment
#   the seed in environment.d  a fresh login, before any apply has run
#
# Miss the middle one and a browser opened after a switch still gets the old
# cursor; miss the last and a fresh login has no cursor theme at all.
apply_cursor() {
    local palette=$1 theme size variant
    # The cursor outline is painted in its own flavour's base colour, so a
    # flavour-matched cursor loses its border on that flavour's own background:
    # latte's near-white outline on the latte desk read as a thin accent
    # sliver. The cursor is the one surface that wants CONTRAST, not match —
    # a light desk carries the night flavour's cursor (near-black outline),
    # a dark desk keeps its own (the light body already reads on dark).
    variant="$palette"
    if is_light "$palette"; then
        variant=$(get night "$palette")
        is_light "$variant" && variant="mocha"
    fi
    theme=$(resolve_surface "$variant" cursor "$ACCENT" cursor "catppuccin-$variant-$ACCENT-cursors")
    size=$(get cursor_size 28)
    if [ ! -d "/usr/share/icons/$theme" ] && [ ! -d "$HOME/.icons/$theme" ] && [ ! -d "$HOME/.local/share/icons/$theme" ]; then
        echo "cursor: $theme not installed"
        record_failed cursor "$theme not installed"
        return 0
    fi
    sandboxed && {
        echo "cursor: $theme (skipped: sandboxed)"
        return 0
    }
    systemctl --user set-environment "XCURSOR_THEME=$theme" "XCURSOR_SIZE=$size" 2>/dev/null || true
    have hyprctl && hyprctl setcursor "$theme" "$size" >/dev/null 2>&1 || true
    echo "cursor: $theme ($size)"
    record_applied cursor immediate
}

apply_hyprland() {
    local palette=$1 stamp previous
    # AWWW's sandboxed-but-injected exception (see apply_wallpaper_output):
    # a test pointing THEME_HYPRCTL at its own recorder wants the real code
    # path, not the sandbox short-circuit.
    if sandboxed && [ -z "${THEME_HYPRCTL-}" ]; then
        echo "hyprland: skipped (sandboxed)"
        return
    fi
    have "$HYPRCTL" || {
        echo "hyprland: not running"
        record_failed hyprland "not running"
        return
    }
    # A genuine hyprfocus mode transition holds the desk behind a veil and
    # keeps state in the Lua runtime. Reloading mid-transition restarts that
    # runtime, drops the bracket, and makes the veil vanish early. Defer the
    # reload until the transition settles; the post-settle half will call
    # ,theme.sh apply again when it is safe.
    local transition="$ROOT/hyprfocus.transition.json"
    if [ -f "$transition" ] && jq -e '.active == true' "$transition" >/dev/null 2>&1; then
        echo "hyprland: transition active, deferring reload"
        record_applied hyprland pending
        return
    fi
    # Hyprland's colours come from its own config (hypr/themes/colors.lua reads
    # this same store), because `hyprctl keyword general:col.*` answers "unknown
    # request" on a Lua-configured Hyprland — and exits 0, so a script cannot
    # even tell it failed. `apply_colors` pushes that same block through
    # `hl.config` instead, live, which is the lever this uses below.
    #
    # The palette is still compared against the last applied one: theme-auto
    # .timer calls `apply` hourly and most sun-check ticks land in the same
    # day/night half, so pushing colours that have not moved is work for
    # nothing. Skip it when the palette is the one already live.
    stamp="${XDG_CACHE_HOME:-$HOME/.cache}/quantumfate/hyprland.applied"
    previous=$([ -f "$stamp" ] && cat "$stamp" || echo "")

    # A mode-change path already applied border/groupbar colours at runtime
    # (hypr.themes.colors.apply_colors), so the full reload is redundant
    # there and it wipes the Lua state that the scene engine keeps in memory.
    # Skip it, but still mark the palette applied so a later sun-tick or
    # manual `set` does not surprise-reload.
    if [ -n "${HYPRFOCUS_NO_RELOAD-}" ]; then
        if [ "$palette" != "$previous" ]; then
            mkdir -p "$(dirname "$stamp")"
            printf '%s' "$palette" >"$stamp"
        fi
        echo "hyprland: skipped reload (mode-change path)"
        record_applied hyprland immediate
        return
    fi

    if [ "$palette" = "$previous" ]; then
        echo "hyprland: $palette (unchanged, no reload)"
    else
        mkdir -p "$(dirname "$stamp")"
        printf '%s' "$palette" >"$stamp"
        # A palette flip pushes the colours LIVE; it does not reload.
        #
        # Everything Hyprland's own config derives from the palette is the
        # border and groupbar block, and `hypr/themes/colors.lua`'s
        # `apply_colors` writes exactly that block through `hl.config` — which
        # is why the mode-change path (HYPRFOCUS_NO_RELOAD) has never needed a
        # reload for the same job. Reloading for it was the blunt instrument:
        # it re-runs every Lua module, drops the registered layout providers
        # and the scene engine's in-memory state, and on the desk it reads as
        # a visible glitch — the sun timer flipping the palette under a video
        # or a game was the complaint (2026-09-25). Two sun flips a day were
        # two reloads a day for a colour change that needed none.
        #
        # `eval` runs in the compositor's live Lua state (same state the
        # scene engine holds; `bin/,proj.sh` and `bin/,logs.sh` read it the
        # same way), so this reaches the modules already loaded rather than a
        # fresh copy.
        #
        # The submap still leaves first. It was the reload that MADE this
        # mandatory -- re-running the config reset `hypr/lib/submap.lua`'s
        # stack under a keyboard still runtime-in a submap, so escape popped
        # an empty stack and the menu had no way out -- and without a reload
        # it is no longer a safety measure. It stays because cycling the theme
        # from the shell submap has always closed that menu, and a colour
        # change is a finished action: keeping it is today's behaviour, kept
        # on purpose rather than dropped as a side effect of this change.
        "$HYPRCTL" dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true
        "$HYPRCTL" eval 'require("hypr.themes.colors").apply_colors(); return "ok"' >/dev/null 2>&1 || true
        echo "hyprland: $palette pushed live (no reload)"
        record_applied hyprland immediate
    fi

    apply_transparency
}

# The window-transparency dial lives in the theme store, but Hyprland builds its
# opacity window rules once, when the config loads: HL.WindowRule exposes only
# set_enabled, so a rule's value cannot be changed after the fact. Re-reading
# the store therefore means re-reading the config.
#
# `hyprctl reload` is the only lever, and it is too blunt to run on every apply
# — the sun timer fires hourly and a reload is visible. So it runs only when the
# dial actually moved, tracked by a stamp beside the wallpaper cache.
apply_transparency() {
    # The mode-change path avoids any Hyprland reload; transparency does not
    # change with the mode, and a reload here would re-run the config and
    # disturb the scene engine.
    if [ -n "${HYPRFOCUS_NO_RELOAD-}" ]; then
        return
    fi

    local dial stamp previous
    dial=$(get transparency 1.0)
    stamp="${XDG_CACHE_HOME:-$HOME/.cache}/quantumfate/transparency.applied"
    previous=$([ -f "$stamp" ] && cat "$stamp" || echo "")

    if [ "$dial" = "$previous" ]; then
        echo "transparency: $dial (unchanged)"
        return
    fi

    mkdir -p "$(dirname "$stamp")"
    printf '%s' "$dial" >"$stamp"
    "$HYPRCTL" reload >/dev/null 2>&1 || true
    echo "transparency: $dial (reloaded)"
    record_applied transparency immediate
}

# A transparent bar over a high-contrast source image is unreadable, and the
# fix belongs here rather than in a wallpaper-picking rule: blur+desaturate+tint
# every wallpaper toward its palette's accent once, and hand awww the result
# instead of the original.
#
# Per-output blur sigma, falling back to the global wallpaper_blur, then 18.
get_monitor_blur() {
    local out=${1-} blur=""
    if [ -n "$out" ] && [ "$out" != "*" ]; then
        blur=$(jq -r --arg o "$out" '.wallpaper_blurs[$o] // empty' "$STATE" 2>/dev/null || true)
    fi
    if [ -z "$blur" ]; then
        blur=$(get wallpaper_blur 18)
    fi
    case "$blur" in
    '' | *[!0-9]*) blur=18 ;;
    esac
    if [ "$blur" -gt 48 ]; then blur=48; fi
    printf '%s' "$blur"
}

# Cached by source mtime rather than content hash — a stat is free and a
# wallpaper file does not change without its mtime moving. The stamp also
# carries the accent role and the blur sigma: two modes leasing the same
# palette can still tint toward different accents, and the `wallpaper_blur`
# dial changes the sigma, so either must re-render even though the source
# file did not move. The stamp file next to the render is what makes an
# unchanged source-and-role-and-blur a no-op on the next apply.
process_wallpaper() {
    local palette=$1 wall=$2 role=$3 out=${4-} blur
    have "$MAGICK" || {
        printf '%s' "$wall"
        return
    }
    # The blur dial is a store option (`wallpaper_blurs[out]`, falling back to
    # `wallpaper_blur`, default 18 = the 0x12 sigma this step has always used).
    # 0 means "no blur at all" — a source image the user wants straight — so it
    # must skip the flag, not pass a 0-sigma one; anything non-numeric falls back
    # like an unset key.
    blur=$(get_monitor_blur "$out")
    local name="${wall##*/}"
    local out_dir="$CACHE/$palette"
    local cached
    if [ -n "$out" ] && [ "$out" != "*" ]; then
        cached="$out_dir/${out}_${name}"
    else
        cached="$out_dir/$name"
    fi
    local stamp="$cached.mtime"
    local src_mtime stamp_key blur_flag=()
    src_mtime=$(stat -c %Y "$wall" 2>/dev/null || echo 0)
    stamp_key="$src_mtime:$role:$blur"
    [ "$blur" -gt 0 ] && blur_flag=(-blur "0x$(printf %x "$blur")")

    if [ -f "$cached" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$stamp_key" ]; then
        printf '%s' "$cached"
        return
    fi

    mkdir -p "$out_dir"
    local accent
    accent=$(accent_hex "$palette" "$role")
    # Blur hides detail a bar would otherwise sit on top of; the modulate call
    # desaturates without flattening to grey; colorize is the tint toward the
    # palette's accent that makes the result read as "this palette" at a glance.
    if "$MAGICK" "$wall" "${blur_flag[@]}" -modulate 100,50,100 -fill "$accent" -colorize 25% "$cached" 2>/dev/null; then
        printf '%s' "$stamp_key" >"$stamp"
        printf '%s' "$cached"
    else
        rm -f "$cached" "$stamp"
        printf '%s' "$wall"
    fi
}

# --- wallpaper sets and per-monitor picks ------------------------------------
#
# Sets live per palette (`hypr/wallpapers/<palette>/*`, i.e. this repo's own
# `wallpapers/<palette>/*` — the config root IS the repo, symlinked in by
# `ansible/roles/hypr`). An image may belong to several palettes; that's a
# symlink from one palette's folder to another's file, not a second copy or a
# shared/ bucket — `find`ing a palette's own folder is then always the whole
# answer for that palette, with no union step anywhere else that reads it.

WALLPAPER_GLOB=(-iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png')

# --- fit: does an image belong on this output? -------------------------------
#
# A palette's folder is one pool; every monitor draws from it at random, but
# only from the images whose real pixel size actually fits that monitor's
# geometry. Two numbers decide fit, chosen to keep a crop-to-fill sane without
# rejecting ordinary photos shot a little off the output's exact ratio:
#
#   FIT_ASPECT_TOLERANCE  0.20  the image's aspect ratio may differ from the
#                                output's by at most 20% (relative) — an
#                                ultrawide (32:9 ≈ 3.56) and a 16:9 (≈1.78) or
#                                16:10 (1.6) output differ by 100%+, so they
#                                never cross; a 3:2 photo (1.5) on a 16:10
#                                output (1.6) differs by ~6% and passes.
#   FIT_MIN_SCALE          0.5  after aspect-matched scaling, the image must
#                                supply at least half the output's width and
#                                half its height — anything smaller would be
#                                upscaled more than 2x to cover the screen.
#
# Both are documented here rather than buried in the arithmetic below because
# they are a product decision, not an implementation detail.
FIT_ASPECT_TOLERANCE=0.20
FIT_MIN_SCALE=0.5

# The output's live pixel size as "WxH". THEME_OUTPUT_SIZES (space-separated
# "NAME:WxH" tokens) is the test injection, the same pattern as THEME_OUTPUTS —
# hyprctl addresses the live session, so a test must be able to force sizes
# without a real monitor. Empty/unknown output geometry returns failure so
# callers can fail open (permissive) rather than reject on missing data.
output_size() {
    local out=$1 tok
    if [ -n "${THEME_OUTPUT_SIZES-}" ]; then
        for tok in $THEME_OUTPUT_SIZES; do
            [ "${tok%%:*}" = "$out" ] && {
                printf '%s' "${tok#*:}"
                return 0
            }
        done
        return 1
    fi
    sandboxed && return 1
    have hyprctl || return 1
    local dims
    dims=$(hyprctl monitors -j 2>/dev/null | jq -r --arg n "$out" '.[] | select(.name==$n) | "\(.width)x\(.height)"' 2>/dev/null)
    [ -n "$dims" ] || return 1
    printf '%s' "$dims"
}

# An image's real pixel size as "WxH", cached beside the wallpaper cache so
# listing a large pool stays cheap — keyed by the file's own path and mtime,
# so a replaced file re-measures itself. THEME_IMAGE_SIZES (space-separated
# "basename:WxH" tokens) is the test injection: fixtures in tests are not real
# images, so a test names their sizes instead of relying on `identify` to read
# pixels that are not there.
image_size() {
    local file=$1 tok
    if [ -n "${THEME_IMAGE_SIZES-}" ]; then
        for tok in $THEME_IMAGE_SIZES; do
            [ "${tok%%:*}" = "$(basename "$file")" ] && {
                printf '%s' "${tok#*:}"
                return 0
            }
        done
    fi
    have "$MAGICK" || return 1
    local dims_dir="$CACHE/.dims" key mtime cached
    key=$(printf '%s' "$file" | tr '/' '_')
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    cached="$dims_dir/$key.$mtime"
    if [ -f "$cached" ]; then
        cat "$cached"
        return 0
    fi
    dims=$("$MAGICK" identify -format '%wx%h' "$file" 2>/dev/null) || return 1
    [ -n "$dims" ] || return 1
    mkdir -p "$dims_dir" 2>/dev/null || true
    printf '%s' "$dims" >"$cached" 2>/dev/null || true
    printf '%s' "$dims"
}

# Whether $file fits $out. "*" (no known single geometry) and any output or
# image whose size cannot be determined both fail open — fit only bites once
# there is real geometry to check against, matching in_palette_set's own
# "cannot validate, so let it through" rule. Otherwise both FIT_ASPECT_TOLERANCE
# and FIT_MIN_SCALE must hold.
fits_output() {
    local file=$1 out=$2 idims odims iw ih ow oh
    [ "$out" = "*" ] && return 0
    idims=$(image_size "$file") || return 0
    odims=$(output_size "$out") || return 0
    [ -n "$idims" ] && [ -n "$odims" ] || return 0
    iw=${idims%x*} ih=${idims#*x}
    ow=${odims%x*} oh=${odims#*x}
    case "$iw$ih$ow$oh" in *[!0-9]*) return 0 ;; esac
    [ "$iw" -gt 0 ] && [ "$ih" -gt 0 ] && [ "$ow" -gt 0 ] && [ "$oh" -gt 0 ] || return 0
    awk -v iw="$iw" -v ih="$ih" -v ow="$ow" -v oh="$oh" \
        -v tol="$FIT_ASPECT_TOLERANCE" -v minscale="$FIT_MIN_SCALE" 'BEGIN {
        ia = iw / ih; oa = ow / oh
        diff = (ia > oa) ? (ia - oa) / oa : (oa - ia) / oa
        sw = iw / ow; sh = ih / oh
        scale = (sw < sh) ? sw : sh
        exit (diff <= tol && scale >= minscale) ? 0 : 1
    }'
}

# $palette's set, filtered to the subset that fits $out — the pool every
# per-output pick and cycle actually draws from. Unfiltered ("*", or an output
# with no known geometry) is the whole set, unchanged.
palette_fitting_files() {
    local palette=$1 out=$2 f
    palette_wallpaper_files "$palette" | while IFS= read -r f; do
        if fits_output "$f" "$out"; then printf '%s\n' "$f"; fi
    done
}

# The monitor names a wallpaper pick applies to. THEME_OUTPUTS (space
# separated) is the test injection, the same pattern as THEME_HOUR — hyprctl
# addresses the live session by name, so a test must be able to force a fixed
# set of monitors without querying one. Empty (no override, no live hyprctl,
# or sandboxed) means "one virtual output", printed as nothing here and
# handled by callers as the "*" fallback — the single-wallpaper-for-everything
# shape every existing binding and test already assumes.
outputs_list() {
    if [ -n "${THEME_OUTPUTS-}" ]; then
        printf '%s' "$THEME_OUTPUTS"
        return
    fi
    sandboxed && return 0
    have hyprctl || return 0
    hyprctl monitors -j 2>/dev/null | jq -r '.[].name' | tr '\n' ' '
}

# A palette's own wallpaper set, sorted by name (the `list` order; cycling
# order is the separate shuffle below). Symlinks count — that's how a shared
# image joins a second palette.
palette_wallpaper_files() {
    local palette=$1 dir="$CONFIG/hypr/wallpapers/$palette"
    [ -d "$dir" ] || return 0
    find -L "$dir" -maxdepth 1 -type f \( "${WALLPAPER_GLOB[@]}" \) 2>/dev/null | sort
}

# A path relative to the wallpapers root, when it is under one — otherwise
# unchanged (an absolute path bound from outside the set, the pre-palette-
# folders shape every existing test still uses).
relativize() {
    local f=$1 dir=$2
    case "$f" in
    "$dir"/*) printf '%s' "${f#"$dir"/}" ;;
    *) printf '%s' "$f" ;;
    esac
}

# Whether $file is a member of $palette's own set — by path, not by name, so a
# same-named file elsewhere does not pass. A palette with no set folder yet
# (a host mid-migration, or a test's scratch layout) cannot be validated
# against, so it is let through rather than refused: the membership rule only
# bites once the folder exists.
in_palette_set() {
    local file=$1 palette=$2 dir="$CONFIG/hypr/wallpapers/$palette"
    [ -d "$dir" ] || return 0
    [ "$file" = "$dir/$(basename "$file")" ] && [ -e "$file" ]
}

# Which wallpaper this palette shows on one monitor: the per-output binding,
# then the palette's "*" (every-monitor) binding, then the legacy single
# fallback, then <palette>.jpg. Wallpapers belong to palettes, not to modes, so
# a mode changes the wallpaper only by leasing a palette. A palette with none
# of those is legitimate configuration, so the last fallback is a random pick
# — the palette's own set if it has a folder, else the whole flat directory
# (a pre-migration host) — rather than an error. The pick is not persisted: a
# binding is a user decision, and applying it instead of forgetting it would
# re-roll on every palette switch. Shared with `status` and `list` so none of
# the three can ever disagree about what is bound.
resolve_wallpaper() {
    local palette=$1 output=${2:-*} wall dir="$CONFIG/hypr/wallpapers" raw kind
    raw=$(jq -c --arg p "$palette" '.wallpapers[$p] // empty' "$STATE" 2>/dev/null)
    if [ -n "$raw" ]; then
        kind=$(printf '%s' "$raw" | jq -r 'type')
        if [ "$kind" = "string" ]; then
            # The pre-per-output shape: one binding for every monitor.
            wall=$(printf '%s' "$raw" | jq -r '.')
        else
            wall=$(printf '%s' "$raw" | jq -r --arg o "$output" '.[$o] // .["*"] // ""')
            # The "any value in the map" fallback applies only to the "*"
            # pseudo-output (no live/injected monitor list — the single-
            # virtual-output shape) picking something out of a map that has
            # only named entries. A real named output with no entry of its
            # own must NOT borrow another real monitor's specific pick — that
            # was LEO-365's bug: HDMI-A-1 and DP-2 had no binding yet, fell
            # into `[.[]] | first`, and both got DP-1's file, so every
            # monitor showed the same wallpaper. A named output with nothing
            # bound falls through to the palette-level defaults below
            # instead, same as an empty map.
            if [ -z "$wall" ] && [ "$output" = "*" ]; then
                wall=$(printf '%s' "$raw" | jq -r '[.[]] | first // ""')
            fi
        fi
    fi
    [ -n "${wall-}" ] || wall=$(get wallpaper "")
    if [ -n "$wall" ]; then
        # A bound name with no leading "/" is either bare (LEO-372:
        # `theme.json` stored `Clearnight.jpg`, not a path) or the new
        # `<palette>/<file>` shape — both resolve against the wallpapers root.
        case "$wall" in
        /*) : ;;
        *) wall="$dir/$wall" ;;
        esac
        # A binding that does not exist on disk must not fail the whole
        # resolution: fall through to the next step instead, same as no
        # binding at all.
        [ -f "$wall" ] || wall=""
    fi
    if [ -z "$wall" ]; then
        for candidate in "$dir/$palette.jpg" "$dir/$palette.png"; do
            [ -f "$candidate" ] && {
                wall=$candidate
                break
            }
        done
    fi
    if [ -z "$wall" ]; then
        if [ -d "$dir/$palette" ]; then
            # Scoped to $output's own fitting subset first, so an unbound
            # monitor's random pick still respects its aspect/size (the same
            # pool `next`/`prev`/`random` draw from) instead of a set-wide
            # pick that could land a portrait case image on an ultrawide.
            # Falls back to the whole set only when nothing in it fits.
            wall=$(palette_fitting_files "$palette" "$output" | shuf -n 1)
            [ -n "$wall" ] || wall=$(palette_wallpaper_files "$palette" | shuf -n 1)
        fi
        [ -n "$wall" ] || wall=$(find "$dir" -maxdepth 1 -type f \( "${WALLPAPER_GLOB[@]}" \) 2>/dev/null | shuf -n 1)
    fi
    printf '%s' "$wall"
}

# --- the shuffle --------------------------------------------------------------
#
# One shuffled order per (palette, output) — `wallpaper_shuffle[P].orders[O]` —
# because fit now scopes the pool per output: two monitors of different shape
# draw from different fitting subsets of the same palette folder, so they
# cannot share one order. `pos[O]` says where that monitor sits in its own
# order. Persisted in theme.json, so the order survives across script
# invocations for as long as its fitting subset does not change — that is what
# "deterministic per session" means here: not reseeded on every call, only
# when the subset changes or the order is exhausted.
shuffle_order() {
    jq -c --arg p "$1" --arg o "$2" '.wallpaper_shuffle[$p].orders[$o] // []' "$STATE" 2>/dev/null || echo '[]'
}

shuffle_pos() {
    jq -r --arg p "$1" --arg o "$2" '.wallpaper_shuffle[$p].pos[$o] // -1' "$STATE" 2>/dev/null || echo -1
}

# $1 = palette, $2 = output, $3.. = the fitting subset's file names. Writes and
# returns a fresh order for that output alone.
reshuffle() {
    local palette=$1 out=$2 order
    shift 2
    order=$(printf '%s\n' "$@" | shuf | jq -R -s 'split("\n") | map(select(length > 0))')
    put "$(jq -n --arg p "$palette" --arg o "$out" --argjson ord "$order" '{wallpaper_shuffle: {($p): {orders: {($o): $ord}}}}')"
    printf '%s' "$order"
}

# Ensures $out's persisted order still names exactly its current fitting
# subset (a file added, removed, or newly fitting/unfitting invalidates it),
# reshuffling if not. $3.. are that subset's file names. Returns the (possibly
# just-written) order as JSON.
current_shuffle_order() {
    local palette=$1 out=$2 order have want
    shift 2
    order=$(shuffle_order "$palette" "$out")
    have=$(printf '%s' "$order" | jq 'sort')
    want=$(printf '%s\n' "$@" | jq -R -s 'split("\n") | map(select(length > 0)) | sort')
    if [ "$have" = "$want" ]; then
        printf '%s' "$order"
    else
        reshuffle "$palette" "$out" "$@"
    fi
}

# One image per monitor: each output in outputs_list() gets its own resolve
# and its own `awww img --outputs`. With no known outputs (no THEME_OUTPUTS,
# no live hyprctl, or sandboxed) this loops once over the "*" pseudo-output —
# the single-wallpaper-for-everything shape every pre-multi-monitor binding
# and test still uses, so the label stays plain "wallpaper" for it and only
# gains a "[NAME]" tag for a real, named output.
apply_wallpaper() {
    local palette=$1 role=$2 outs out
    local -a outs_arr
    outs=$(outputs_list)
    [ -n "$outs" ] || outs='*'
    # Word-split into an array rather than an unquoted `for out in $outs`: the
    # "*" fallback is a literal token here, not a glob, and an unquoted
    # expansion would have the shell replace it with the working directory's
    # file listing.
    read -r -a outs_arr <<<"$outs"
    for out in "${outs_arr[@]}"; do
        apply_wallpaper_output "$palette" "$role" "$out"
    done
}

apply_wallpaper_output() {
    local palette=$1 role=$2 out=$3 wall label="wallpaper"
    [ "$out" = "*" ] || label="wallpaper[$out]"
    # If this palette is currently active, keep what is already on this monitor
    # unless an explicit binding overrides it — a blur adjustment or re-apply
    # must not re-roll the wallpaper.
    local bound
    bound=$(jq -r --arg p "$palette" --arg o "$out" '.wallpapers[$p][$o] // empty' "$STATE" 2>/dev/null || true)
    if [ -n "$bound" ]; then
        wall=$(resolve_wallpaper "$palette" "$out")
    elif [ "$palette" = "$(resolve)" ]; then
        local live_file
        live_file=$(displayed_wallpaper "$out")
        if [ -n "$live_file" ]; then
            if [ -f "$CONFIG/hypr/wallpapers/$palette/$live_file" ]; then
                wall="$CONFIG/hypr/wallpapers/$palette/$live_file"
            elif [ -f "$CONFIG/hypr/wallpapers/$live_file" ]; then
                wall="$CONFIG/hypr/wallpapers/$live_file"
            fi
        fi
    fi
    [ -n "${wall-}" ] || wall=$(resolve_wallpaper "$palette" "$out")
    [ -n "$wall" ] && [ -f "$wall" ] || {
        echo "$label: unchanged"
        record_failed "$label" "no wallpaper bound to the palette and no default found"
        return
    }
    wall=$(process_wallpaper "$palette" "$wall" "$role" "$out")
    # Unlike MAGICK, calling the real awww has a live-session side effect (it
    # would actually repaint the desk), so sandboxed() still holds it back —
    # except when a test has pointed AWWW at its own recorder, the same
    # exception GSETTINGS gets in apply_gtk. A bare sandboxed run with no
    # THEME_AWWW override therefore never touches the real binary.
    if sandboxed && [ -z "${THEME_AWWW-}" ]; then
        echo "$label: skipped (sandboxed)"
        return
    fi
    have "$AWWW" || {
        echo "$label: awww not available"
        record_failed "$label" "awww not installed"
        return
    }
    # `img` is a no-op against a dead daemon. The session unit
    # (session/systemd/awww-daemon.service) starts it at login, so this is a
    # fallback for a daemon that died or a session the unit never reached —
    # `query` is how both swww and awww probe for that.
    "$AWWW" query >/dev/null 2>&1 || {
        "$AWWW_DAEMON" >/dev/null 2>&1 &
        disown
        sleep 0.3
    }
    # step/fps stand in for the 240ms crossfade the focus-modes spec calls
    # for — awww has no direct duration knob, only step size and frame rate.
    local outflag=()
    [ "$out" = "*" ] || outflag=(--outputs "$out")
    "$AWWW" img "$wall" "${outflag[@]}" --transition-type simple --transition-step 2 --transition-fps 30 >/dev/null 2>&1 || true
    echo "$label: ${wall##*/}"
    record_applied "$label" immediate
}

# The mode currently holding the lease's declared accent role (one
# store, `hyprfocus.json`'s `.modes[mode].presentation.accent_role`, read the
# same way `hypr/themes/colors.lua`'s `resolve_accent` reads it for window
# borders — so the bar, the borders and these adapters can never disagree).
# Falls back to "mauve" exactly like the Lua reader does: a fresh desk or a
# mode with no declared role must still resolve to something installed.
#
# $1 is the resolved palette, for the contrast guard it shares with the Lua
# reader: on the light latte palette only mauve and blue clear the
# accent-on-base target, so any other declared role stands in as mauve there;
# the dark palettes pass every role. None of the callers pass a palette when
# the guard cannot know it — it is withheld, not guessed.
accent_role() {
    local mode palette=${1-} role
    mode=$(lease_state)
    role=$(jq -r --arg m "$mode" '.modes[$m].presentation.accent_role // "mauve"' "$DECLARATION" 2>/dev/null || printf 'mauve')
    if [ "$palette" = latte ] && [ "$role" != mauve ] && [ "$role" != blue ]; then
        role=mauve
    fi
    printf '%s' "$role"
}

# The accent colour for a palette+role pair, matching the tables
# `hypr/themes/*.lua` and Theme.qml both carry. Duplicated here because a
# shell script cannot require Lua or QML; asserted against those tables by
# `tests/theme_test.sh` rather than left to drift. An unknown role falls back
# to the palette's own mauve; an unknown palette falls back to macchiato's,
# matching `baseline`'s own default.
# The Catppuccin palette, by flavour and role, and the ONLY place this script
# names a colour. Every adapter that has to spell a hex out -- the shell
# palette, rofi, wlogout, the cursor border -- reads it from here, so a flavour
# cannot be half-applied by one surface carrying its own copy.
accent_hex() {
    local palette=$1 role=${2:-mauve}
    case "$palette:$role" in
    latte:rosewater) printf '#dc8a78' ;;
    latte:flamingo) printf '#dd7878' ;;
    latte:pink) printf '#ea76cb' ;;
    latte:mauve) printf '#8839ef' ;;
    latte:red) printf '#d20f39' ;;
    latte:maroon) printf '#e64553' ;;
    latte:peach) printf '#fe640b' ;;
    latte:yellow) printf '#df8e1d' ;;
    latte:green) printf '#40a02b' ;;
    latte:teal) printf '#179299' ;;
    latte:sky) printf '#04a5e5' ;;
    latte:sapphire) printf '#209fb5' ;;
    latte:blue) printf '#1e66f5' ;;
    latte:lavender) printf '#7287fd' ;;
    latte:text) printf '#4c4f69' ;;
    latte:subtext1) printf '#5c5f77' ;;
    latte:subtext0) printf '#6c6f85' ;;
    latte:overlay2) printf '#7c7f93' ;;
    latte:overlay1) printf '#8c8fa1' ;;
    latte:overlay0) printf '#9ca0b0' ;;
    latte:surface2) printf '#acb0be' ;;
    latte:surface1) printf '#bcc0cc' ;;
    latte:surface0) printf '#ccd0da' ;;
    latte:base) printf '#eff1f5' ;;
    latte:mantle) printf '#e6e9ef' ;;
    latte:crust) printf '#dce0e8' ;;
    frappe:rosewater) printf '#f2d5cf' ;;
    frappe:flamingo) printf '#eebebe' ;;
    frappe:pink) printf '#f4b8e4' ;;
    frappe:mauve) printf '#ca9ee6' ;;
    frappe:red) printf '#e78284' ;;
    frappe:maroon) printf '#ea999c' ;;
    frappe:peach) printf '#ef9f76' ;;
    frappe:yellow) printf '#e5c890' ;;
    frappe:green) printf '#a6d189' ;;
    frappe:teal) printf '#81c8be' ;;
    frappe:sky) printf '#99d1db' ;;
    frappe:sapphire) printf '#85c1dc' ;;
    frappe:blue) printf '#8caaee' ;;
    frappe:lavender) printf '#babbf1' ;;
    frappe:text) printf '#c6d0f5' ;;
    frappe:subtext1) printf '#b5bfe2' ;;
    frappe:subtext0) printf '#a5adce' ;;
    frappe:overlay2) printf '#949cbb' ;;
    frappe:overlay1) printf '#838ba7' ;;
    frappe:overlay0) printf '#737994' ;;
    frappe:surface2) printf '#626880' ;;
    frappe:surface1) printf '#51576d' ;;
    frappe:surface0) printf '#414559' ;;
    frappe:base) printf '#303446' ;;
    frappe:mantle) printf '#292c3c' ;;
    frappe:crust) printf '#232634' ;;
    macchiato:rosewater) printf '#f4dbd6' ;;
    macchiato:flamingo) printf '#f0c6c6' ;;
    macchiato:pink) printf '#f5bde6' ;;
    macchiato:mauve) printf '#c6a0f6' ;;
    macchiato:red) printf '#ed8796' ;;
    macchiato:maroon) printf '#ee99a0' ;;
    macchiato:peach) printf '#f5a97f' ;;
    macchiato:yellow) printf '#eed49f' ;;
    macchiato:green) printf '#a6da95' ;;
    macchiato:teal) printf '#8bd5ca' ;;
    macchiato:sky) printf '#91d7e3' ;;
    macchiato:sapphire) printf '#7dc4e4' ;;
    macchiato:blue) printf '#8aadf4' ;;
    macchiato:lavender) printf '#b7bdf8' ;;
    macchiato:text) printf '#cad3f5' ;;
    macchiato:subtext1) printf '#b8c0e0' ;;
    macchiato:subtext0) printf '#a5adcb' ;;
    macchiato:overlay2) printf '#939ab7' ;;
    macchiato:overlay1) printf '#8087a2' ;;
    macchiato:overlay0) printf '#6e738d' ;;
    macchiato:surface2) printf '#5b6078' ;;
    macchiato:surface1) printf '#494d64' ;;
    macchiato:surface0) printf '#363a4f' ;;
    macchiato:base) printf '#24273a' ;;
    macchiato:mantle) printf '#1e2030' ;;
    macchiato:crust) printf '#181926' ;;
    mocha:rosewater) printf '#f5e0dc' ;;
    mocha:flamingo) printf '#f2cdcd' ;;
    mocha:pink) printf '#f5c2e7' ;;
    mocha:mauve) printf '#cba6f7' ;;
    mocha:red) printf '#f38ba8' ;;
    mocha:maroon) printf '#eba0ac' ;;
    mocha:peach) printf '#fab387' ;;
    mocha:yellow) printf '#f9e2af' ;;
    mocha:green) printf '#a6e3a1' ;;
    mocha:teal) printf '#94e2d5' ;;
    mocha:sky) printf '#89dceb' ;;
    mocha:sapphire) printf '#74c7ec' ;;
    mocha:blue) printf '#89b4fa' ;;
    mocha:lavender) printf '#b4befe' ;;
    mocha:text) printf '#cdd6f4' ;;
    mocha:subtext1) printf '#bac2de' ;;
    mocha:subtext0) printf '#a6adc8' ;;
    mocha:overlay2) printf '#9399b2' ;;
    mocha:overlay1) printf '#7f849c' ;;
    mocha:overlay0) printf '#6c7086' ;;
    mocha:surface2) printf '#585b70' ;;
    mocha:surface1) printf '#45475a' ;;
    mocha:surface0) printf '#313244' ;;
    mocha:base) printf '#1e1e2e' ;;
    mocha:mantle) printf '#181825' ;;
    mocha:crust) printf '#11111b' ;;
    latte:*) printf '#8839ef' ;;
    frappe:*) printf '#ca9ee6' ;;
    mocha:*) printf '#cba6f7' ;;
    *) printf '#c6a0f6' ;;
    esac
}

# --- commands ----------------------------------------------------------------

cmd_apply() {
    local palette baseline role
    palette=$(resolve)
    baseline=$(baseline)
    # The accent role belongs to whichever mode holds the lease right now
    # (accent_role(), the store field a mode declares) — resolved once so every
    # accent-bearing adapter below tints toward the same colour.
    role=$(accent_role "$palette")
    # Keep the BASELINE in the store so the shell and the script never
    # disagree about what the desk shows with no lease held, even in auto
    # mode. A lease is never written here: a mode holds a palette the way it
    # holds a window, and when the mode ends the store still points at what
    # the sun (or the user) chose — a mode must not bury the baseline.
    # `resolved` carries the palette in effect right now — the lease's when a
    # mode holds one, the baseline otherwise — for readers that cannot run the
    # lease resolver themselves (nvim follows the store directly); the socket
    # pokes below use this same value, so every editor switches to one palette.
    put "$(jq -n --arg p "$baseline" --arg r "$palette" '{palette: $p, resolved: $r}')"

    apply_kitty "$palette"
    apply_nvim "$palette"
    apply_gtk "$palette"
    apply_qt "$palette"
    apply_hyprland "$palette"
    apply_cursor "$palette"
    apply_btop "$palette"
    apply_yazi "$palette"
    apply_zathura "$palette"
    apply_rofi "$palette"
    apply_wlogout "$palette" "$role"
    apply_zen "$palette" "$role"
    apply_obsidian "$palette" "$role"
    apply_linear "$palette"
    apply_shell "$palette"
    apply_wallpaper "$palette" "$role"

    # Last, so it reflects every applier above it. A sandboxed run records
    # nothing real, so it writes nothing — a test must not leave a result file
    # claiming the desk changed.
    sandboxed || write_result
}

cmd_set() {
    local palette=${1-}
    [ -n "$palette" ] || die "set needs a palette: ${PALETTES[*]}"
    is_palette "$palette" || die "unknown palette '$palette' (have: ${PALETTES[*]})"
    # An explicit pick outlasts the next sunrise. `auto` is how you undo that.
    put "$(jq -n --arg p "$palette" '{palette: $p, mode: "manual"}')"
    cmd_apply
}

cmd_auto() {
    put '{"mode": "auto"}'
    cmd_apply
}

cmd_toggle() {
    local current day night
    current=$(resolve)
    day=$(get day latte)
    night=$(get night macchiato)
    if [ "$current" = "$day" ]; then cmd_set "$night"; else cmd_set "$day"; fi
}

# Bind a wallpaper to a palette: `,theme.sh wallpaper <file> [palette]`. A
# palette that has its own set folder refuses a file from outside it — the
# membership in_palette_set() checks. Binds to every currently known output
# (or the "*" fallback), same image everywhere, since the caller named no
# monitor; `next`/`prev`/`random` below are how a monitor gets its own pick.
cmd_wallpaper() {
    local file=${1-} palette=${2-} abs rel outs out patch='{}'
    [ -n "$file" ] || die "wallpaper needs a file"
    [ -f "$file" ] || die "no such file: $file"
    [ -n "$palette" ] || palette=$(resolve)
    is_palette "$palette" || die "unknown palette '$palette'"
    abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
    in_palette_set "$abs" "$palette" || die "$file is not in $palette's wallpaper set"
    rel=$(relativize "$abs" "$CONFIG/hypr/wallpapers")
    outs=$(outputs_list)
    for out in $outs; do
        fits_output "$abs" "$out" || die "$file does not fit output $out"
    done
    if [ -z "$outs" ]; then
        patch=$(jq -n --arg f "$rel" '{"*": $f}')
    else
        for out in $outs; do
            patch=$(jq -n --argjson base "$patch" --arg o "$out" --arg f "$rel" '$base * {($o): $f}')
        done
    fi
    put "$(jq -n --arg p "$palette" --argjson m "$patch" '{wallpapers: {($p): $m}}')"
    echo "wallpaper: $palette -> ${file##*/}"
    cmd_apply
}

# Returns the basename of the image currently displayed on an output by awww.
displayed_wallpaper() {
    local out=$1 line img
    have "$AWWW" || return 0
    sandboxed && [ -z "${THEME_AWWW-}" ] && return 0
    line=$("$AWWW" query 2>/dev/null | grep -E "^: $out:" || true)
    [ -n "$line" ] || return 0
    img=${line##*currently displaying: image: }
    [ -n "$img" ] || return 0
    img=$(printf '%s' "$img" | tr -d '\r\n')
    img=${img##*/}
    img=${img#"${out}_"}
    printf '%s' "$img"
}

# `,theme.sh wallpaper list [P]`: the palette's set and each known monitor's
# current pick, as JSON — `{palette, monitors: {NAME: {current, index, blur}}, count,
# items}`. Shared resolve_wallpaper/palette_wallpaper_files with the cycle
# commands and `status`, so none of them can disagree about what is bound.
cmd_wallpaper_list() {
    local palette=$1 outs out items count monitors='{}' names
    local -a outs_arr
    names=$(palette_wallpaper_files "$palette")
    items=$(printf '%s\n' "$names" | jq -R -s --arg p "$palette" \
        'split("\n") | map(select(length > 0) | (split("/") | last) | {name: ., file: ($p + "/" + .)})')
    count=$(printf '%s' "$items" | jq 'length')
    outs=$(outputs_list)
    [ -n "$outs" ] || outs='*'
    read -r -a outs_arr <<<"$outs" # see apply_wallpaper: "*" is a literal, not a glob
    for out in "${outs_arr[@]}"; do
        local cur idx=-1 rel=null fits live_file b
        cur=$(resolve_wallpaper "$palette" "$out")
        if [ "$palette" = "$(resolve)" ]; then
            live_file=$(displayed_wallpaper "$out")
            if [ -n "$live_file" ]; then
                if [ -f "$CONFIG/hypr/wallpapers/$palette/$live_file" ]; then
                    cur="$CONFIG/hypr/wallpapers/$palette/$live_file"
                elif [ -f "$CONFIG/hypr/wallpapers/$live_file" ]; then
                    cur="$CONFIG/hypr/wallpapers/$live_file"
                fi
            fi
        fi
        if [ -n "$cur" ] && [ -f "$cur" ]; then
            rel=$(jq -n --arg f "$(relativize "$cur" "$CONFIG/hypr/wallpapers")" '$f')
            idx=$(printf '%s' "$items" | jq --arg n "$(basename "$cur")" '[.[].name] | index($n) // -1')
        fi
        b=$(get_monitor_blur "$out")
        # Which of the pool's own images fit this output — the same subset
        # next/prev/random draw from.
        fits=$(palette_fitting_files "$palette" "$out" | jq -R -s 'split("\n") | map(select(length > 0) | (split("/") | last))')
        monitors=$(jq -n --argjson base "$monitors" --arg o "$out" --argjson f "$rel" --argjson i "$idx" --argjson fits "$fits" --argjson b "$b" \
            '$base * {($o): {current: $f, index: $i, fits: $fits, blur: $b}}')
    done
    jq -n --arg p "$palette" --argjson monitors "$monitors" --argjson items "$items" --argjson count "$count" \
        '{palette: $p, monitors: $monitors, count: $count, items: $items}'
}

# `,theme.sh wallpaper next|prev|random [P] [--output NAME]`: advances one or
# every known monitor through $palette's shuffled set (random: an independent
# random pick, not a step in the shuffle), saves the choice per output, and
# repaints only if $palette is the one currently resolved — a cycle on a
# palette nobody is showing just updates what it would show next.
cmd_wallpaper_cycle() {
    local op=$1 palette=$2 only_output=$3 outs out
    local -a outs_arr
    outs=${only_output:-$(outputs_list)}
    [ -n "$outs" ] || outs='*'
    read -r -a outs_arr <<<"$outs" # see apply_wallpaper: "*" is a literal, not a glob
    for out in "${outs_arr[@]}"; do
        cycle_one_output "$op" "$palette" "$out"
    done
    if [ "$palette" = "$(resolve)" ]; then
        apply_wallpaper "$palette" "$(accent_role "$palette")"
    fi
    sandboxed || write_result
}

cycle_one_output() {
    local op=$1 palette=$2 out=$3
    local -a files
    mapfile -t files < <(palette_fitting_files "$palette" "$out")
    local len=${#files[@]}
    if [ "$len" -eq 0 ]; then
        # Nothing in the pool fits — honest, not silently stretched: report it
        # and leave this output's current wallpaper alone (no put() below).
        local odims
        odims=$(output_size "$out" 2>/dev/null || echo "unknown size")
        echo "wallpaper[$out]: nothing in $palette's set fits $out ($odims)"
        record_failed "wallpaper:$out" "no wallpapers in $palette's set fit $out ($odims)"
        RESULT_WALLPAPER+=("$(jq -n --arg p "$palette" --arg o "$out" --arg f "" --argjson i -1 --argjson c 0 \
            '{palette: $p, output: $o, file: $f, index: $i, count: $c}')")
        return
    fi
    local -a names=("${files[@]##*/}")
    local order pos idx newfile rel
    order=$(current_shuffle_order "$palette" "$out" "${names[@]}")
    pos=$(shuffle_pos "$palette" "$out")
    case "$op" in
    random)
        idx=$((RANDOM % len))
        ;;
    next)
        if [ "$pos" -lt 0 ] || [ "$((pos + 1))" -ge "$len" ]; then
            # Exhausted (or never started): a fresh shuffle, so a long-running
            # session cycles through the whole set before any repeat.
            order=$(reshuffle "$palette" "$out" "${names[@]}")
            idx=0
        else
            idx=$((pos + 1))
        fi
        ;;
    prev)
        if [ "$pos" -le 0 ]; then
            order=$(reshuffle "$palette" "$out" "${names[@]}")
            idx=$((len - 1))
        else
            idx=$((pos - 1))
        fi
        ;;
    esac
    newfile=$(printf '%s' "$order" | jq -r --argjson i "$idx" '.[$i]')
    rel="$palette/$newfile"
    put "$(jq -n --arg p "$palette" --arg o "$out" --arg f "$rel" '{wallpapers: {($p): {($o): $f}}}')"
    put "$(jq -n --arg p "$palette" --arg o "$out" --argjson i "$idx" '{wallpaper_shuffle: {($p): {pos: {($o): $i}}}}')"
    RESULT_WALLPAPER+=("$(jq -n --arg p "$palette" --arg o "$out" --arg f "$newfile" --argjson i "$idx" --argjson c "$len" \
        '{palette: $p, output: $o, file: $f, index: $i, count: $c}')")
    echo "wallpaper[$out]: $palette -> $newfile ($((idx + 1))/$len)"
}

# `,theme.sh wallpaper blur <sigma> [palette] [--output NAME]`: sets the blur
# sigma (0..48; 0 disables blur) for one monitor or globally, persists it to
# theme.json, and repaints live if $palette is currently resolved.
cmd_wallpaper_blur() {
    local sigma=$1 palette=$2 out=${3-}
    if [ -n "$out" ] && [ "$out" != "*" ]; then
        put "$(jq -n --arg o "$out" --argjson b "$sigma" '{wallpaper_blurs: {($o): $b}}')"
        echo "wallpaper_blur[$out]: $sigma"
        if [ "$palette" = "$(resolve)" ]; then
            apply_wallpaper_output "$palette" "$(accent_role "$palette")" "$out"
        fi
    else
        put "$(jq -n --argjson b "$sigma" '{wallpaper_blur: $b}')"
        echo "wallpaper_blur: $sigma"
        if [ "$palette" = "$(resolve)" ]; then
            apply_wallpaper "$palette" "$(accent_role "$palette")"
        fi
    fi
    sandboxed || write_result
}

cmd_status() {
    printf 'store     %s\n' "$STATE"
    printf 'mode      %s\n' "$(get mode auto)"
    printf 'resolved  %s\n' "$(resolve)"
    printf 'kitty     %s\n' "$(readlink "$CONFIG/kitty/current-theme.conf" 2>/dev/null || echo unset)"
    have gsettings && printf 'gtk       %s\n' "$(gsettings get org.gnome.desktop.interface gtk-theme)"
    printf 'gtk3      %s\n' "$(sed -n 's|^gtk-theme-name=||p' "$CONFIG/gtk-3.0/settings.ini" 2>/dev/null || echo unset)"
    printf 'xsettingsd %s\n' "$(sed -n 's|^Net/ThemeName "\(.*\)"$|\1|p' "$CONFIG/xsettingsd/xsettingsd.conf" 2>/dev/null || echo unset)"
    printf 'qt6ct     %s\n' "$(sed -n 's/^color_scheme_path=.*\///p' "$CONFIG/qt6ct/qt6ct.conf" 2>/dev/null || echo unset)"
    printf 'kvantum   %s\n' "$(sed -n 's/^theme=//p' "$CONFIG/Kvantum/kvantum.kvconfig" 2>/dev/null || echo unset)"
    # Which wallpaper is bound, resolved the same way apply_wallpaper resolves
    # it — so `status` and an apply can never disagree about what is showing.
    printf 'wallpaper %s\n' "$(resolve_wallpaper "$(resolve)")"
}

case "${1-apply}" in
apply) cmd_apply ;;
set)
    shift
    cmd_set "${1-}"
    ;;
auto) cmd_auto ;;
toggle) cmd_toggle ;;
wallpaper)
    shift
    sub=${1-}
    case "$sub" in
    list | next | prev | random)
        shift
        palette="" output=""
        while [ $# -gt 0 ]; do
            case "$1" in
            --output)
                output=${2-}
                shift 2
                ;;
            *)
                palette=$1
                shift
                ;;
            esac
        done
        [ -n "$palette" ] || palette=$(resolve)
        is_palette "$palette" || die "unknown palette '$palette'"
        if [ "$sub" = "list" ]; then
            cmd_wallpaper_list "$palette"
        else
            cmd_wallpaper_cycle "$sub" "$palette" "$output"
        fi
        ;;
    blur)
        shift
        sigma=${1-} palette="" output=""
        [ -n "$sigma" ] || die "wallpaper blur requires a sigma (0..48)"
        case "$sigma" in
        '' | *[!0-9]*) die "invalid blur sigma '$sigma' — must be integer 0..48" ;;
        esac
        [ "$sigma" -gt 48 ] && sigma=48
        shift
        while [ $# -gt 0 ]; do
            case "$1" in
            --output)
                output=${2-}
                shift 2
                ;;
            *)
                palette=$1
                shift
                ;;
            esac
        done
        [ -n "$palette" ] || palette=$(resolve)
        is_palette "$palette" || die "unknown palette '$palette'"
        cmd_wallpaper_blur "$sigma" "$palette" "$output"
        ;;
    *)
        cmd_wallpaper "${1-}" "${2-}"
        ;;
    esac
    ;;
get)
    resolve
    echo
    ;;
status) cmd_status ;;
-h | --help | help) sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//' ;;
*) die "unknown command '${1}' — try --help" ;;
esac
