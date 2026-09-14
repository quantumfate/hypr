#!/usr/bin/env bash
# ,hyprfocus-units — the two gates, and that they still fail when they should.
#
# A gate that only ever passes is indistinguishable from one that never runs,
# so this asserts the failing direction too: a capability naming a unit no
# repo installs, and a committed target the contract no longer produces.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
cli="$repo/bin/,hyprfocus-units"

fail=0
check() {
    local name=$1 expected=$2 actual=$3
    if [[ $actual == "$expected" ]]; then
        echo "  ok   $name"
    else
        echo "  FAIL $name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        fail=1
    fi
}

status() {
    set +e
    "$@" >/dev/null 2>&1
    local code=$?
    set -e
    echo "$code"
}

echo "hyprfocus-units:"

check "the committed targets match the contract" 0 "$(status "$cli" check)"
check "every declared unit has exactly one owner" 0 "$(status "$cli" verify --programme "$repo/..")"

# The failing direction, against a scratch copy so the real contract is never
# the thing under test.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cp -r "$repo" "$scratch/scripts"
drifted="$scratch/scripts/bin/,hyprfocus-units"

python3 - "$scratch/scripts/etc/scene-managed.json" <<'PY'
import json, sys
path = sys.argv[1]
contract = json.load(open(path))
contract["tasks"]["unowned"] = ["nothing-installs-this.service"]
json.dump(contract, open(path, "w"), indent=2)
PY

check "a unit no repo installs fails verify" 1 \
    "$(status "$drifted" verify --programme "$repo/..")"
check "a contract edited without regenerating fails check" 1 "$(status "$drifted" check)"

exit "$fail"
