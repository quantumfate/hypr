# Architecture — hypr environment packaging

This repo is the **single source of truth** for a self-contained Hyprland
_environment_: the compositor config plus the surrounding `hypr*` ecosystem
session glue, delivered reproducibly by **Ansible**.

## Delivery model — one path

| Path        | Target machines             | Installs + deploys via                            |
| ----------- | --------------------------- | ------------------------------------------------- |
| **Ansible** | Arch/CachyOS and other unix | `ansible/roles/hypr` → pacman + AUR + file deploy |

There was a second, nix flake path (NixOS + home-manager modules, a pinned
devShell, `nix flake check` in the gate). It is gone: it was carried as a
first-class path that nothing here actually ran on, so it drifted from the
ansible role it was supposed to mirror and cost a second place to update on
every dependency change. Ansible is the delivery path.

## Scope — the Hyprland ecosystem

In scope (absorbed into this repo, out of chezmoi):

- Compositor + config: `hyprland`, this repo's `hypr/**.lua` and `*.conf`.
- Ecosystem daemons: `hypridle`, `hyprsunset`, `hyprlock`,
  `hyprpolkitagent`, `hyprpicker`, `hyprshot`, `hyprcursor`.
- Wallpaper daemon: `awww` (retired `hyprpaper`, which cannot crossfade).
- Session glue: `uwsm` env (`env-hyprland`), the `hypr*` systemd **user**
  units, portal backends (`xdg-desktop-portal-hyprland` + gtk).
- Greeter fragment tied to the compositor (`dms-hypr.conf`).

Out of scope (stays in chezmoi, `$HOME` dotfiles): waybar, shell, editors,
file managers, and other non-hypr configs. The bar is `quickshell` (separate
repo, part of the running environment — see the store-bridge), not waybar.

Packages are inferred from the ecosystem's own dependencies, not hand-listed.

## Source layout

- `hypr/` — Lua config (the running compositor logic).
- `*.conf` — hypr\* daemon configs (hypridle, hyprlock, hyprsunset, …).
- `assets/`, `icons/`, `wallpapers/` — generated + static assets.
- `session/` — session glue absorbed from chezmoi (uwsm env, systemd user
  units, greeter fragment). Deployed identically by both paths.
- `ansible/` — ansible delivery (role `hypr`, playbook, galaxy meta).
- CI: none in this repo. The workflow was removed in August 2026 and this
  line described one that had not existed since; `just check` is the gate,
  run locally and by the pre-commit hook. The sibling `quickshell` and
  `system-config` repos do run theirs on GitHub.

## Dependency completeness (verified)

- **hypr** — every binary the Lua config / `*.conf` / `bin/` helpers invoke maps to
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
hypridle, hyprsunset, hyprpicker, portal, qt-support, guiutils),
with `libhyprlang/graphics/aquamarine/wire` on subsets. A lib soname bump
(e.g. `libhyprutils.so.13 → .14`) forces **every consumer to be rebuilt**
against it. Consequence: the ecosystem moves as **one atomic unit** — you
cannot run a git compositor against stable daemons. Only `hyprpolkitagent`
(Qt-only) is decoupled.

Two channels:

| Channel  | Packages                                                       |
| -------- | -------------------------------------------------------------- |
| `stable` | official-repo packages (`hypr_core_packages`)                  |
| `git`    | AUR `-git` group in one paru transaction (`hypr_git_packages`) |

**How compatibility is enforced:**

- **Ansible/AUR** — `hyprland-git` _declares the `-git` libs as dependencies_
  (aquamarine-git, hyprutils-git, hyprlang-git, hyprgraphics-git, hyprcursor-git,
  hyprwire-git, hyprland-protocols-git, hyprwayland-scanner-git,
  hyprland-guiutils-git), so paru pulls the whole lib chain and builds it in one
  transaction against a single HEAD. The role only lists the **daemons** as
  `-git` (they link the libs but aren't pulled by the compositor). Update the
  whole group together: `paru -Sua` (devel upgrade). Never `-Syu` a stable lib
  under a git compositor.

Note: on CachyOS the official repos are already very fresh (often ahead of the
AUR `.SRCINFO` snapshots), so `git` mainly buys _unreleased_ commits (e.g. the
`hyprctl binds -j` serializer fix) at the cost of local rebuilds.

## Declarative scenes

Compositor logic executes scene documents; see [docs/scenes.md](docs/scenes.md).
Host `workspace_specs` bind workspace ids and monitors. Geometry profiles stay
fingerprint-based.

A scene covers geometry alone. Which workspaces exist, which binding trees are
loaded and what runs in the background are declared by a **mode**, and this
repo is one of several executors of that declaration — the others being the
shell and the user units. The cross-repo model is `hyprfocus`, documented in
the sibling `system-config` repo.

The scene is registered as a Hyprland layout rather than run as a correction
loop over one: the compositor asks where windows go and the scene answers.
That is what keeps placement independent of which window has focus, and what
removes the need to subscribe to the events that change a layout.

## Package classification (Arch/AUR)

Most `hypr*` packages are in official CachyOS/Arch repos. Genuinely-AUR ones
are tracked separately in the role so an AUR helper (`paru`/`yay`) handles
only those: `grim-hyprland-git`, `catppuccin-sddm-theme-*`, `qt6ct-kde`,
`greetd-dms-greeter-git`. (Note: the old chezmoi `packages.yaml` listed a
stale `greetd-tuigreet-fork-bin` that is not installed — corrected here.)
