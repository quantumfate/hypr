#!/usr/bin/env bash
# ,obsidian-cli-wrapper.sh — Obsidian vault bootstrap (Zettelkasten + index notes).
# Thin shell front-end for bin/obsidian_vault.py.
#
#   ,obsidian-cli-wrapper.sh status                     vault/store status
#   ,obsidian-cli-wrapper.sh sync                       rebuild tags.json + .gpg
#   ,obsidian-cli-wrapper.sh dump [--raw]               tag-structure report
#   ,obsidian-cli-wrapper.sh ensure-topic <topic>       create missing index notes
#   ,obsidian-cli-wrapper.sh create <note_type> <title> --tag <topic> [opts]
#
#   note_type: atomic | fleeting | moc | journal | blog
#
# Examples:
#   ,obsidian-cli-wrapper.sh create atomic "Generating an EdDSA SSH Key" \
#       --tag Technology/Systems/Security/GPG-Keys
#   ,obsidian-cli-wrapper.sh ensure-topic Technology/Systems/Security/GPG-Keys
#
# Full options (--dry-run, --no-chain, --open, --tags): obsidian_vault.py --help.
set -euo pipefail
BIN="$(dirname "$(readlink -f "$0")")"

case "${1:-status}" in
help | -h | --help)
    sed -n '1,16p' "$0"
    exec python3 "$BIN/obsidian_vault.py" --help
    ;;
*)
    exec python3 "$BIN/obsidian_vault.py" "$@"
    ;;
esac
