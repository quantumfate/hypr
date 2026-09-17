#!/usr/bin/env bash
# Run every scenario (or those named) in its own nested compositor; exit
# non-zero if any failed.
set -uo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
if (($#)); then scenarios=("$@"); else scenarios=("$dir"/scenarios/*.sh); fi

failed=()
for s in "${scenarios[@]}"; do
    printf '== %s\n' "$(basename "$s")"
    timeout "${E2E_SCENARIO_TIMEOUT:-120}" "$s" || failed+=("$(basename "$s")")
done
if ((${#failed[@]})); then
    printf 'e2e: failed: %s\n' "${failed[*]}" >&2
    exit 1
fi
echo "e2e: all passed"
