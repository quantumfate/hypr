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

- [x] Split package vars: `hypr_packages` (repo) vs `hypr_aur_packages`.
- [x] Correct AUR set: grim-hyprland-git, catppuccin-sddm-theme-\*, qt6ct-kde,
      greetd-dms-greeter-git (dropped stale greetd-tuigreet-fork-bin).
- [x] AUR helper task (paru/yay) for `hypr_aur_packages`.
- [x] Deploy `session/**` files (uwsm env, user units, greeter fragment).
- [x] Enable user units (hypridle, hyprpaper, hyprsunset, hyprpolkitagent).
- [x] `hypr_gpu` var gating the NVIDIA env block.
- [ ] galaxy `meta/main.yml` completeness — verify before any publish.

## Phase 3 — nix delivery (nix path)

- [x] flake: `nixosModules.hypr` + `homeManagerModules.hypr`.
- [x] home module: deploy config dir + session files via home-manager.
- [x] nixos module: programs.hyprland, portals, ecosystem packages.
- [ ] `nix flake check` green — unverified locally (no nix on host); CI gates.

## Phase 4 — CI (validate-only)

- [x] `flake check` job.
- [x] ansible syntax-check + ansible-lint (via `just check-all`).
- [x] stylua --check, shellcheck, shfmt, yamllint (via `just check-all`).
- [ ] Confirm green on first PR run; no publish step (deferred).

## Phase 4b — ecosystem release channel (stable | git)

- [x] Scout soname coupling (libhyprutils universal) + AUR -git set.
- [x] Ansible: `hypr_channel`, split core/git/tool package vars, paru group.
- [x] Nix: Hyprland + daemon flake inputs, `follows`-unified libs, hyprGit
      overlay, `channel` module option.
- [x] Document compatibility model in ARCHITECTURE.md.
- [ ] `nix flake lock` + `flake check` — unverified locally (no nix); CI gates.
- [ ] LIVE swap to git (heavy compositor rebuild) — do only on confirm.

## Phase 5 — retire from chezmoi (LIVE SYSTEM — do last, with confirm)

- [ ] Remove absorbed files from chezmoi source.
- [ ] Fold hypr package entries out of chezmoi `packages.yaml`.
- [ ] Point chezmoi bootstrap at this repo's ansible role (or nix) for hypr.
- [ ] Verify fresh-apply still converges; `chezmoi diff` clean.

## Phase 6 — verify whole environment

- [ ] `ansible-playbook --check` on this host.
- [ ] `nix flake check` + build modules (dry).
- [ ] Fresh-session smoke: units up, env exported, greeter renders.
