#!/usr/bin/env bash

PROFILE_MANAGER=false
PRIVATE=false
# Parse flags
while [[ "$1" == -* ]]; do
    case "$1" in
    --ProfileManager)
        PROFILE_MANAGER=true
        shift
        ;;
    --private-window)
        PRIVATE=true
        shift
        ;;
    *) shift ;;
    esac
done
URL="$1"

case "$URL" in
https://* | *http://*) ;;
*)
    ,notify zen-dispatcher "URL Pattern not allowed: $URL"
    exit 1
    ;;
esac

# Build args
ARGS=()
[[ "$PROFILE_MANAGER" == true ]] && ARGS+=(--ProfileManager)
[[ "$PRIVATE" == true ]] && ARGS+=(--private-window)

# Bypass container routing for certain domains
case "$URL" in
*proton.me*)
    uwsm-app -- zen-twilight "${ARGS[@]}" "$URL"
    exit 0
    ;;
# Ankama OAuth callback port → fall through to Gaming/Media mapping below
http://127.0.0.1:9001* | https://127.0.0.1:9001*) ;;
# Real local dev servers → firefox dev edition (anchored to host, not embedded redirect_uri)
http://127.0.0.1* | https://127.0.0.1* | http://localhost* | https://localhost* | http://\[::1\]* | https://\[::1\]*)
    uwsm-app -- firefox-developer-edition "$URL"
    exit 0
    ;;
esac

# Define domain → container mappings
case "$URL" in
*dofus.com* | *dofusbook.net* | *d-bk.net* | *dofensive.com* | *dofusdb.fr* | *barbofus.com* | *auth.ankama.com* | *ankama.com* | *dofuspourlesnoobs.com* | *dofuswiki.fandom.com* | http*://127.0.0.1*9001* | *ankama*localhost*)
    ARGS+=("-P" "Dofus" "--name" "zen-twilight-dofus")
    CONTAINER="Dofus"
    ;;
*claude.ai* | *codeberg.org* | *github.com* | *gitlab.com* | *stackoverflow.com* | *obsidian.md* | *linkedin.com* | *sendgrid.net* | *readyforlinux.com* | *docker.com* | *hypr.land* | *archlinux.org* | *debian.org* | *lua.org* | *neovim.io* | *boot.dev*)
    CONTAINER="Productivity"
    ;;
*mit.edu*)
    CONTAINER="Studying"
    ;;
*datev.de* | *revolut.com* | *ing.de* | *hushed.com* | *paypal.com* | *skrill.com* | *doctolib.de*)
    CONTAINER="Personal"
    ;;
*twitch.tv* | *youtube.com* | *youtu.be* | *reddit.com* | *discord.com* | *x.com* | *instagram.com* | *tinder.com* | *spotify.com* | *discordapp.com*)
    ARGS+=("-P" "Media" "--name" "zen-twilight-media" "--no-remote")
    CONTAINER="Social Media"
    ;;
*myanimelist.net* | *crunchyroll.com* | *animeschedule.net*)
    ARGS+=("-P" "Media" "--name" "zen-twilight-media" "--no-remote")
    CONTAINER="Anime"
    ;;
*store.steampowered.com* | *elderscrollsonline.com* | *esologs.com* | *esoserverstatus.net* | *eso-hub.com*)
    ARGS+=("-P" "Media" "--name" "zen-twilight-media" "--no-remote")
    CONTAINER="Gaming"
    ;;
*amazon.de* | *otto.de*)
    ARGS+=("-P" "Media" "--name" "zen-twilight-media" "--no-remote")
    CONTAINER="Shopping"
    ;;
*)
    ,notify zen-dispatcher "External URL ($URL) not yet allowed" "" -u critical
    exit 0
    ;;
esac
# URL-encode the target URL
ENCODED_URL=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$URL")

uwsm-app -- zen-twilight "${ARGS[@]}" "ext+container:name=$CONTAINER&url=$ENCODED_URL"
