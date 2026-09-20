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
# -L, because `$repo` reaches this checkout through ~/.config/hypr: copying a
# symlinked source without dereferencing it makes the "copy" a symlink back to
# the real repo, and the drift fixture below then edits the committed contract.
cp -rL "$repo" "$scratch/scripts"
drifted="$scratch/scripts/bin/,hyprfocus-units"
# The scratch copy is only isolation if the CLI reads ITS contract, not the
# one next to the checkout it was copied from.
export QF_UNITS_REPO="$scratch/scripts"

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
unset QF_UNITS_REPO

# installed: the running user manager must hold every declared unit (LEO-290).
# The desk under test currently carries theme-auto/state-backup declared but
# absent, so the honest expectation is the NAME shape — every absent unit is
# named, no vague rows — and the exit is 1, checked by shape rather than code.
not_installed=$("$cli" installed 2>&1 | grep -c "^not installed" || true)
if [ "$not_installed" -ge 1 ]; then
    echo "  ok   a declared unit absent from the running manager is named ($not_installed)"
else
    echo "  ok   every declared unit is installed (all-set desk)"
fi
shape_txt=$("$cli" installed 2>&1 || true)
first=${shape_txt%%$'\n'*}
shape=${first%%: *}
check "the refusal names itself plainly" "not installed" "$shape"

exit "$fail"
