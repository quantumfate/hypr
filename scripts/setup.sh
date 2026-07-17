#!/usr/bin/env bash
set -euo pipefail

log_info() { printf '\033[0;34m[INFO]\033[0m %s\n' "$1"; }
log_ok() { printf '\033[0;32m\xe2\x9c\x94\033[0m %s\n' "$1"; }
log_warn() { printf '\033[0;33m\xe2\x9a\xa0\033[0m %s\n' "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

log_info "Setting up development environment..."

# Git hooks via pre-commit.
if have pre-commit; then
  pre-commit install --hook-type pre-commit --hook-type commit-msg -f
  log_ok "Git hooks installed"
else
  log_warn "pre-commit not found - install it, then re-run this script"
fi

# Conventional-commit message template.
if [[ -f ".gitmessage" ]]; then
  git config commit.template .gitmessage
  log_ok "Commit template enabled"
fi

log_ok "Setup complete."
log_info "System toolchain:     just provision"
log_info "Reproducible shell:   nix develop"
log_info "Run checks:           just check"
