#!/usr/bin/env bash
# Functional tests for ,theme.sh.
#
# The script's whole job is editing files that belong to a running desktop, so
# the tests give it a fake one: XDG_CONFIG_HOME and XDG_STATE_HOME point into a
# scratch tree seeded with the same file shapes the real config has.
#
# That is not enough on its own. gsettings writes over D-Bus to the dconf
# service, which uses ITS environment rather than the caller's, so a redirected
# XDG_CONFIG_HOME does not contain it — an early version of this file repainted
# the live desktop it was meant to be isolated from. hyprctl and pkill address
# the session by name and escape the same way.
#
# So THEME_GSETTINGS points at a recorder below. It stubs the one call that can
# escape, tells the script it is sandboxed so the signals and hyprctl pokes are
# held back, and gives the tests something to assert on that they could not
# check before.

set -euo pipefail

THEME=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/,theme.sh
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

# A scratch desktop: the files the script edits, with the shapes it expects.
setup() {
    ROOT=$(mktemp -d)
    export XDG_CONFIG_HOME="$ROOT/config" XDG_STATE_HOME="$ROOT/state" XDG_CACHE_HOME="$ROOT/cache"

    # The gsettings recorder. Appends its arguments and succeeds, so the script
    # takes the same path it would on a real desktop.
    GSETTINGS_LOG="$ROOT/gsettings.log"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$GSETTINGS_LOG" >"$ROOT/gsettings"
    chmod +x "$ROOT/gsettings"
    export THEME_GSETTINGS="$ROOT/gsettings"
    : >"$GSETTINGS_LOG"
    # The script keeps its store files in the shared quantum-store directory
    # under the redirected state home — the same layout the real desk has. The
    # live session exports QF_STORE at a higher level than the redirected
    # homes, so pin it into the scratch tree too; a script that prefers it
    # must not leak into the real desk's store.
    export QF_STORE="$XDG_STATE_HOME/quantum-store"
    mkdir -p "$XDG_CONFIG_HOME"/{kitty/themes,qt5ct/colors,qt6ct/colors,Kvantum} "$XDG_STATE_HOME/quantum-store"

    for flavour in latte frappe macchiato mocha; do
        touch "$XDG_CONFIG_HOME/kitty/themes/$flavour.conf"
        for v in qt5ct qt6ct; do
            touch "$XDG_CONFIG_HOME/$v/colors/catppuccin-$flavour-mauve.conf"
        done
        mkdir -p "$XDG_CONFIG_HOME/Kvantum/catppuccin-$flavour-mauve"
    done

    printf 'style=kvantum\ncolor_scheme_path=%s/qt6ct/colors/catppuccin-macchiato-mauve.conf\n' \
        "$XDG_CONFIG_HOME" >"$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
    printf 'style=kvantum\ncolor_scheme_path=%s/qt5ct/colors/catppuccin-macchiato-mauve.conf\n' \
        "$XDG_CONFIG_HOME" >"$XDG_CONFIG_HOME/qt5ct/qt5ct.conf"
    printf '[General]\ntheme=catppuccin-macchiato-mauve\n' >"$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig"

    STORE="$XDG_STATE_HOME/quantum-store/theme.json"
}

teardown() {
    unset THEME_GSETTINGS
    rm -rf "$ROOT"
}

gsettings_log() { cat "$GSETTINGS_LOG"; }

field() { jq -r ".$1" "$STORE"; }

echo "seeding an empty store"
setup
"$THEME" set mocha >/dev/null
check "palette written" "mocha" "$(field palette)"
check "an explicit set pins the mode" "manual" "$(field mode)"
check "get agrees" "mocha" "$("$THEME" get)"
check "kitty link repointed" "themes/mocha.conf" "$(readlink "$XDG_CONFIG_HOME/kitty/current-theme.conf")"
contains "qt6ct rewritten" "catppuccin-mocha-mauve.conf" "$(cat "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf")"
contains "qt5ct rewritten" "catppuccin-mocha-mauve.conf" "$(cat "$XDG_CONFIG_HOME/qt5ct/qt5ct.conf")"
contains "kvantum rewritten" "theme=catppuccin-mocha-mauve" "$(cat "$XDG_CONFIG_HOME/Kvantum/kvantum.kvconfig")"
contains "qt5ct style untouched" "style=kvantum" "$(cat "$XDG_CONFIG_HOME/qt5ct/qt5ct.conf")"
teardown

echo "GTK is told the theme and the light/dark scheme"
setup
"$THEME" set latte >/dev/null
contains "a light palette asks for the light theme" "gtk-theme catppuccin-latte-mauve-standard+default" "$(gsettings_log)"
contains "and for prefer-light" "color-scheme prefer-light" "$(gsettings_log)"
teardown

setup
"$THEME" set macchiato >/dev/null
contains "a dark palette asks for prefer-dark" "color-scheme prefer-dark" "$(gsettings_log)"
teardown

echo "GTK declaration files follow the palette too"
setup
# Seed the same shapes the theming role renders, pinned at the night palette.
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0" "$XDG_CONFIG_HOME/xsettingsd"
printf '[Settings]\ngtk-theme-name=catppuccin-macchiato-mauve-standard+default\ngtk-icon-theme-name=Papirus-Dark\ngtk-cursor-theme-name=catppuccin-macchiato-mauve-cursors\ngtk-application-prefer-dark-theme=1\n' >"$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
printf '[Settings]\ngtk-theme-name=catppuccin-macchiato-mauve-standard+default\n' >"$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
printf 'Net/ThemeName "catppuccin-macchiato-mauve-standard+default"\nNet/IconThemeName "Papirus-Dark"\n' >"$XDG_CONFIG_HOME/xsettingsd/xsettingsd.conf"

"$THEME" set latte >/dev/null
gtk3=$(cat "$XDG_CONFIG_HOME/gtk-3.0/settings.ini")
contains "a light apply rewrites the gtk3 theme name" "gtk-theme-name=catppuccin-latte-mauve-standard+default" "$gtk3"
contains "and its icon pack" "gtk-icon-theme-name=Papirus-Light" "$gtk3"
contains "and clears prefer-dark" "gtk-application-prefer-dark-theme=0" "$gtk3"
contains "a key the adapter does not own is left alone" "gtk-cursor-theme-name=catppuccin-macchiato-mauve-cursors" "$gtk3"
contains "gtk4 settings follow too" "gtk-theme-name=catppuccin-latte-mauve-standard+default" "$(cat "$XDG_CONFIG_HOME/gtk-4.0/settings.ini")"
xss=$(cat "$XDG_CONFIG_HOME/xsettingsd/xsettingsd.conf")
contains "xsettingsd announces the light theme to XWayland" 'Net/ThemeName "catppuccin-latte-mauve-standard+default"' "$xss"
contains "and the light icon pack" 'Net/IconThemeName "Papirus-Light"' "$xss"
teardown

echo "the nwg-look store stays in agreement so Apply cannot repaint the seed"
setup
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0"
printf '[Settings]\ngtk-application-prefer-dark-theme=1\n' >"$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
printf 'gtk-theme=catppuccin-macchiato-mauve-standard+default\nicon-theme=Papirus-Dark\ncolor-scheme=prefer-dark\n' >"$ROOT/nwg-store"
export THEME_NWG_GSETTINGS="$ROOT/nwg-store"
"$THEME" set latte >/dev/null
nwg=$(cat "$ROOT/nwg-store")
contains "nwg-look store follows the light scheme" "color-scheme=prefer-light" "$nwg"
contains "and the light theme name" "gtk-theme=catppuccin-latte-mauve-standard+default" "$nwg"
contains "and the light icon pack" "icon-theme=Papirus-Light" "$nwg"
unset THEME_NWG_GSETTINGS
teardown

