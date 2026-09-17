#!/usr/bin/env bash
# ,theme.sh — one palette, every surface.
#
# Quickshell and Hyprland watch $XDG_STATE_HOME/theme.json directly and react on
# their own. Everything else — kitty, GTK, Qt, Kvantum, the wallpaper — needs a
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

# The accent is not yet a store field: every surface below takes flavour+accent
# as one theme name, and only one accent is installed per flavour that matters.
ACCENT="mauve"

PALETTES=(latte frappe macchiato mocha)
# Which flavours are light. Drives GTK's color-scheme, which is a separate
# setting from the theme name and is what applications actually branch on.
LIGHT=(latte)

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
        '{ok: $ok, ts: $ts, adapter: $adapter, applied: $applied, pending: $pending, failed: $failed}' >"$tmp"
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
# the held mode, or "" at rest — a timed mode whose `until` already passed
# reads as neutral. Shared by both lease applications (the palette and the
# wallpaper) so two readers can never disagree about which mode is on.
lease_state() {
    local mode until until_ms file="$FOCUS"
    [ -f "$file" ] || { [ ! -f "$LEGACY_FOCUS" ] || file="$LEGACY_FOCUS"; }
    [ -f "$file" ] && mode=$(jq -r '.mode // "neutral"' "$file" 2>/dev/null) || mode=neutral
    until=$(jq -r '.until // ""' "$file" 2>/dev/null)
    if [ "$mode" != neutral ] && [ -n "$until" ]; then
        until_ms=$(date -d "$until" +%s%3N 2>/dev/null || echo 0)
        [ "$(date +%s%3N)" -gt "$until_ms" ] && mode=neutral
    fi
    printf '%s' "$mode"
}

