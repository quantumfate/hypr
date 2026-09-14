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
    mkdir -p "$XDG_CONFIG_HOME"/{kitty/themes,qt5ct/colors,qt6ct/colors,Kvantum} "$XDG_STATE_HOME"

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

    STORE="$XDG_STATE_HOME/theme.json"
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

echo "wallpaper resolution: mood beats palette, palette beats the single fallback"
setup
export THEME_MAGICK="$ROOT/no-such-magick-binary" # image processing is not the point here
awww_stub
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'single' >"$ROOT/single.png"
printf 'palette-bound' >"$ROOT/palette.png"
printf 'mood-bound' >"$ROOT/mood.png"

# Nothing bound yet: falls all the way through to the bare `wallpaper` field.
printf '{"palette":"mocha","mode":"manual","wallpaper":"%s"}\n' "$ROOT/single.png" >"$STORE"
"$THEME" apply >/dev/null
contains "no binding falls back to the single wallpaper" "single.png" "$(cat "$AWWW_LOG")"

# A palette binding outranks the bare fallback.
"$THEME" wallpaper "$ROOT/palette.png" mocha >/dev/null
: >"$AWWW_LOG"
"$THEME" apply >/dev/null
contains "a palette binding outranks the bare fallback" "palette.png" "$(cat "$AWWW_LOG")"

# A mood binding outranks the palette binding, even though both are set.
"$THEME" mood-wallpaper "$ROOT/mood.png" work >/dev/null
jq '.mood = "work"' "$STORE" >"$STORE.tmp" && mv "$STORE.tmp" "$STORE"
: >"$AWWW_LOG"
"$THEME" apply >/dev/null
contains "mood wins over the bound palette" "mood.png" "$(cat "$AWWW_LOG")"
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
contains "a second unbound apply still answers" "rain.png" "$(cat $AWWW_LOG)"

rm -f "$XDG_CONFIG_HOME/hypr/wallpapers"/*
"$THEME" apply >"$ROOT/out" 2>&1
contains "an empty wallpaper directory still reports unchanged" "wallpaper: unchanged" "$(cat $ROOT/out)"
unset THEME_MAGICK THEME_AWWW THEME_AWWW_DAEMON AWWW_LOG
teardown

echo "wallpaper resolution: an unknown mood is refused, like an unknown palette"
setup
mkdir -p "$XDG_CONFIG_HOME/hypr/wallpapers"
printf 'x' >"$ROOT/x.png"
if "$THEME" mood-wallpaper "$ROOT/x.png" nightmare >/dev/null 2>&1; then
    printf '  FAIL an unknown mood was accepted\n'
    fail=$((fail + 1))
else
    printf '  ok   an unknown mood is refused\n'
    pass=$((pass + 1))
fi
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
