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

# Ansible playbook syntax check (cheap; part of the CI gate)
ansible-syntax:
	ansible-playbook ansible/playbook.yml --syntax-check

# Validate the ansible delivery path (syntax + lint) — advisory, not gated
check-ansible: ansible-syntax
	ansible-lint ansible/

# Validate the nix delivery path (evaluates modules + devShell)
check-nix:
	nix flake check

# CI gate: formatting + ansible syntax (lint stays advisory, per `lint` above)
check-all: check ansible-syntax

# Bootstrap the local dev environment (hooks, toolchain, PATH)
setup:
	./scripts/setup.sh

# Install the system toolchain via ansible (needs sudo)
provision:
	ansible-playbook scripts/provision.yml --ask-become-pass

# Enter the reproducible nix dev shell
dev:
	nix develop

# Swap the hypr* ecosystem to the rolling git channel (interactive: confirm the
# stable→git replacements + review PKGBUILDs as the compositor rebuilds).
channel-git:
	paru -S --needed hyprland-git hyprland-qt-support-git hyprlock-git \
		hypridle-git hyprpaper-git hyprsunset-git hyprpicker-git \
		xdg-desktop-portal-hyprland-git

# Update the git-channel ecosystem (rebuild all -git packages together)
channel-update:
	paru -Sua