# The palette a mode leases while it runs (LEO-288). The declaration names a
# day/night pair (or one palette for both) in the mode's `presentation`; the
# pointer (focus.json) says the mode is on, and a timed mode whose `until`
# already passed reads as neutral — the same rule the mode policy keeps
# everywhere else. The pair follows `daytime`, so the sun timer flips a mode's
# palette exactly as it flips the baseline. "" means no lease held, and an
# unknown lease palette reads as no lease: resolution never fails.
lease() {
    local mode palette half=night
    mode=$(lease_state)
    [ "$mode" != neutral ] || return 0
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
    echo "gtk: $theme ($scheme, $icons; settings.ini + xsettingsd + .gtkrc follow)"
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

# wlogout hardcodes the flavour inside every icon path.
apply_wlogout() {
    local palette=$1 theme css="$CONFIG/wlogout/style.css"
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" wlogout "$palette")
    [ -f "$css" ] || return 0
    [ -d "$CONFIG/wlogout/catppuccin/icons/wlogout/$theme" ] || return 0
    sed -i -E "s#(/wlogout/catppuccin/icons/wlogout/)[a-z]+/#\\1$theme/#g" "$css"
    echo "wlogout: $theme"
    record_applied wlogout immediate
}

# Zen reads user.js once at launch, so the prefs land on the next restart.
# The chrome CSS is also read at launch, but `,theme.sh` keeps the runtime
# palette file (`zen-palette.css`) in sync and overwrites the main CSS files
# from the repo assets so light/dark blocks are always present. A running Zen
# still needs a restart to pick up CSS changes, but the files are correct
# immediately.
apply_zen() {
    local palette=$1 accent
    local zen_dir="$CONFIG/zen-chezmoi"
    local js="$zen_dir/user.js"
    [ -f "$js" ] || return 0
    accent=$(accent_hex "$palette")

    sed -i "s|^user_pref(\"zen.theme.accent-color\".*|user_pref(\"zen.theme.accent-color\", \"$accent\");|" "$js"
    sed -i "s|^user_pref(\"layout.css.prefers-color-scheme.content-override\".*|user_pref(\"layout.css.prefers-color-scheme.content-override\", 3); // follow system|" "$js"
    sed -i "s|^user_pref(\"theme-better_find_bar-enable_custom_background\".*|user_pref(\"theme-better_find_bar-enable_custom_background\", false);|" "$js"

    # Overwrite the CSS from the repo assets so both light and dark blocks are
    # present and the accent is controlled by the runtime palette file.
    local asset_dir="$SCRIPT_DIR/../assets/zen"
    if [ -d "$asset_dir" ]; then
        install -m 644 "$asset_dir/userChrome.css" "$zen_dir/userChrome.css"
        install -m 644 "$asset_dir/userContent.css" "$zen_dir/userContent.css"
        printf '@media (prefers-color-scheme: light) { :root { --qf-accent: %s; } }\n@media (prefers-color-scheme: dark) { :root { --qf-accent: %s; } }\n' "$accent" "$accent" >"$zen_dir/zen-palette.css"
        chmod 644 "$zen_dir/zen-palette.css"
    fi

    echo "zen: $accent (user.js + CSS written; Zen restart required to see CSS)"
    record_pending zen next-launch "Zen reads user.js and CSS at launch"
}

# Obsidian reads its vault's appearance.json at launch, so this lands on the
# next restart — the same tier zen lives on. The mapping is the palette's
# accent and light-ness: the CSS theme stays Catppuccin (already chosen in the
# vault), which is what makes a manual retheme afterwards an error worth
# avoiding.
#
# The vault is nameable rather than discovered: a single declared vault keeps
# the adapter one edit behind the truth instead of guessing which of several
# looks themed. `bin/,obsidian-cli-wrapper.sh` names the same Main vault, so
# the two paths already agree on the source.
apply_obsidian() {
    local palette=$1 vault="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian/Main}" base appearance
    appearance="$vault/.obsidian/appearance.json"
    [ -f "$appearance" ] || {
        echo "obsidian: $appearance not found"
        record_failed obsidian "vault appearance.json not found"
        return 0
    }
    # `theme` is Obsidian's base-look key: moonstone wants a light palette,
    # obsidian a dark one — the same question is_light answers everywhere else.
    base=$(is_light "$palette" && echo moonstone || echo obsidian)
    if ! jq --arg base "$base" --arg accent "$(accent_hex "$palette")" \
        '.theme = $base | .accentColor = $accent' "$appearance" >"$appearance.tmp" ||
        ! mv -f "$appearance.tmp" "$appearance"; then
        record_failed obsidian "appearance.json is not writable"
        return 0
    fi
    echo "obsidian: $base + accent (applies on next launch)"
    record_pending obsidian next-launch "appearance.json is read at launch"
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
    local palette=$1 theme size
    theme=$(resolve_surface "$palette" "$(is_light "$palette" && echo light || echo dark)" "$ACCENT" cursor "catppuccin-$palette-$ACCENT-cursors")
    size=$(get cursor_size 28)
    if [ ! -d "/usr/share/icons/$theme" ] && [ ! -d "$HOME/.icons/$theme" ] && [ ! -d "$HOME/.local/share/icons/$theme" ]; then
        echo "cursor: $theme not installed"
        record_failed cursor "$theme not installed"
        return 0
    fi
    sandboxed && {
        echo "cursor: skipped (sandboxed)"
        return 0
    }
    systemctl --user set-environment "XCURSOR_THEME=$theme" "XCURSOR_SIZE=$size" 2>/dev/null || true
    have hyprctl && hyprctl setcursor "$theme" "$size" >/dev/null 2>&1 || true
    echo "cursor: $theme ($size)"
    record_applied cursor immediate
}

apply_hyprland() {
    local palette=$1
    sandboxed && {
        echo "hyprland: skipped (sandboxed)"
        return
    }
    have hyprctl || {
        echo "hyprland: not running"
        record_failed hyprland "not running"
        return
    }
    # Hyprland's colours come from its own config (hypr/themes/colors.lua reads
    # this same store), because `hyprctl keyword general:col.*` answers "unknown
    # request" on a Lua-configured Hyprland — and exits 0, so a script cannot
    # even tell it failed. Reloading re-runs that file against the new palette.
    #
    # Leave any submap FIRST. A reload re-executes the Lua config, which resets
    # the submap stack in hypr/lib/submap.lua while Hyprland is still runtime-in
    # a submap — so escape pops an empty stack and the keyboard is stuck in a
    # menu with no way out. Cycling the theme from the shell submap did exactly
    # that. hyprctl's dispatch argument is evaluated as Lua on this config.
    hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true
    hyprctl reload >/dev/null 2>&1 || true
    echo "hyprland: reloaded for $palette"
    record_applied hyprland immediate

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
    hyprctl reload >/dev/null 2>&1 || true
    echo "transparency: $dial (reloaded)"
    record_applied transparency immediate
}

# A transparent bar over a high-contrast source image is unreadable, and the
# fix belongs here rather than in a wallpaper-picking rule: blur+desaturate+tint
# every wallpaper toward its palette's accent once, and hand awww the result
# instead of the original.
#
# Cached by source mtime rather than content hash — a stat is free and a
# wallpaper file does not change without its mtime moving. The stamp file next
# to the render is what makes an unchanged source a no-op on the next apply.
process_wallpaper() {
    local palette=$1 wall=$2
    have "$MAGICK" || {
        printf '%s' "$wall"
        return
    }
    local name="${wall##*/}"
    local out_dir="$CACHE/$palette"
    local cached="$out_dir/$name"
    local stamp="$cached.mtime"
    local src_mtime
    src_mtime=$(stat -c %Y "$wall" 2>/dev/null || echo 0)

    if [ -f "$cached" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$src_mtime" ]; then
        printf '%s' "$cached"
        return
    fi

    mkdir -p "$out_dir"
    local accent
    accent=$(accent_hex "$palette")
    # Blur hides detail a bar would otherwise sit on top of; the modulate call
    # desaturates without flattening to grey; colorize is the tint toward the
    # palette's accent that makes the result read as "this palette" at a glance.
    if "$MAGICK" "$wall" -blur 0x12 -modulate 100,50,100 -fill "$accent" -colorize 25% "$cached" 2>/dev/null; then
        printf '%s' "$src_mtime" >"$stamp"
        printf '%s' "$cached"
    else
        rm -f "$cached" "$stamp"
        printf '%s' "$wall"
    fi
}

# Which wallpaper this palette should show: the palette binding, then the
# single fallback, then <palette>.jpg. Wallpapers belong to palettes, not to
# modes, so a mode changes the wallpaper only by leasing a palette. A palette
# with none of those is legitimate configuration, so the last fallback is a
# random pick from the wallpapers directory — the same semantics
# `,wallpaper.sh` gives a user who asked for anything — rather than an error.
# The pick is not persisted: a binding is a user decision, and applying it
# instead of forgetting it would re-roll on every palette switch. Shared with
# `status` so the two can never disagree about what is bound.
resolve_wallpaper() {
    local palette=$1 wall dir="$CONFIG/hypr/wallpapers"
    wall=$(jq -r --arg p "$palette" '.wallpapers[$p] // ""' "$STATE" 2>/dev/null || echo "")
    [ -n "$wall" ] || wall=$(get wallpaper "")
    if [ -n "$wall" ]; then
        # A bound name with no "/" is bare (LEO-372: `theme.json` stores
        # `Clearnight.jpg`, not a path) — resolve it against the wallpapers
        # directory before checking it exists.
        case "$wall" in
        */*) : ;;
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
        wall=$(find "$dir" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null |
            shuf -n 1)
    fi
    printf '%s' "$wall"
}

apply_wallpaper() {
    local palette=$1 wall
    wall=$(resolve_wallpaper "$palette")
    [ -n "$wall" ] && [ -f "$wall" ] || {
        echo "wallpaper: unchanged"
        record_failed wallpaper "no wallpaper bound to the palette and no default found"
        return
    }
    wall=$(process_wallpaper "$palette" "$wall")
    # Unlike MAGICK, calling the real awww has a live-session side effect (it
    # would actually repaint the desk), so sandboxed() still holds it back —
    # except when a test has pointed AWWW at its own recorder, the same
    # exception GSETTINGS gets in apply_gtk. A bare sandboxed run with no
    # THEME_AWWW override therefore never touches the real binary.
    if sandboxed && [ -z "${THEME_AWWW-}" ]; then
        echo "wallpaper: skipped (sandboxed)"
        return
    fi
    have "$AWWW" || {
        echo "wallpaper: awww not available"
        record_failed wallpaper "awww not installed"
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
    "$AWWW" img "$wall" --transition-type simple --transition-step 2 --transition-fps 30 >/dev/null 2>&1 || true
    echo "wallpaper: ${wall##*/}"
    record_applied wallpaper immediate
}

# The accent colour per flavour, matching Theme.qml's tables. Duplicated here
# because a shell script cannot read QML, and asserted against the real table by
# the quickshell test suite rather than left to drift.
accent_hex() {
    case "$1" in
    latte) printf '#8839ef' ;;
    frappe) printf '#ca9ee6' ;;
    macchiato) printf '#c6a0f6' ;;
    mocha) printf '#cba6f7' ;;
    *) printf '#c6a0f6' ;;
    esac
}

