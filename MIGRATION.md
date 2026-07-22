# Migration — chezmoi → hypr repo (dual nix/ansible delivery)

Tracks folding the Hyprland ecosystem out of chezmoi into this repo as a
dual-delivered (nix + ansible), validate-in-CI environment. See ARCHITECTURE.md.

## Phase 0 — decisions (done)
- [x] Dual full delivery: nix for nix hosts, ansible for the rest.
- [x] Scope = Hyprland ecosystem; keep this repo; CI validate-only.

## Phase 1 — absorb session glue into repo (additive, safe)
- [x] `session/uwsm/env-hyprland` (GPU block gated).
- [x] `session/systemd/hypridle.service`, `hyprpaper.service`.
- [x] `session/greeter/dms-hypr.conf`.
- [x] `ARCHITECTURE.md`, `session/README.md`.

## Phase 2 — ansible delivery (non-nix path)
- [ ] Split package vars: `hypr_packages` (repo) vs `hypr_aur_packages`.
- [ ] Correct AUR set: grim-hyprland-git, catppuccin-sddm-theme-*, qt6ct-kde,
      greetd-dms-greeter-git (drop stale greetd-tuigreet-fork-bin).
- [ ] AUR helper task (paru/yay) for `hypr_aur_packages`.
- [ ] Deploy `session/**` files (uwsm env, user units, greeter fragment).
- [ ] Enable user units (hypridle, hyprpaper, hyprsunset, hyprpolkitagent).
- [ ] `hypr_gpu` var gating the NVIDIA env block.
- [ ] galaxy `meta/main.yml` completeness (platforms, min_ansible_version).

## Phase 3 — nix delivery (nix path)
- [ ] flake: add `nixosModules.hypr` + `homeModules.hypr`.
- [ ] home module: deploy config dir + session files via home-manager.
- [ ] nixos module: enable programs.hyprland, portals, packages, user units.
- [ ] Keep devShell; `nix flake check` green.

## Phase 4 — CI (validate-only)
- [ ] `flake check` job.
- [ ] `ansible-lint` + `yamllint` job.
- [ ] stylua --check, shellcheck, shfmt (already partly in pre-commit).
- [ ] Matrix/caching; no publish step yet.

## Phase 5 — retire from chezmoi (LIVE SYSTEM — do last, with confirm)
- [ ] Remove absorbed files from chezmoi source.
- [ ] Fold hypr package entries out of chezmoi `packages.yaml`.
- [ ] Point chezmoi bootstrap at this repo's ansible role (or nix) for hypr.
- [ ] Verify fresh-apply still converges; `chezmoi diff` clean.

## Phase 6 — verify whole environment
- [ ] `ansible-playbook --check` on this host.
- [ ] `nix flake check` + build modules (dry).
- [ ] Fresh-session smoke: units up, env exported, greeter renders.
