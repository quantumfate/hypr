#!/usr/bin/env bash
# Copy Dofus settings/presets across accounts the way the Dofus submap wants
# it: a held terminal shows the per-account log, and one toast reports the
# outcome. BETA + EXPERIMENTAL by default; pass copy_settings.sh flags to
# narrow it.
#
#   ,copy-settings.sh            # BETA + EXPERIMENTAL
#   ,copy-settings.sh --release  # one RELEASE-to-RELEASE pass
#
# The engine is bin/copy_settings.sh (ex-dofus-scripts); this only picks the
# bound default and reports. Exits non-zero when the copy does, so the toast is
# honest.
set -uo pipefail

if [[ $# -eq 0 ]]; then
    set -- --all
fi

if copy_settings.sh "$@"; then
    ,notify dofus-settings "Dofus settings copied" "$*"
else
    status=$?
    ,notify dofus-settings "Dofus settings copy failed" "exit $status"
    exit "$status"
fi
