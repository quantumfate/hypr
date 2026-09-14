#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ID="182117445"
DEFAULT_CHAR="0a2e393d8dbcce6b8b8c29c205e2b188"
TARGET_CHANNEL="RELEASE"

usage() {
  echo "Usage: $0 [-b|--beta] [-e|--experimental] [-a|--all] [account_id] [character_dir]"
  exit 1
}

ARGS=()
TARGET_CHANNELS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -b | --beta)
    TARGET_CHANNELS+=("BETA")
    shift
    ;;
  -e | --experimental)
    TARGET_CHANNELS+=("EXPERIMENTAL")
    shift
    ;;
  -r | --release)
    TARGET_CHANNELS+=("RELEASE")
    shift
    ;;
  -a | --all)
    TARGET_CHANNELS+=("BETA" "EXPERIMENTAL")
    shift
    ;;
  -h | --help) usage ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

SRC_ID="${ARGS[0]:-$DEFAULT_ID}"
SRC_CHAR="${ARGS[1]:-$DEFAULT_CHAR}"

# No channel flag given: keep old default of a single RELEASE-to-RELEASE pass.
[[ ${#TARGET_CHANNELS[@]} -gt 0 ]] || TARGET_CHANNELS=("$TARGET_CHANNEL")

ROOT="$HOME/.config/unity3d/Ankama/Dofus"
SRC_BASE="$ROOT/RELEASE/Accounts"
SRC_SHARED="$ROOT/RELEASE/Shared"
SRC="$SRC_BASE/$SRC_ID"

echo "Source:  RELEASE/$SRC_ID/$SRC_CHAR"
echo "Targets: ${TARGET_CHANNELS[*]} (all accounts/characters + Shared)"

[[ -d "$SRC" ]] || {
  echo "Source account not found: $SRC"
  exit 1
}

SRC_DOFUS="$SRC/dofus.json"
SRC_PRESET="$SRC/preset.json"
SRC_CHAR_DIR="$SRC/Characters/$SRC_CHAR"
SRC_CHAR_JSON="$SRC_CHAR_DIR/dofus.json"
SRC_SHARED_DOFUS="$SRC_SHARED/dofus.json"
SRC_SHARED_PRESET="$SRC_SHARED/preset.json"

for f in "$SRC_DOFUS" "$SRC_PRESET" "$SRC_CHAR_JSON" "$SRC_SHARED_DOFUS" "$SRC_SHARED_PRESET"; do
  [[ -f "$f" ]] || {
    echo "Missing source file: $f"
    exit 1
  }
done

# Copies the source settings over every account/character of one channel.
copy_to_channel() {
  local channel="$1"
  local target_base="$ROOT/$channel/Accounts"
  local target_shared="$ROOT/$channel/Shared"

  [[ -d "$target_base" ]] || {
    echo "warn: target base not found, skipping channel: $target_base"
    return 0
  }

  echo "== $channel =="

  # Shared folder
  if [[ "$channel" != "RELEASE" ]]; then
    if [[ -d "$target_shared" ]]; then
      echo "Shared: updating dofus.json + preset.json"
      cp -f "$SRC_SHARED_DOFUS" "$target_shared/dofus.json"
      cp -f "$SRC_SHARED_PRESET" "$target_shared/preset.json"
    else
      echo "warn: $target_shared not found, skipping"
    fi
  fi

  # Account-level files
  local dir acc
  for dir in "$target_base"/*/; do
    acc=$(basename "$dir")
    [[ "$acc" =~ ^[0-9]+$ ]] || continue
    [[ "$channel" == "RELEASE" && "$acc" == "$SRC_ID" ]] && continue

    echo "Account $acc: updating dofus.json + preset.json"
    cp -f "$SRC_DOFUS" "$dir/dofus.json"
    cp -f "$SRC_PRESET" "$dir/preset.json"
  done

  # Character dofus.json
  local char_dir
  while IFS= read -r -d '' char_dir; do
    [[ "$channel" == "RELEASE" && "$char_dir" == "$SRC_CHAR_DIR" ]] && continue
    echo "Char: ${char_dir#"$ROOT"/}"
    cp -f "$SRC_CHAR_JSON" "$char_dir/dofus.json"
  done < <(find "$target_base" -mindepth 3 -maxdepth 3 -type d -path "*/Characters/*" -print0)
}

for channel in "${TARGET_CHANNELS[@]}"; do
  copy_to_channel "$channel"
done
