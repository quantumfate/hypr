#!/usr/bin/env bash
# Run every scenario (or those named) in its own nested compositor; exit
# non-zero if any failed.
set -uo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
if (($#)); then scenarios=("$@"); else scenarios=("$dir"/scenarios/*.sh); fi

# A scenario only ever runs from this directory's own `scenarios/`. A copy
# living anywhere else is how the live desk's store got overwritten once: the
# copy's `. "$(dirname "$0")/../lib.sh"` resolved to nothing, the script kept
# going with lib.sh's sandbox exports never applied, and its fixture write
# landed in $XDG_STATE_HOME/quantum-store instead of the sandbox.
for s in "${scenarios[@]}"; do
    real=$(cd "$(dirname "$s")" && pwd)/$(basename "$s")
    if [[ $real != "$dir/scenarios/"* ]]; then
        printf 'e2e: refusing to run a scenario outside %s/scenarios: %s\n' "$dir" "$s" >&2
        exit 2
    fi
done

failed=()
for s in "${scenarios[@]}"; do
    printf '== %s\n' "$(basename "$s")"
    # Poisoned before lib.sh gets a chance to point it at the sandbox: a
    # scenario that somehow runs without the harness writes to a dead path
    # and fails loudly, never to the live store.
    QF_STORE="$dir/.no-store-harness-did-not-boot" \
        timeout "${E2E_SCENARIO_TIMEOUT:-120}" "$s" || failed+=("$(basename "$s")")
done
if ((${#failed[@]})); then
    printf 'e2e: failed: %s\n' "${failed[*]}" >&2
    exit 1
fi
echo "e2e: all passed"
