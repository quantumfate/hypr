# Task runner. Run `just` to list recipes.
# Recipes are generated from the detected toolchain; edit freely.

# The shell helpers (bin/), by shebang rather than by name: bin/ holds Python
# too (,hyprfocus, dofus_swap.py) and shfmt cannot parse it.
shell_files := "$(git ls-files '*.sh' 'bin/,*' 'tests/*.sh' | xargs -r grep -lE '^#!.*(ba)?sh' )"
python_files := "$(git ls-files 'bin/*' '*.py' | xargs -r grep -lE '^#!.*python' )"

default:
	@just --list

# Reformat the tree in place
fmt:
	stylua .
	shfmt -w -i 4 {{ shell_files }}
	ruff format {{ python_files }}
	prettier --write '**/*.md'
	nixpkgs-fmt .

# Verify formatting without writing
fmt-check:
	stylua --check .
	shfmt -d -i 4 {{ shell_files }}
	ruff format --check {{ python_files }}
	prettier --check '**/*.md'
	nixpkgs-fmt --check .

# Static analysis
lint:
	luacheck .
	shellcheck {{ shell_files }}
	yamllint .

# Unit tests for hypr/lib/ (pure Lua, no compositor needed), then the shell
# helpers' own tests, against scratch XDG trees — never this machine.
test:
	lua tests/run.lua
	./tests/theme_test.sh
	./tests/scene_apply_test.sh
	./tests/hyprfocus_test.sh
	./tests/hyprfocus_units_test.sh

# Regenerate the capability targets (the systemd seam bin/,hyprfocus-units
# writes). `just check` fails if the committed ones and the contract have
# drifted, so this is what clears that.
units:
	./bin/,hyprfocus-units generate

# CI/pre-commit gate: formatting + luacheck + tests (shellcheck/yamllint stay advisory via `lint`)
check: fmt-check test
	@../hypr/bin/,privacy-check

	luacheck .

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
