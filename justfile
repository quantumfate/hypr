# Task runner. Run `just` to list recipes.
# Recipes are generated from the detected toolchain; edit freely.

default:
	@just --list

# Reformat the tree in place
fmt:
	stylua .
	shfmt -w -i 4 .
	prettier --write '**/*.md'
	nixpkgs-fmt .

# Verify formatting without writing
fmt-check:
	stylua --check .
	shfmt -d -i 4 .
	prettier --check '**/*.md'
	nixpkgs-fmt --check .

# Static analysis
lint:
	luacheck .
	git ls-files '*.sh' '*.bash' | xargs -r shellcheck
	yamllint .

# CI/pre-commit gate: formatting + tests (lint is advisory)
check: fmt-check

# Bootstrap the local dev environment (hooks, toolchain, PATH)
setup:
	./scripts/setup.sh

# Install the system toolchain via ansible (needs sudo)
provision:
	ansible-playbook scripts/provision.yml --ask-become-pass

# Enter the reproducible nix dev shell
dev:
	nix develop