setup
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0"
printf '[Settings]\ngtk-theme-name=catppuccin-latte-mauve-standard+default\ngtk-application-prefer-dark-theme=0\n' >"$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
"$THEME" set macchiato >/dev/null
contains "a dark apply re-raises prefer-dark" "gtk-application-prefer-dark-theme=1" "$(cat "$XDG_CONFIG_HOME/gtk-3.0/settings.ini")"
contains "and darkens the theme" "gtk-theme-name=catppuccin-macchiato-mauve-standard+default" "$(cat "$XDG_CONFIG_HOME/gtk-3.0/settings.ini")"
teardown

echo "gtkrc-2.0.mine follows when pointed at the scratch tree"
setup
MINE="$ROOT/mine"
printf 'gtk-theme-name="catppuccin-macchiato-mauve-standard+default"\ngtk-icon-theme-name="Papirus-Dark"\n' >"$MINE"
export THEME_GTKRC_MINE="$MINE"
"$THEME" set latte >/dev/null
contains "the .mine theme follows the palette" 'gtk-theme-name="catppuccin-latte-mauve-standard+default"' "$(cat "$MINE")"
contains "and its icons" 'gtk-icon-theme-name="Papirus-Light"' "$(cat "$MINE")"
unset THEME_GTKRC_MINE
teardown

echo "the home .mine is outside the sandbox and stays untouched"
setup
home_mine="$HOME/.gtkrc-2.0.mine"
before=$([ -f "$home_mine" ] && cat "$home_mine" || echo "<absent>")
"$THEME" set mocha >/dev/null
after=$([ -f "$home_mine" ] && cat "$home_mine" || echo "<absent>")
check "a sandboxed run leaves the home .mine alone" "$before" "$after"
teardown

echo "zen gets only the runtime accent, never the provisioned CSS"
setup
mkdir -p "$XDG_CONFIG_HOME/zen/shared"
cat >"$XDG_CONFIG_HOME/zen/shared/user.js" <<'EOF'
user_pref("zen.theme.accent-color", "#000000");
user_pref("layout.css.prefers-color-scheme.content-override", 1); // stale dark
user_pref("theme-better_find_bar-enable_custom_background", true);
EOF
"$THEME" set macchiato >/dev/null
ZS="$XDG_CONFIG_HOME/zen/shared"
contains "the accent follows the palette" 'zen.theme.accent-color", "#c6a0f6"' "$(cat "$ZS/user.js")"
contains "prefers-color-scheme stays on follow-system" 'prefers-color-scheme.content-override", 3' "$(cat "$ZS/user.js")"
contains "the palette file carries the accent" '#c6a0f6' "$(cat "$ZS/zen-palette.css")"
[ -f "$ZS/userChrome.css" ] && css_written=1 || css_written=0
check "the provisioned CSS is left alone" "0" "$css_written"
teardown

echo "wlogout follows the palette and drops the hardcoded dark background"
setup
mkdir -p "$XDG_CONFIG_HOME/wlogout/catppuccin/icons/wlogout/latte/text"
mkdir -p "$XDG_CONFIG_HOME/wlogout/catppuccin/icons/wlogout/latte/mauve"
touch "$XDG_CONFIG_HOME/wlogout/catppuccin/icons/wlogout/latte/text/lock.svg"
touch "$XDG_CONFIG_HOME/wlogout/catppuccin/icons/wlogout/latte/mauve/lock.svg"
# Seed a legacy CSS with the old dark scrim.
cat >"$XDG_CONFIG_HOME/wlogout/style.css" <<'EOF'
window { background-color: rgba(24, 25, 38, 0.55); }
button { background-color: #363a4f; }
#lock { background-image: url("/home/user/.config/wlogout/catppuccin/icons/wlogout/macchiato/text/lock.svg"); }
EOF
"$THEME" set latte >/dev/null
wls=$(cat "$XDG_CONFIG_HOME/wlogout/style.css")
contains "wlogout icon path follows the palette" "icons/wlogout/latte/" "$wls"
contains "wlogout background becomes transparent" "background-color: transparent;" "$wls"
contains "wlogout text colour follows the palette" "color: #cad3f5;" "$wls"
contains "wlogout button uses an alpha surface" "rgba(" "$wls"
# The old dark scrim must be gone.
if printf '%s' "$wls" | grep -q 'rgba(24, 25, 38, 0.55)'; then
    printf '  FAIL legacy dark scrim survived the apply\n'
    fail=$((fail + 1))
else
    printf '  ok   legacy dark scrim was replaced\n'
    pass=$((pass + 1))
fi
teardown

echo "nothing reaches the live session"
setup
"$THEME" set mocha >/dev/null
# The desk this runs on must be untouched: every write landed under $ROOT, and
# the session-wide pokes were held back.
check "gsettings was stubbed, not the real one" "$ROOT/gsettings" "$THEME_GSETTINGS"
contains "hyprland was skipped" "skipped (sandboxed)" "$("$THEME" apply)"
teardown

echo "auto mode resolves from day/night, not from palette"
setup
printf '{"mode":"auto","day":"latte","night":"mocha","palette":"frappe"}\n' >"$STORE"
resolved=$("$THEME" get)
case "$resolved" in
latte | mocha)
    printf '  ok   resolved to a day/night palette (%s)\n' "$resolved"
    pass=$((pass + 1))
    ;;
*)
    printf '  FAIL auto resolved to %s, expected latte or mocha\n' "$resolved"
    fail=$((fail + 1))
    ;;
esac
"$THEME" apply >/dev/null
check "apply records what it resolved" "$resolved" "$(field palette)"
check "apply leaves the mode alone" "auto" "$(field mode)"
teardown

echo "auto hands the choice back"
setup
"$THEME" set latte >/dev/null
check "pinned" "manual" "$(field mode)"
"$THEME" auto >/dev/null
check "handed back" "auto" "$(field mode)"
teardown

echo "toggle swaps day and night"
setup
printf '{"mode":"manual","day":"latte","night":"mocha","palette":"latte"}\n' >"$STORE"
"$THEME" toggle >/dev/null
check "latte toggles to night" "mocha" "$(field palette)"
"$THEME" toggle >/dev/null
check "and back to day" "latte" "$(field palette)"
teardown

echo "refusing what it cannot do"
setup
if "$THEME" set dracula >/dev/null 2>&1; then
    printf '  FAIL an unknown palette was accepted\n'
    fail=$((fail + 1))
else
    printf '  ok   an unknown palette is refused\n'
    pass=$((pass + 1))
fi
# A refused set must not create the store either: writing a file to record a
# rejection is how a typo ends up as persisted state.
if [ ! -e "$STORE" ]; then
    printf '  ok   a refused set leaves no store behind\n'
    pass=$((pass + 1))
else
    check "a refused set wrote no palette" "null" "$(jq -r '.palette // "null"' "$STORE")"
fi
if "$THEME" nonsense >/dev/null 2>&1; then
    printf '  FAIL an unknown command was accepted\n'
    fail=$((fail + 1))
else
    printf '  ok   an unknown command is refused\n'
    pass=$((pass + 1))
fi
teardown

echo "surviving a half-provisioned machine"
setup
rm -rf "$XDG_CONFIG_HOME/Kvantum" "$XDG_CONFIG_HOME/qt5ct"
if out=$("$THEME" set frappe 2>&1); then
    printf '  ok   a missing surface does not abort the rest\n'
    pass=$((pass + 1))
else
    printf '  FAIL aborted on a missing surface:\n%s\n' "$out"
    fail=$((fail + 1))
fi
check "the surfaces that exist still changed" "frappe" "$(field palette)"
contains "qt6ct still rewritten" "catppuccin-frappe-mauve.conf" "$(cat "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf")"
teardown

echo "wallpaper cache: rendered once, kept on an unchanged source"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
# A stub magick, so the test asserts on caching behaviour rather than on real
# image output: it just needs to run once per distinct input to prove whether
# the script asked it to.
MAGICK_LOG="$ROOT/magick.log"
cat >"$ROOT/magick" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MAGICK_LOG"
touch "\${@: -1}"
STUB
chmod +x "$ROOT/magick"
export THEME_MAGICK="$ROOT/magick"
printf 'source-v1' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"

