#!/usr/bin/env bash
# ,hyprfocus log — argument handling for the lifecycle journal query
# (LEO-352). journalctl is stubbed on PATH so this runs with no journal and
# no compositor; it asserts on the argv the stub recorded, not on any real
# log output.
set -euo pipefail

ROOT_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT_REPO/bin/,hyprfocus"
STATE=$(mktemp -d)
trap 'rm -rf "$STATE"' EXIT

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

# Records every argv it was called with, one line per call, so a test can
# assert on exactly what ,hyprfocus asked the journal for.
STUBDIR="$STATE/bin"
mkdir -p "$STUBDIR"
cat >"$STUBDIR/journalctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$JOURNALCTL_CALLS"
EOF
chmod +x "$STUBDIR/journalctl"
export PATH="$STUBDIR:$PATH"
export JOURNALCTL_CALLS="$STATE/calls.log"

run() { XDG_STATE_HOME="$STATE/xdg" "$CLI" "$@"; }

: >"$JOURNALCTL_CALLS"
run log --trace 0x1234 >/dev/null
check "--trace filters by TRACE=<address>" \
    "--user -t hyprfocus -o json TRACE=0x1234" \
    "$(tail -n1 "$JOURNALCTL_CALLS")"

: >"$JOURNALCTL_CALLS"
run log --follow >/dev/null
check "--follow adds -f, no trace filter" \
    "--user -t hyprfocus -o json -f" \
    "$(tail -n1 "$JOURNALCTL_CALLS")"

: >"$JOURNALCTL_CALLS"
run log --trace 0x1234 --follow >/dev/null
check "--trace and --follow combine" \
    "--user -t hyprfocus -o json -f TRACE=0x1234" \
    "$(tail -n1 "$JOURNALCTL_CALLS")"

: >"$JOURNALCTL_CALLS"
run log 3 >/dev/null 2>&1 || true
check "plain 'log <count>' never touches journalctl (scene-policy path)" \
    "" \
    "$(cat "$JOURNALCTL_CALLS")"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