# --- commands ----------------------------------------------------------------

cmd_apply() {
    local palette baseline
    palette=$(resolve)
    baseline=$(baseline)
    # Keep the BASELINE in the store so the shell and the script never
    # disagree about what the desk shows with no lease held, even in auto
    # mode. A lease is never written here: a mode holds a palette the way it
    # holds a window, and when the mode ends the store still points at what
    # the sun (or the user) chose — a mode must not bury the baseline.
    put "$(jq -n --arg p "$baseline" '{palette: $p}')"

    apply_kitty "$palette"
    apply_gtk "$palette"
    apply_qt "$palette"
    apply_hyprland "$palette"
    apply_cursor "$palette"
    apply_btop "$palette"
    apply_zathura "$palette"
    apply_rofi "$palette"
    apply_wlogout "$palette"
    apply_zen "$palette"
    apply_obsidian "$palette"
    apply_linear "$palette"
    apply_wallpaper "$palette"

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

# Bind a wallpaper to a palette: `,theme.sh wallpaper <file> [palette]`.
cmd_wallpaper() {
    local file=${1-} palette=${2-}
    [ -n "$file" ] || die "wallpaper needs a file"
    [ -f "$file" ] || die "no such file: $file"
    [ -n "$palette" ] || palette=$(resolve)
    is_palette "$palette" || die "unknown palette '$palette'"
    put "$(jq -n --arg p "$palette" --arg f "$file" '{wallpapers: {($p): $f}}')"
    echo "wallpaper: $palette -> ${file##*/}"
    cmd_apply
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
    cmd_wallpaper "${1-}" "${2-}"
    ;;
get)
    resolve
    echo
    ;;
status) cmd_status ;;
-h | --help | help) sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//' ;;
*) die "unknown command '${1}' — try --help" ;;
esac