"$THEME" set mocha >/dev/null
cached="$XDG_CACHE_HOME/wallpapers/mocha/mocha.png"
check "a cached render was produced" "1" "$([ -f "$cached" ] && echo 1 || echo 0)"
check "magick ran once" "1" "$(wc -l <"$MAGICK_LOG" | tr -d ' ')"

"$THEME" apply >/dev/null
check "an unchanged source is not re-rendered" "1" "$(wc -l <"$MAGICK_LOG" | tr -d ' ')"

touch -d '+1 hour' "$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"
"$THEME" apply >/dev/null
check "a changed source mtime re-renders" "2" "$(wc -l <"$MAGICK_LOG" | tr -d ' ')"
unset THEME_MAGICK
teardown

echo "wallpaper cache: the store's blur dial drives the magick flags"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
MAGICK_LOG="$ROOT/magick.log"
cat >"$ROOT/magick" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MAGICK_LOG"
touch "\${@: -1}"
STUB
chmod +x "$ROOT/magick"
export THEME_MAGICK="$ROOT/magick"
printf 'dial' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"

printf '{"palette":"mocha","mode":"manual","wallpaper_blur":24}\n' >"$STORE"
"$THEME" apply >/dev/null
contains "a custom sigma reaches magick" "-blur 0x18" "$(cat "$MAGICK_LOG")"

# A dial change must re-render even though neither the source nor the role
# moved — it is part of the cache stamp, not a cosmetic label.
: >"$MAGICK_LOG"
printf '{"palette":"mocha","mode":"manual","wallpaper_blur":18}\n' >"$STORE"
"$THEME" apply >/dev/null
contains "the default sigma 18 is the historic 0x12" "-blur 0x12" "$(cat "$MAGICK_LOG")"

: >"$MAGICK_LOG"
printf '{"palette":"mocha","mode":"manual","wallpaper_blur":0}\n' >"$STORE"
"$THEME" apply >/dev/null
check "blur 0 skips the -blur flag" "0" "$(grep -c -- '-blur' "$MAGICK_LOG" || true)"
check "blur 0 still renders through magick" "1" "$(wc -l <"$MAGICK_LOG" | tr -d ' ')"
unset THEME_MAGICK
teardown

echo "wallpaper cache: missing ImageMagick degrades to the original"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'source' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"
export THEME_MAGICK="$ROOT/no-such-magick-binary"
"$THEME" set mocha >/dev/null
check "no cache directory was created" "0" "$([ -d "$XDG_CACHE_HOME/wallpapers" ] && echo 1 || echo 0)"
unset THEME_MAGICK
teardown

if command -v magick >/dev/null 2>&1; then
    echo "wallpaper cache: a real render lands under XDG_CACHE_HOME, tinted per palette"
    setup
    mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
    magick -size 8x8 xc:'#336699' "$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"
    "$THEME" set mocha >/dev/null
    check "rendered under the scratch cache, not the real one" "1" \
        "$([ -f "$XDG_CACHE_HOME/wallpapers/mocha/mocha.png" ] && echo 1 || echo 0)"
    teardown
fi

# A recorder standing in for both awww binaries, the same trick THEME_GSETTINGS
# uses on gsettings. Pointing AWWW/AWWW_DAEMON at it is what tells
# apply_wallpaper this run may call through — a bare sandboxed run, with
# neither variable set, still gets held back (checked below).
awww_stub() {
    AWWW_LOG="$ROOT/awww.log"
    : >"$AWWW_LOG"
    cat >"$ROOT/awww" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWWW_LOG"
[ "$1" = "query" ] && exit 1 # daemon reports dead, every time — exercises the start path
exit 0
STUB
    chmod +x "$ROOT/awww"
    cat >"$ROOT/awww-daemon" <<'STUB'
#!/usr/bin/env bash
printf 'daemon started\n' >>"$AWWW_LOG"
STUB
    chmod +x "$ROOT/awww-daemon"
    export THEME_AWWW="$ROOT/awww" THEME_AWWW_DAEMON="$ROOT/awww-daemon" AWWW_LOG
}

echo "wallpaper resolution: a palette binding beats the single fallback"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary" # image processing is not the point here
awww_stub
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'single' >"$ROOT/single.png"
printf 'palette-bound' >"$ROOT/palette.png"

# Nothing bound yet: falls all the way through to the bare `wallpaper` field.
printf '{"palette":"mocha","mode":"manual","wallpaper":"%s"}\n' "$ROOT/single.png" >"$STORE"
"$THEME" apply >/dev/null
contains "no binding falls back to the single wallpaper" "single.png" "$(cat "$AWWW_LOG")"

# A palette binding outranks the bare fallback.
"$THEME" wallpaper "$ROOT/palette.png" mocha >/dev/null
: >"$AWWW_LOG"
"$THEME" apply >/dev/null
contains "a palette binding outranks the bare fallback" "palette.png" "$(cat "$AWWW_LOG")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

echo "wallpaper resolution: an unbound palette fails open to a random pick"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'fallback' >"$XDG_CONFIG_HOME/hypr/wallpapers/rain.png"
# frappe has no binding, no bare fallback, no frappe.jpg — the pick answers.
printf '{"palette":"frappe"}\n' >"$STORE"
"$THEME" apply >/dev/null
contains "an unbound palette falls open to the wallpapers directory" "rain.png" "$(cat "$AWWW_LOG")"
check "the random pick is not persisted as a binding" "0" \
    "$(jq -r '.wallpapers // {} | length' "$STORE")"
: >"$AWWW_LOG"
"$THEME" apply >/dev/null
contains "a second unbound apply still answers" "rain.png" "$(cat "$AWWW_LOG")"

