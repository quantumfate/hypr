# Architecture — hypr environment packaging

This repo is the **single source of truth** for a self-contained Hyprland
_environment_: the compositor config plus the surrounding `hypr*` ecosystem
session glue, delivered reproducibly to two classes of machine.

## Delivery model — dual, full, equal

| Path        | Target machines                            | Installs + deploys via                            |
| ----------- | ------------------------------------------ | ------------------------------------------------- |
| **Nix**     | NixOS / nix-managed hosts                  | `flake.nix` → NixOS + home-manager modules        |
| **Ansible** | everything else (Arch/CachyOS, other unix) | `ansible/roles/hypr` → pacman + AUR + file deploy |

Both paths are first-class and kept in sync: same package set, same deployed
files, same end state. Nix is for nix machines; Ansible is for non-nix ones.
The Lua config, assets, and `.conf` files are shared verbatim by both.

## Scope — the Hyprland ecosystem

In scope (absorbed into this repo, out of chezmoi):

- Compositor + config: `hyprland`, this repo's `hypr/**.lua` and `*.conf`.
- Ecosystem daemons: `hypridle`, `hyprpaper`, `hyprsunset`, `hyprlock`,
  `hyprpolkitagent`, `hyprpicker`, `hyprshot`, `hyprcursor`.
- Session glue: `uwsm` env (`env-hyprland`), the `hypr*` systemd **user**
  units, portal backends (`xdg-desktop-portal-hyprland` + gtk).
- Greeter fragment tied to the compositor (`dms-hypr.conf`).

Out of scope (stays in chezmoi, `$HOME` dotfiles): waybar, shell, editors,
file managers, and other non-hypr configs. The bar is `quickshell` (separate
repo, part of the running environment — see the store-bridge), not waybar.

Packages are inferred from the ecosystem's own dependencies, not hand-listed.

## Source layout

- `hypr/` — Lua config (the running compositor logic).
- `*.conf` — hypr* daemon configs (hypridle, hyprlock, hyprpaper, …).
- `assets/`, `icons/`, `wallpapers/` — generated + static assets.
- `session/` — session glue absorbed from chezmoi (uwsm env, systemd user
  units, greeter fragment). Deployed identically by both paths.
- `flake.nix` — nix delivery (devShell + NixOS/home-manager modules).
- `ansible/` — ansible delivery (role `hypr`, playbook, galaxy meta).
- `.github/` — CI: validate-only (flake check, ansible-lint, stylua,
  shellcheck). Publishing (Galaxy / cachix) deferred until stable.

## Dependency completeness (verified)

- **hypr** — every binary the Lua config / `*.conf` / `scripts/` invoke maps to
  a listed package. `grim`, `slurp`, `wl-clipboard`, `jq`, `libnotify` arrive
  transitively as `hyprshot` dependencies, so they need no explicit entry. Only
  `ankama-launcher` (proprietary) is intentionally excluded.
- **quickshell** (sibling repo — deps owned there, not duplicated in this role).
  Its package pulls the hard deps (qt6-base/declarative/svg/wayland, libpipewire,
  polkit). Two QML needs are _not_ hard deps and must be provided by the
  quickshell packaging: `Qt5Compat.GraphicalEffects` → `qt6-5compat`, and
  `Services.UPower` → the `upower` service. Integration binaries it shells out to
  (`hyprctl`, `notify-send`, `pkill`, `bash`) are all covered by the hypr set.

## Release channel & ecosystem compatibility

The `hypr*` ecosystem is **soname-coupled**. `hyprland` and every daemon link
shared libs — `libhyprutils.so` is universal (all of hyprland, hyprlock,
hypridle, hyprpaper, hyprsunset, hyprpicker, portal, qt-support, guiutils),
with `libhyprlang/graphics/aquamarine/wire` on subsets. A lib soname bump
(e.g. `libhyprutils.so.13 → .14`) forces **every consumer to be rebuilt**
against it. Consequence: the ecosystem moves as **one atomic unit** — you
cannot run a git compositor against stable daemons. Only `hyprpolkitagent`
(Qt-only) is decoupled.

Two channels, selected per delivery path:

| Channel  | Ansible                                                        | Nix                          |
| -------- | -------------------------------------------------------------- | ---------------------------- |
| `stable` | official-repo packages (`hypr_core_packages`)                  | nixpkgs packages             |
| `git`    | AUR `-git` group in one paru transaction (`hypr_git_packages`) | the Hyprland + daemon flakes |

**How compatibility is enforced:**

- **Ansible/AUR** — `hyprland-git` _declares the `-git` libs as dependencies_
  (aquamarine-git, hyprutils-git, hyprlang-git, hyprgraphics-git, hyprcursor-git,
  hyprwire-git, hyprland-protocols-git, hyprwayland-scanner-git,
  hyprland-guiutils-git), so paru pulls the whole lib chain and builds it in one
  transaction against a single HEAD. The role only lists the **daemons** as
  `-git` (they link the libs but aren't pulled by the compositor). Update the
  whole group together: `paru -Sua` (devel upgrade). Never `-Syu` a stable lib
  under a git compositor.
- **Nix** — each daemon flake's shared-lib inputs `follow` the Hyprland flake's
  (`hypridle.inputs.hyprutils.follows = "hyprland/hyprutils"`, …), so the entire
  set resolves to **one** hyprutils/hyprlang/hyprgraphics/aquamarine → one
  soname → compatible by construction. `flake.lock` pins the commit set
  (reproducible rolling); `nix flake update` bumps them atomically. The
  `hyprGit` overlay swaps the coupled packages for the flake builds when
  `programs.hyprEnvironment.channel = "git"`.

Note: on CachyOS the official repos are already very fresh (often ahead of the
AUR `.SRCINFO` snapshots), so `git` mainly buys _unreleased_ commits (e.g. the
`hyprctl binds -j` serializer fix) at the cost of local rebuilds.

## Package classification (Arch/AUR)

Most `hypr*` packages are in official CachyOS/Arch repos. Genuinely-AUR ones
are tracked separately in the role so an AUR helper (`paru`/`yay`) handles
only those: `grim-hyprland-git`, `catppuccin-sddm-theme-*`, `qt6ct-kde`,
`greetd-dms-greeter-git`. (Note: the old chezmoi `packages.yaml` listed a
stale `greetd-tuigreet-fork-bin` that is not installed — corrected here.)
