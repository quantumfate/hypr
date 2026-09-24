#!/usr/bin/env bash
# Routing contract for ,zen-dispatcher.sh.
#
# The script hands URLs to a zen profile + container on a real desk (through
# uwsm-app), so the tests replace the desk with a scratch PATH: fakes for
# `uwsm-app` and `,notify` log their arguments and exit 0, and everything else
# (python3, …) comes from the real system PATH. Nothing here may reach a real
# browser or the real notification service.
#
# The contract under test: companion routing is a document, the script is one
# executor. The Ankama login flow — the launcher's OAuth callback on
# 127.0.0.1:9001 and the auth.ankama.com pages before it — must land in the
# Dofus profile's Dofus container; dev servers on localhost go to Firefox dev
# edition; the media set goes to the Media profile. Anything else is refused
# through ,notify (which carries the x-hyprfocus-source hint by construction,
# asserted at the file level in notify_source_test.sh).
set -euo pipefail

ROOT_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DISPATCHER="$ROOT_REPO/bin/,zen-dispatcher.sh"
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

# Scratch desk: a fake bin dir on PATH logs every call the dispatcher would
# make on a real desktop.
ROOT=$(mktemp -d)
FAKE="$ROOT/fake-bin"
mkdir -p "$FAKE"

printf '#!/usr/bin/env bash\nprintf "uwsm-app: %%s\\n" "$*" >> "%s"\n' "$ROOT/apps.log" >"$FAKE/uwsm-app"
chmod +x "$FAKE/uwsm-app"
printf '#!/usr/bin/env bash\nprintf "notify: %%s\\n" "$*" >> "%s"\n' "$ROOT/notify.log" >"$FAKE/,notify"
chmod +x "$FAKE/,notify"

LAST_STATUS=0
run() { # url [extra args...]
    : >"$ROOT/apps.log"
    : >"$ROOT/notify.log"
    local url=$1
    shift
    set +e
    PATH="$FAKE:$PATH" "$DISPATCHER" "$@" "$url"
    LAST_STATUS=$?
    set -e
}

apps_log() { cat "$ROOT/apps.log"; }
notify_log() { cat "$ROOT/notify.log"; }

echo "the Ankama launcher's OAuth callback routes to the Dofus container"
run 'http://127.0.0.1:9001/oauth2/authorize?response_type=code&client_id=zaap'
contains "the callback survives the localhost bypass" "uwsm-app: -- zen-twilight -P Dofus --name zen-twilight-dofus" "$(apps_log)"
contains "and carries the ext+container url" 'ext+container:name=Dofus&url=' "$(apps_log)"
contains "the callback URL itself is encoded, not the callback host" "url=http%3A%2F%2F127.0.0.1%3A9001%2F" "$(apps_log)"

echo "auth.ankama.com (the launcher's login page) routes to Dofus too"
run 'https://auth.ankama.com/login?return_url=https%3A%2F%2Fwww.ankama.com'
contains "the login page opens in the Dofus profile" "uwsm-app: -- zen-twilight -P Dofus --name zen-twilight-dofus" "$(apps_log)"
contains "and the Dofus container" "ext+container:name=Dofus" "$(apps_log)"

echo "media sites open in the media profile, each in its own container"
run 'https://www.youtube.com/watch?v=abc123'
contains "youtube lands in the media profile" "-P Media --name zen-twilight-media --no-remote" "$(apps_log)"
contains "and the Social Media container" 'ext+container:name=Social Media&url=' "$(apps_log)"

echo "real local dev servers are outside the container matrix"
run 'http://127.0.0.1:8080/app'
contains "a 127.0.0.1 dev server goes to firefox dev edition" "uwsm-app: -- firefox-developer-edition" "$(apps_log)"
run 'http://localhost:3000'
contains "localhost does too" "uwsm-app: -- firefox-developer-edition" "$(apps_log)"

echo "an unknown domain is refused and reported through ,notify"
run 'https://example.com/'
check "refusal exits 0 (the URL is handled, not an error)" "0" "$LAST_STATUS"
contains "and names the zen-dispatcher source" "notify: zen-dispatcher" "$(notify_log)"
contains "and says the URL is not yet allowed" "External URL" "$(notify_log)"

echo "a malformed URL is rejected up front"
run 'not-a-url'
check "rejection exits 1" "1" "$LAST_STATUS"
contains "and names the zen-dispatcher source" "notify: zen-dispatcher" "$(notify_log)"
contains "and says the pattern is not allowed" "URL Pattern not allowed" "$(notify_log)"

rm -rf "$ROOT"

echo
echo "theme: passes=$pass fails=$fail"
[ "$fail" -eq 0 ]