rm -f "$XDG_CONFIG_HOME/hypr/wallpapers"/*
"$THEME" apply >"$ROOT/out" 2>&1
contains "an empty wallpaper directory still reports unchanged" "wallpaper: unchanged" "$(cat "$ROOT/out")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

echo "wallpaper resolution: a bare bound name resolves against the wallpapers dir (LEO-372)"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'bare' >"$XDG_CONFIG_HOME/hypr/wallpapers/Clearnight.jpg"
printf '{"palette":"mocha","mode":"manual","wallpapers":{"mocha":"Clearnight.jpg"}}\n' >"$STORE"
"$THEME" apply >/dev/null
contains "a bare name resolves against \$CONFIG/hypr/wallpapers" "Clearnight.jpg" "$(cat "$AWWW_LOG")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

echo "wallpaper resolution: a missing bound file falls through to a random pick"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'fallback' >"$XDG_CONFIG_HOME/hypr/wallpapers/rain.png"
printf '{"palette":"mocha","mode":"manual","wallpapers":{"mocha":"does-not-exist.jpg"}}\n' >"$STORE"
"$THEME" apply >/dev/null
contains "a nonexistent bound file falls through to the random pick, not a failure" "rain.png" "$(cat "$AWWW_LOG")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

echo "wallpaper resolution: an unknown palette is refused"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'x' >"$ROOT/x.png"
if "$THEME" wallpaper "$ROOT/x.png" nightmare >/dev/null 2>&1; then
    printf '  FAIL an unknown palette was accepted\n'
    fail=$((fail + 1))
else
    printf '  ok   an unknown palette is refused\n'
    pass=$((pass + 1))
fi
teardown

echo "obsidian/linear: recorded as the tiered surfaces they are"
setup
mkdir -p "$ROOT/vault/.obsidian"
printf '{"cssTheme":"Catppuccin","accentColor":"","theme":"obsidian"}\n' >"$ROOT/vault/.obsidian/appearance.json"
export OBSIDIAN_VAULT="$ROOT/vault"
"$THEME" set mocha >"$ROOT/out" 2>&1
check "obsidian stays on adapt-to-system" "system" "$(jq -r '.theme' "$ROOT/vault/.obsidian/appearance.json")"
check "obsidian got the palette accent" "#cba6f7" "$(jq -r '.accentColor' "$ROOT/vault/.obsidian/appearance.json")"
contains "obsidian is reported as next-launch, not immediate" "applies on next launch" "$(cat "$ROOT/out")"
contains "linear is reported as scheme-following" "linear: follows the system colour scheme (dark)" "$(cat "$ROOT/out")"
"$THEME" set latte >"$ROOT/out" 2>&1
check "latte does not pin a fixed base either" "system" "$(jq -r '.theme' "$ROOT/vault/.obsidian/appearance.json")"
contains "linear follows a light scheme too" "linear: follows the system colour scheme (light)" "$(cat "$ROOT/out")"

echo "obsidian: a user's own dark/light pick is corrected back to adapt-to-system"
printf '{"cssTheme":"Catppuccin","accentColor":"","theme":"dark"}\n' >"$ROOT/vault/.obsidian/appearance.json"
"$THEME" set mocha >/dev/null 2>&1
check "an external theme write is overridden back to system" "system" "$(jq -r '.theme' "$ROOT/vault/.obsidian/appearance.json")"
rm -rf "$ROOT/vault"
"$THEME" set mocha >"$ROOT/out" 2>&1
contains "a missing vault is failed, not silent" "obsidian:" "$(cat "$ROOT/out")"
unset OBSIDIAN_VAULT
teardown

echo "accent: a mode's declared role resolves to its own hex per palette"
setup
mkdir -p "$ROOT/vault/.obsidian"
printf '{"cssTheme":"Catppuccin","accentColor":"","theme":"obsidian"}\n' >"$ROOT/vault/.obsidian/appearance.json"
export OBSIDIAN_VAULT="$ROOT/vault"

printf '{"modes":{"study":{"name":"study","presentation":{"accent_role":"red"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"study","until":null}\n' >"$XDG_STATE_HOME/quantum-store/focus.json"
"$THEME" set macchiato >/dev/null
check "study's red role on macchiato is the catppuccin red hex" "#ed8796" \
    "$(jq -r '.accentColor' "$ROOT/vault/.obsidian/appearance.json")"

printf '{"modes":{"gaming":{"name":"gaming","presentation":{"accent_role":"lavender"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"gaming","until":null}\n' >"$XDG_STATE_HOME/quantum-store/focus.json"
"$THEME" set latte >/dev/null
check "gaming's lavender role on latte falls back to mauve (contrast guard)" "#8839ef" \
    "$(jq -r '.accentColor' "$ROOT/vault/.obsidian/appearance.json")"

printf '{"modes":{"gaming":{"name":"gaming","presentation":{"accent_role":"blue"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
"$THEME" set latte >/dev/null
check "latte keeps the blue role (it clears contrast)" "#1e66f5" \
    "$(jq -r '.accentColor' "$ROOT/vault/.obsidian/appearance.json")"

rm -f "$XDG_STATE_HOME/quantum-store/hyprfocus.json" "$XDG_STATE_HOME/quantum-store/focus.json"
unset OBSIDIAN_VAULT
teardown

# The cursor outline is painted in its own flavour's base colour, so a
# flavour-matched cursor is invisible on that flavour's own background
# (latte's near-white outline on the latte desk). The cursor is resolved for
# CONTRAST: a light desk carries the night flavour's cursor, a dark desk its
# own. The applier names the resolved theme even when sandboxed, so the
# resolution is assertable without a compositor.
echo "cursor: a light desk carries the night flavour's (dark-outlined) cursor"
setup
printf '{"mode":"manual","palette":"latte","day":"latte","night":"macchiato"}\n' >"$STORE"
contains "latte resolves the dark cursor" "cursor: catppuccin-macchiato-mauve-cursors" "$("$THEME" apply)"
teardown

echo "cursor: a dark desk keeps its own flavour"
setup
printf '{"mode":"manual","palette":"mocha","day":"latte","night":"macchiato"}\n' >"$STORE"
contains "mocha keeps its own cursor" "cursor: catppuccin-mocha-mauve-cursors" "$("$THEME" apply)"
teardown

echo "cursor: a degenerate light-night config still resolves a dark cursor"
setup
printf '{"mode":"manual","palette":"latte","day":"latte","night":"latte"}\n' >"$STORE"
contains "latte with a light night falls back to a dark flavour" "cursor: catppuccin-mocha-mauve-cursors" "$("$THEME" apply)"
teardown

echo "nvim: a live control socket is poked and reported as switched"
setup
# The recorder stands in for nvim: it answers the --remote-expr by printing
# nothing, exactly what execute('colorscheme …') returns on a real switch.
NVIM_LOG="$ROOT/nvim.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$NVIM_LOG" >"$ROOT/nvim"
chmod +x "$ROOT/nvim"
export THEME_NVIM="$ROOT/nvim"
# A real unix socket, so the [ -S ] guard passes: python holds it open for the
# length of the apply, then the test tears it down.
mkdir -p "$ROOT/runtime/proj-nvim"
python3 - "$ROOT/runtime/proj-nvim/spike.sock" <<'PY' &
import socket
import sys
import time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
time.sleep(30)
PY
NVIM_PID=$!
sleep 0.3
export XDG_RUNTIME_DIR="$ROOT/runtime"

"$THEME" set mocha >"$ROOT/out" 2>&1
contains "the poke addressed the live socket" "--server $ROOT/runtime/proj-nvim/spike.sock" "$(cat "$NVIM_LOG")"
contains "the poke requested the catppuccin colourscheme" "catppuccin-mocha" "$(cat "$NVIM_LOG")"
contains "a switched editor is reported immediate" "nvim: catppuccin-mocha (1 live)" "$(cat "$ROOT/out")"
check "the store records the resolved palette" "mocha" "$(field resolved)"
kill "$NVIM_PID" 2>/dev/null || true
wait "$NVIM_PID" 2>/dev/null || true
unset THEME_NVIM XDG_RUNTIME_DIR
teardown

echo "nvim: an editor that answers with an E185 error is a miss, not a switch"
setup
printf '#!/usr/bin/env bash\nprintf "E185: Cannot find color scheme %%s\\n" "${@: -1}"\n' >"$ROOT/nvim-e185"
chmod +x "$ROOT/nvim-e185"
export THEME_NVIM="$ROOT/nvim-e185"
mkdir -p "$ROOT/runtime"
python3 - "$ROOT/runtime/nvim.9999.0" <<'PY' &
import socket
import sys
import time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
time.sleep(30)
PY
NVIM_PID=$!
sleep 0.3
export XDG_RUNTIME_DIR="$ROOT/runtime"

"$THEME" set mocha >"$ROOT/out" 2>&1
contains "an E185 answer is surfaced, not swallowed" "E185" "$(cat "$ROOT/out")"
contains "a missed editor is not reported immediate" "no socket switched" "$(cat "$ROOT/out")"
kill "$NVIM_PID" 2>/dev/null || true
wait "$NVIM_PID" 2>/dev/null || true
unset THEME_NVIM XDG_RUNTIME_DIR
teardown

echo "nvim: a dead socket (E247 with exit 2) is a miss, never a fatal"
setup
# The live failure shape: a stale socket file left by an exited editor makes
# nvim exit 2 with the E247 connect-refused text. That exit status used to
# ride the `answer=$(...)` assignment, and set -e turned it into an abort of
# the whole apply mid-flight — kitty printed, then gtk/zen/obsidian/linear/
# shell/wallpaper never ran, which is the desk's "apps didn't follow the
# theme" regression. The stub replicates the shape exactly: the same stderr
# text AND a nonzero exit. The run must surface the miss and keep going.
printf '#!/usr/bin/env bash\nprintf "E247: Failed to connect to %%s: connection refused. Send expression failed.\\n" "${@: -1}" >&2\nexit 2\n' >"$ROOT/nvim-e247"
chmod +x "$ROOT/nvim-e247"
export THEME_NVIM="$ROOT/nvim-e247"
mkdir -p "$ROOT/runtime"
python3 - "$ROOT/runtime/nvim.9999.0" <<'PY' &
import socket
import sys
import time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
time.sleep(30)
PY
NVIM_PID=$!
sleep 0.3
export XDG_RUNTIME_DIR="$ROOT/runtime"

"$THEME" set mocha >"$ROOT/out" 2>&1
contains "a dead socket is surfaced, not fatal" "no socket switched: E247" "$(cat "$ROOT/out")"
contains "the apply survives the dead socket and runs the later surfaces" "shell: Mocha" "$(cat "$ROOT/out")"
kill "$NVIM_PID" 2>/dev/null || true
wait "$NVIM_PID" 2>/dev/null || true
unset THEME_NVIM XDG_RUNTIME_DIR
teardown

echo "nvim: a hung socket is timed out, surfaced, never stalls the apply"
setup
# Third failure shape, live: a socket whose editor is still alive but wedged
# accepts the connect and never answers, so --remote-expr blocks forever and
# the fan-out stalls right after kitty. The poke is capped by `timeout`; the
# editor's own deadly-signal text (what nvim prints on SIGTERM) becomes the
# miss. THEME_NVIM_TIMEOUT keeps the test fast.
cat >"$ROOT/nvim-hang" <<'STUB'
#!/usr/bin/env bash
printf "Nvim: Caught deadly signal 'SIGTERM'\nNvim: Finished.\n" >&2
sleep 30
STUB
chmod +x "$ROOT/nvim-hang"
export THEME_NVIM="$ROOT/nvim-hang" THEME_NVIM_TIMEOUT=1
mkdir -p "$ROOT/runtime"
python3 - "$ROOT/runtime/nvim.8888.0" <<'PY' &
import socket
import sys
import time
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
time.sleep(30)
PY
NVIM_PID=$!
sleep 0.3
export XDG_RUNTIME_DIR="$ROOT/runtime"

"$THEME" set mocha >"$ROOT/out" 2>&1
contains "a timed-out socket is a miss, not a switch" "no socket switched" "$(cat "$ROOT/out")"
contains "the apply survives the hang and runs the later surfaces" "shell: Mocha" "$(cat "$ROOT/out")"
kill "$NVIM_PID" 2>/dev/null || true
wait "$NVIM_PID" 2>/dev/null || true
unset THEME_NVIM THEME_NVIM_TIMEOUT XDG_RUNTIME_DIR
teardown

echo "nvim: no sockets at all is pending, not immediate"
setup
printf '#!/usr/bin/env bash\nexit 0\n' >"$ROOT/nvim"
chmod +x "$ROOT/nvim"
export THEME_NVIM="$ROOT/nvim"
export XDG_RUNTIME_DIR="$ROOT/empty-runtime"
mkdir -p "$XDG_RUNTIME_DIR"

"$THEME" set mocha >"$ROOT/out" 2>&1
contains "a socketless desk reports pending, not immediate" "no sockets; the editor follows the store itself" "$(cat "$ROOT/out")"
unset THEME_NVIM XDG_RUNTIME_DIR
teardown

echo "crossfade: awww is asked for a transition, not a hard cut"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'source' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"

"$THEME" set mocha >/dev/null
contains "the daemon was started, since query reported it dead" "daemon started" "$(cat "$AWWW_LOG")"
contains "img was called with a transition, not a bare path" "--transition-type" "$(cat "$AWWW_LOG")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

echo "a sandboxed run never reaches the real awww without an explicit override"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
export THEME_MAGICK="$ROOT/no-such-magick-binary"
printf 'source' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"
contains "wallpaper apply reports skipped, not attempted" "skipped (sandboxed)" "$("$THEME" set mocha 2>&1)"
unset THEME_MAGICK
teardown

echo "a pack-names a variant the appliers do not (LEO-210's harder half)"
setup
# The scratch pack dir: a gruvbox pack shipping partial coverage — the kitty
# surface named, the others not.
PACKS="$XDG_STATE_HOME/packs"
export THEME_PACKS_DIR="$PACKS"
mkdir -p "$PACKS"
cat >"$PACKS/gruvbox.json" <<'PACK'
{
  "pack": "gruvbox",
  "accents": {
    "lavender": "base16", "blue": "base0d", "peach": "base09",
    "mauve": "base0e", "green": "base0b", "pink": "base17", "teal": "base0c"
  },
  "names": { "base": "base00" },
  "surfaces": { "kitty": "gruvbox-material-{variant}" },
  "variants": {
    "gruvbox-material": {
      "kind": "dark",
      "slots": {
        "base00": "#282828", "base01": "#3c3836", "base02": "#504945",
        "base03": "#665c54", "base04": "#928374", "base05": "#ebdbb2",
        "base06": "#fbf1c7", "base07": "#f9f5d7", "base08": "#cc241d",
        "base09": "#d65d0e", "base0a": "#d79921", "base0b": "#98971a",
        "base0c": "#689d6a", "base0d": "#458588", "base0e": "#b16286",
        "base0f": "#9d0006", "base10": "#2a2520", "base11": "#1d1d1d",
        "base12": "#fb4934", "base13": "#fabd2f", "base14": "#b8bb26",
        "base15": "#8ec07c", "base16": "#83a598", "base17": "#d3869b"
      }
    }
  }
}
PACK
# The surface assets carry what the pack names: kitty has the theme under the
# registry's own name shape.
mkdir -p "$XDG_CONFIG_HOME/kitty/themes"
touch "$XDG_CONFIG_HOME/kitty/themes/gruvbox-material-gruvbox-material.conf"

# The shell's theme.json + mode pointer lease it through the whole desk.
STORE="$XDG_STATE_HOME/quantum-store/theme.json"
printf '{"palette":"mocha","mode":"manual"}\n' >"$STORE"
printf '{"modes":{"gaming":{"name":"gaming","presentation":{"palette":"gruvbox-material"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"gaming","until":null}' >"$XDG_STATE_HOME/quantum-store/focus.json"

get=$("$THEME" get)
check "the lease resolves through the pack" "gruvbox-material" "$get"
"$THEME" apply >/dev/null
check "the kitty surface reads the pack's own name" "themes/gruvbox-material-gruvbox-material.conf" \
    "$(readlink "$XDG_CONFIG_HOME/kitty/current-theme.conf")"

# Partial coverage is normal, not a failure of the apply: a surface the pack
# does not name keeps its own shape and records the gap.
out=$("$THEME" apply 2>&1)
contains "the unnamed surface records a named failure, not a crash" \
    "gtk: catppuccin-gruvbox-material-mauve-standard+default not installed" "$out"
teardown

echo "a mode's wallpaper is the leased palette's own binding"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers" "$XDG_STATE_HOME/quantum-store"
touch "$XDG_CONFIG_HOME/hypr/wallpapers/mocha.jpg" "$XDG_CONFIG_HOME/hypr/wallpapers/latte.jpg"
STORE="$XDG_STATE_HOME/quantum-store/theme.json"
printf '{"mode":"manual","palette":"mocha","day":"latte","night":"mocha"}\n' >"$STORE"
printf '{"modes":{"work":{"name":"work","presentation":{"palette":"latte"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"

# Wallpapers belong to palettes, not modes: a mode changes the wallpaper only
# by leasing a palette, so binding latte's own wallpaper is what a leasing
# mode picks up.
"$THEME" wallpaper "$XDG_CONFIG_HOME/hypr/wallpapers/mocha.jpg" mocha >/dev/null
"$THEME" wallpaper "$XDG_CONFIG_HOME/hypr/wallpapers/latte.jpg" latte >/dev/null

# No pointer file at all reads as `work`, the boot/resting mode — its own
# lease applies from the very first read, not the baseline.
contains "at rest (no pointer) the boot mode's own lease answers" \
    "wallpaper $XDG_CONFIG_HOME/hypr/wallpapers/latte.jpg" "$("$THEME" status)"

# `neutral` is the hidden recovery mode: reachable deliberately, never a
# fallback, and (having no presentation here) holds no lease of its own.
printf '{"mode":"neutral","until":null}' >"$XDG_STATE_HOME/quantum-store/focus.json"
contains "a deliberate neutral entry falls through to the baseline palette" \
    "wallpaper $XDG_CONFIG_HOME/hypr/wallpapers/mocha.jpg" "$("$THEME" status)"

printf '{"mode":"work","until":null}' >"$XDG_STATE_HOME/quantum-store/focus.json"
contains "a held lease shows the leased palette's own binding" \
    "wallpaper $XDG_CONFIG_HOME/hypr/wallpapers/latte.jpg" "$("$THEME" status)"
teardown

echo "wallpaper sets: list, per-monitor picks, shuffled cycling (LEO-366)"
setup
export THEME_OUTPUTS="DP-1 eDP-1"
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/a.jpg"
printf 'b' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/b.jpg"
printf 'c' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/c.jpg"

list=$("$THEME" wallpaper list mocha)
check "list: three items" "3" "$(printf '%s' "$list" | jq '.count')"
check "list: both monitors present" "2" "$(printf '%s' "$list" | jq '.monitors | length')"

# Cycle a fresh output through the whole set (3 files) via `next` before
# anything else touches it: the shuffled order is a permutation of the set,
# so exactly `count` steps from a cold start show every distinct file once
# before the order is exhausted and reshuffled.
seen=""
for _ in 1 2 3; do
    "$THEME" wallpaper next mocha --output DP-1 >/dev/null
    f=$(jq -r '.wallpapers.mocha["DP-1"]' "$STORE")
    seen="$seen $f"
done
uniq_count=$(printf '%s\n' $seen | sort -u | wc -l | tr -d ' ')
check "three next steps from a cold start show three distinct files" "3" "$uniq_count"

before=$(jq -r '.wallpaper_shuffle.mocha.orders["DP-1"]' "$STORE")
"$THEME" wallpaper prev mocha --output DP-1 >/dev/null
after=$(jq -r '.wallpaper_shuffle.mocha.orders["DP-1"]' "$STORE")
check "the shuffled order persists across calls (deterministic per session)" "$before" "$after"

# A second, still-untouched output cycles independently of the first.
out=$("$THEME" wallpaper next mocha --output eDP-1)
contains "the other monitor reports its own name" "eDP-1" "$out"
edp1_first=$(jq -r '.wallpapers.mocha["eDP-1"]' "$STORE")
contains "eDP-1 got one of mocha's own files" "mocha/" "$edp1_first"
unset THEME_OUTPUTS
teardown

echo "wallpaper sets: an out-of-set file is refused once the palette has a set folder"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/a.jpg"
printf 'x' >"$ROOT/outside.jpg"
if "$THEME" wallpaper "$ROOT/outside.jpg" mocha >/dev/null 2>&1; then
    printf '  FAIL a file outside the palette set was accepted\n'
    fail=$((fail + 1))
else
    printf '  ok   a file outside the palette set is refused\n'
    pass=$((pass + 1))
fi
"$THEME" wallpaper "$XDG_CONFIG_HOME/hypr/wallpapers/mocha/a.jpg" mocha >/dev/null
check "a file inside the palette set is accepted" "mocha/a.jpg" "$(jq -r '.wallpapers.mocha["*"]' "$STORE")"
teardown

echo "wallpaper sets: an empty set fails open, honestly"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
if out=$("$THEME" wallpaper next mocha 2>&1); then
    contains "an empty set is reported, not silently skipped" "nothing in mocha's set fits" "$out"
else
    printf '  FAIL cycling an empty set aborted instead of reporting\n'
    fail=$((fail + 1))
fi
teardown

echo "wallpaper sets: the legacy flat-name binding still resolves (migration path)"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'legacy' >"$XDG_CONFIG_HOME/hypr/wallpapers/Clearnight.jpg"
printf '{"palette":"mocha","mode":"manual","wallpapers":{"mocha":"Clearnight.jpg"}}\n' >"$STORE"
list=$("$THEME" wallpaper list mocha)
check "the flat bare-name binding is still the resolved current pick" "Clearnight.jpg" \
    "$(printf '%s' "$list" | jq -r '.monitors["*"].current')"
teardown

echo "wallpaper fit: an ultrawide-only pool has nothing for a 16:9 output"
setup
export THEME_OUTPUTS="DP-1"
export THEME_OUTPUT_SIZES="DP-1:2560x1440"
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/ultrawide.jpg"
export THEME_IMAGE_SIZES="ultrawide.jpg:5120x1440"
out=$("$THEME" wallpaper next mocha --output DP-1 2>&1 || true)
contains "nothing fits: reported honestly" "nothing in mocha's set fits DP-1" "$out"
check "no binding was written for the output" "null" "$(jq -r '.wallpapers.mocha["DP-1"] // "null"' "$STORE" 2>/dev/null || echo null)"
unset THEME_OUTPUTS THEME_OUTPUT_SIZES THEME_IMAGE_SIZES
teardown

echo "wallpaper fit: a mixed pool only draws the fitting subset per output"
setup
export THEME_OUTPUTS="DP-1 DP-2"
export THEME_OUTPUT_SIZES="DP-1:5120x1440 DP-2:2560x1440"
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/ultrawide.jpg"
printf 'b' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/sixteennine.jpg"
export THEME_IMAGE_SIZES="ultrawide.jpg:5120x1440 sixteennine.jpg:2560x1440"

list=$("$THEME" wallpaper list mocha)
check "DP-1 (ultrawide) sees only the ultrawide image" "ultrawide.jpg" \
    "$(printf '%s' "$list" | jq -r '.monitors["DP-1"].fits[0]')"
check "DP-1 sees exactly one fitting image" "1" "$(printf '%s' "$list" | jq '.monitors["DP-1"].fits | length')"
check "DP-2 (16:9) sees only the 16:9 image" "sixteennine.jpg" \
    "$(printf '%s' "$list" | jq -r '.monitors["DP-2"].fits[0]')"

"$THEME" wallpaper next mocha --output DP-1 >/dev/null
"$THEME" wallpaper next mocha --output DP-2 >/dev/null
check "DP-1 (ultrawide) was bound the ultrawide image" "mocha/ultrawide.jpg" \
    "$(jq -r '.wallpapers.mocha["DP-1"]' "$STORE")"
check "DP-2 (16:9) was bound the 16:9 image" "mocha/sixteennine.jpg" \
    "$(jq -r '.wallpapers.mocha["DP-2"]' "$STORE")"

# Each output's own fitting subset (one image apiece) exhausts and reshuffles
# independently: a second `next` on either output still returns its one image.
"$THEME" wallpaper next mocha --output DP-1 >/dev/null
check "DP-1's single-image pool reshuffles onto the same image, not the other output's" \
    "mocha/ultrawide.jpg" "$(jq -r '.wallpapers.mocha["DP-1"]' "$STORE")"
unset THEME_OUTPUTS THEME_OUTPUT_SIZES THEME_IMAGE_SIZES
teardown

echo "wallpaper fit: binding a file rejects one that does not fit the named output"
setup
export THEME_OUTPUTS="DP-2"
export THEME_OUTPUT_SIZES="DP-2:2560x1440"
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/ultrawide.jpg"
export THEME_IMAGE_SIZES="ultrawide.jpg:5120x1440"
if "$THEME" wallpaper "$XDG_CONFIG_HOME/hypr/wallpapers/mocha/ultrawide.jpg" mocha >/dev/null 2>&1; then
    printf '  FAIL a file that does not fit the named output was accepted\n'
    fail=$((fail + 1))
else
    printf '  ok   a file that does not fit the named output is refused\n'
    pass=$((pass + 1))
fi
unset THEME_OUTPUTS THEME_OUTPUT_SIZES THEME_IMAGE_SIZES
teardown

echo "wallpaper apply: an unbound monitor does not inherit another monitor's specific pick (LEO-365)"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary" # image processing is not the point here
awww_stub
export THEME_OUTPUTS="DP-1 DP-2 HDMI-A-1"
export THEME_OUTPUT_SIZES="DP-1:5120x1440 DP-2:1920x1080 HDMI-A-1:1920x1080"
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/a.jpg"
printf 'b' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/b.jpg"
export THEME_IMAGE_SIZES="a.jpg:5120x1440 b.jpg:1920x1080"

# Only DP-1 (ultrawide, fits a.jpg only) has ever been cycled; DP-2 and
# HDMI-A-1 (both 16:9, fit b.jpg only) are still unbound — the exact shape
# that used to make resolve_wallpaper's "any value in the map" fallback hand
# DP-1's own pick to every monitor with no binding of its own.
"$THEME" wallpaper next mocha --output DP-1 >/dev/null
"$THEME" set mocha >/dev/null
dp1=$(sed -n 's/^\(.*\) --outputs DP-1 .*$/\1/p' "$AWWW_LOG")
dp2=$(sed -n 's/^\(.*\) --outputs DP-2 .*$/\1/p' "$AWWW_LOG")
hdmi=$(sed -n 's/^\(.*\) --outputs HDMI-A-1 .*$/\1/p' "$AWWW_LOG")
check "the recorder saw three separate --outputs img calls" "3" \
    "$(grep -c -- '--outputs' "$AWWW_LOG")"
contains "DP-1 (ultrawide) got its own bound pick" "a.jpg" "$dp1"
contains "DP-2 (16:9, unbound) got its own fitting pick, not DP-1's" "b.jpg" "$dp2"
contains "HDMI-A-1 (16:9, unbound) got its own fitting pick, not DP-1's" "b.jpg" "$hdmi"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG THEME_OUTPUTS THEME_OUTPUT_SIZES THEME_IMAGE_SIZES
teardown

echo "wallpaper blur: per-monitor blur subcommand and query"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers/mocha"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha/a.jpg"
export THEME_OUTPUTS="DP-1 DP-2"
export THEME_OUTPUT_SIZES="DP-1:5120x1440 DP-2:1920x1080"
export THEME_IMAGE_SIZES="a.jpg:5120x1440"
awww_stub
printf '{"palette":"mocha","mode":"manual","wallpapers":{"mocha":{"DP-1":"mocha/a.jpg","DP-2":"mocha/a.jpg"}}}\n' >"$STORE"
"$THEME" wallpaper blur 25 mocha --output DP-1 >/dev/null
check "per-monitor blur written to store" "25" "$(jq -r '.wallpaper_blurs["DP-1"] // -1' "$STORE")"
check "unmentioned monitor falls back to default 18" "18" "$(jq -r '.wallpaper_blurs["DP-2"] // 18' "$STORE")"
list=$("$THEME" wallpaper list mocha)
check "wallpaper list reports per-monitor blur for DP-1" "25" "$(printf '%s' "$list" | jq -r '.monitors["DP-1"].blur // -1')"
check "wallpaper list reports default blur for DP-2" "18" "$(printf '%s' "$list" | jq -r '.monitors["DP-2"].blur // -1')"
unset THEME_OUTPUTS THEME_OUTPUT_SIZES THEME_IMAGE_SIZES THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

echo "a mode leases a palette while it runs"
setup
printf '{"mode":"manual","palette":"mocha","day":"latte","night":"macchiato"}\n' >"$STORE"
# The pointer is one store the script never writes: a live mode (no `until`)
# whose declaration names a palette in its presentation.
printf '{"modes":{"gaming":{"name":"Gaming","presentation":{"palette":"latte"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"gaming","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"

# The lease is in effect: the manual pick (mocha) must not win while the mode
# holds, whatever the store's pointer says.
check "a held lease is found" "latte" "$("$THEME" get)"
"$THEME" apply >/dev/null
check "kitty points at the leased palette" "themes/latte.conf" \
    "$(readlink "$XDG_CONFIG_HOME/kitty/current-theme.conf")"

# The lease replaces the pointer in effect, never the pointer itself: the
# store's palette and mode survive the apply untouched, so when the mode ends
# the sun's or the user's choice comes back.
check "the baseline palette is intact" "mocha" "$(field palette)"
check "the baseline mode is intact" "manual" "$(field mode)"

# Not holding: leaving the mode (the pointer going neutral) resolves again
# from the baseline.
printf '{"mode":"neutral","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"
check "the lease is given back when the mode ends" "mocha" "$("$THEME" get)"

# A timed mode whose `until` already passed reads as neutral — the same rule
# the mode policy keeps everywhere else.
printf '{"mode":"gaming","until":"2020-01-01T00:00:00Z"}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"
check "a lapsed lease resolves from the baseline" "mocha" "$("$THEME" get)"

# An unknown lease palette reads as none — resolution never fails.
printf '{"mode":"gaming","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"
printf '{"modes":{"gaming":{"name":"Gaming","presentation":{"palette":"dracula"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
check "an unknown lease falls to the baseline" "mocha" "$("$THEME" get)"

# No declaration at all: no lease, no crash.
rm "$XDG_STATE_HOME/quantum-store/hyprfocus.json"
check "a missing declaration still resolves" "mocha" "$("$THEME" get)"
teardown

echo "auto mode keeps resolving under the lease"
setup
printf '{"mode":"auto","day":"latte","night":"mocha","palette":"frappe"}\n' >"$STORE"
printf '{"modes":{"gaming":{"name":"Gaming","presentation":{"palette":"frappe"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"gaming","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"
# Whatever the sun picks, the store's pointer follows it: so the lease ending
# later hands the desk back to the same palette the sun would have applied.
"$THEME" apply >/dev/null
case "$(field palette)" in
latte | mocha)
    printf '  ok   the store pointer follows the sun (%s)\n' "$(field palette)"
    pass=$((pass + 1))
    ;;
*)
    printf '  FAIL auto pointer moved to %s, expected a day/night palette\n' "$(field palette)"
    fail=$((fail + 1))
    ;;
esac
teardown

echo "a mode's leased palette can be a day/night pair"
setup
printf '{"mode":"manual","palette":"mocha","day":"latte","night":"mocha"}\n' >"$STORE"
printf '{"modes":{"work":{"name":"work","presentation":{"palette":{"day":"latte","night":"frappe"}}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"work","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"

check "the day half leases by day" "latte" "$(THEME_HOUR=10 "$THEME" get)"
check "the night half leases by night" "frappe" "$(THEME_HOUR=22 "$THEME" get)"
teardown

echo "a plain string lease palette applies to both day and night"
setup
printf '{"mode":"manual","palette":"mocha","day":"latte","night":"mocha"}\n' >"$STORE"
printf '{"modes":{"work":{"name":"work","presentation":{"palette":"frappe"}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"work","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"

check "a plain string leases by day too" "frappe" "$(THEME_HOUR=10 "$THEME" get)"
check "and by night" "frappe" "$(THEME_HOUR=22 "$THEME" get)"
teardown

echo "neutral holds no lease, day/night pair or not"
setup
printf '{"mode":"manual","palette":"mocha","day":"latte","night":"mocha"}\n' >"$STORE"
printf '{"modes":{"work":{"name":"work","presentation":{"palette":{"day":"latte","night":"frappe"}}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"neutral","until":null}\n' \
    >"$XDG_STATE_HOME/quantum-store/focus.json"

check "no held mode means the baseline answers by day" "mocha" "$(THEME_HOUR=10 "$THEME" get)"
check "and by night" "mocha" "$(THEME_HOUR=22 "$THEME" get)"
teardown

echo "shell: zsh/fzf get a generated theme file matching the resolved palette"
setup
"$THEME" set mocha >"$ROOT/out" 2>&1
check "BAT_THEME follows the palette" "Catppuccin Mocha" \
    "$(bash -c '. "$1" && printf "%s" "$BAT_THEME"' _ "$XDG_CONFIG_HOME/zsh/theme.zsh")"
# fzf takes one accent (mauve) from the flavour, so this is mocha's mauve --
# the check that the --color list is derived per palette, not a fixed table.
contains "fzf gets mocha's own colours" "hl:#cba6f7" "$(cat "$XDG_CONFIG_HOME/zsh/theme.zsh")"
# The rest of the shell's palette rides the same file, so a regression that
# drops one of them (a hardcoded flavour winning in the rc, say) fails here.
shell_var() { bash -c '. "$1" && printf "%s" "${!2}"' _ "$XDG_CONFIG_HOME/zsh/theme.zsh" "$2"; }
contains "delta follows the palette" "Catppuccin Mocha" "$(shell_var _ DELTA_OPTS)"
contains "eza gets mocha's directory colour" "di=38;2;203;166;247" "$(shell_var _ EZA_COLORS)"
check "difftastic is told mocha is dark" "dark" "$(shell_var _ DFT_BACKGROUND)"
contains "less headings take mocha's mauve" "38;2;203;166;247" "$(shell_var _ LESS_TERMCAP_md)"
contains "zsh highlighting follows the palette" "fg=#a6adc8" \
    "$(grep "ZSH_HIGHLIGHT_STYLES\[comment\]" "$XDG_CONFIG_HOME/zsh/theme.zsh")"
contains "shell is reported as applied, not pending" "shell: Mocha" "$(cat "$ROOT/out")"
"$THEME" set latte >/dev/null 2>&1
check "a second palette rewrites the same file" "Catppuccin Latte" \
    "$(bash -c '. "$1" && printf "%s" "$BAT_THEME"' _ "$XDG_CONFIG_HOME/zsh/theme.zsh")"
teardown

echo "one path: the automatic poll (\`get\`) and a manual \`set\` land on the same surfaces"
# LEO-398: Theme.qml's clock decides whether to fan out by asking \`,theme.sh
# get\` for the resolved palette (the same resolver \`apply\`/\`set\`/\`toggle\`
# use) rather than re-deriving lease/baseline itself — so this pins that the
# automatic trigger and a manual one are not two routes that can drift: both
# end up running the identical \`apply\`, writing the identical surfaces.
setup
printf '{"modes":{"work":{"name":"work","presentation":{"palette":{"day":"latte","night":"mocha"}}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"work","until":null}\n' >"$XDG_STATE_HOME/quantum-store/focus.json"

# What the clock's poll would see at night, and what it would then apply —
# exactly the two calls \`noteLease\`/\`applyToSystem\` make, in order.
resolved_night=$(THEME_HOUR=22 "$THEME" get)
check "the automatic poll resolves the leased night half" "mocha" "$resolved_night"
THEME_HOUR=22 "$THEME" apply >"$ROOT/automatic.out" 2>&1
automatic_kitty=$(readlink "$XDG_CONFIG_HOME/kitty/current-theme.conf")
automatic_bat=$(bash -c '. "$1" && printf "%s" "$BAT_THEME"' _ "$XDG_CONFIG_HOME/zsh/theme.zsh")
automatic_gsettings=$(gsettings_log)

# A manual pick of the same palette, from a clean store, must write the
# identical surfaces — proving there is exactly one code path underneath.
teardown
setup
printf '{"modes":{"work":{"name":"work","presentation":{"palette":{"day":"latte","night":"mocha"}}}}}\n' \
    >"$XDG_STATE_HOME/quantum-store/hyprfocus.json"
printf '{"mode":"work","until":null}\n' >"$XDG_STATE_HOME/quantum-store/focus.json"
THEME_HOUR=22 "$THEME" set mocha >"$ROOT/manual.out" 2>&1
manual_kitty=$(readlink "$XDG_CONFIG_HOME/kitty/current-theme.conf")
manual_bat=$(bash -c '. "$1" && printf "%s" "$BAT_THEME"' _ "$XDG_CONFIG_HOME/zsh/theme.zsh")
manual_gsettings=$(gsettings_log)

check "kitty: automatic matches manual" "$manual_kitty" "$automatic_kitty"
check "shell theme: automatic matches manual" "$manual_bat" "$automatic_bat"
check "gsettings: automatic matches manual" "$manual_gsettings" "$automatic_gsettings"
teardown

# A recorder standing in for hyprctl, the same trick awww_stub uses. Pointing
# THEME_HYPRCTL at it is what tells apply_hyprland this run may call through —
# a bare sandboxed run, with the variable unset, still gets held back.
hyprctl_stub() {
    HYPRCTL_LOG="$ROOT/hyprctl.log"
    : >"$HYPRCTL_LOG"
    cat >"$ROOT/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
exit 0
STUB
    chmod +x "$ROOT/hyprctl"
    export THEME_HYPRCTL="$ROOT/hyprctl" HYPRCTL_LOG
}

echo "reload suppression: a wallpaper-only rotation never touches hyprctl (LEO: deck relayout)"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'a' >"$XDG_CONFIG_HOME/hypr/wallpapers/a.png"
printf 'b' >"$XDG_CONFIG_HOME/hypr/wallpapers/b.png"
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
hyprctl_stub
"$THEME" set mocha >/dev/null # establish a palette to cycle wallpapers under
: >"$HYPRCTL_LOG"             # the set above legitimately reloads once; isolate the cycle itself
"$THEME" wallpaper next >/dev/null
"$THEME" wallpaper prev >/dev/null
"$THEME" wallpaper random >/dev/null
check "cycling next/prev/random issued zero hyprctl calls" "0" "$(wc -l <"$HYPRCTL_LOG" | tr -d ' ')"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG THEME_HYPRCTL HYPRCTL_LOG
teardown

echo "reload suppression: an hourly re-apply of the same palette skips hyprctl reload"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'source' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
hyprctl_stub
"$THEME" set mocha >/dev/null
reload_calls_first=$(grep -c '^reload$' "$HYPRCTL_LOG")
: >"$HYPRCTL_LOG"
# theme-auto.timer's hourly tick: the same palette applies again with no
# palette change — this must not reload (the first apply legitimately may,
# once for the new palette and once for transparency's first-ever stamp).
"$THEME" apply >"$ROOT/second-apply.out" 2>&1
check "the first apply did reload" "1" "$([ "$reload_calls_first" -gt 0 ] && echo 1 || echo 0)"
check "the repeat apply issued no reload" "0" "$(grep -c '^reload$' "$HYPRCTL_LOG")"
contains "the repeat apply says so" "unchanged, no reload" "$(cat "$ROOT/second-apply.out")"
contains "wallpaper still re-applies on the unchanged apply" "wallpaper: mocha.png" "$(cat "$ROOT/second-apply.out")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG THEME_HYPRCTL HYPRCTL_LOG
teardown

echo "reload suppression: an actual palette switch still reloads"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'source' >"$XDG_CONFIG_HOME/hypr/wallpapers/mocha.png"
printf 'source' >"$XDG_CONFIG_HOME/hypr/wallpapers/latte.png"
export THEME_MAGICK="$ROOT/no-such-magick-binary"
awww_stub
hyprctl_stub
"$THEME" set mocha >/dev/null
: >"$HYPRCTL_LOG"
"$THEME" set latte >/dev/null
check "switching palette still reloads" "1" "$(grep -c '^reload$' "$HYPRCTL_LOG")"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG THEME_HYPRCTL HYPRCTL_LOG
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
