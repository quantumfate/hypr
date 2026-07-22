# Hypr

This configuration encompasses the common options between my machines.
The gaps are filled by my [dotfiles](https://github.com/quantumfate/dotfiles) and some private sources.

- Colorscheme: [Catppuccin](https://catppuccin.com/)

![hypr](./assets/rice.png)

## Deploy

Non-nix host (Arch/CachyOS), from the repo root:

```sh
ansible-galaxy collection install -r ansible/requirements.yml   # once
ansible-playbook ansible/playbook.yml --ask-become-pass
```

Add `-e hypr_install_aur_packages=true` to also install the AUR set
(`grim-hyprland-git`, `qt6ct-kde`, `greetd-dms-greeter-git`,
`catppuccin-sddm-theme-*`) via your AUR helper.

Ride the rolling **git** channel (whole hypr\* ecosystem from AUR `-git`, built
as one coupled group) with `-e hypr_channel=git`. See the compatibility model
in [ARCHITECTURE.md](./ARCHITECTURE.md); update the group with `paru -Sua`.

Nix host: import `nixosModules.hypr` (system) and `homeManagerModules.hypr`
(home-manager) from this flake and set `programs.hyprEnvironment.enable = true`.

---

## Details

### Delivery model

Dual, full, equal delivery of the whole Hyprland _environment_ (compositor
config + the `hypr*` ecosystem session glue). See [ARCHITECTURE.md](./ARCHITECTURE.md)
and the phased [MIGRATION.md](./MIGRATION.md).

| Path        | Target machines                | Installs + deploys via              |
| ----------- | ------------------------------ | ----------------------------------- |
| **Ansible** | Arch/CachyOS and other non-nix | `ansible/roles/hypr` (pacman + AUR) |
| **Nix**     | NixOS / nix-managed hosts      | `flake.nix` nix modules             |

### Ansible path — knobs

Override role vars with `-e` or a group_vars file:

| Var                         | Default   | Effect                                            |
| --------------------------- | --------- | ------------------------------------------------- |
| `hypr_install_packages`     | `true`    | Install the official-repo ecosystem set.          |
| `hypr_install_aur_packages` | `false`   | Install `hypr_aur_packages` via a helper.         |
| `hypr_aur_helper`           | `paru`    | AUR helper (`paru`/`yay`).                        |
| `hypr_deploy_session`       | `true`    | Deploy `session/**` + enable user units.          |
| `hypr_gpu`                  | `nvidia`  | `nvidia` keeps the GPU env block; else strips it. |
| `hypr_repo_path`            | this repo | Checkout path when run from a controller.         |

The role installs the ecosystem, symlinks this repo to `~/.config/hypr` (skipped
when you already edit in place), deploys the session glue
([`session/`](./session/README.md)), and enables the `hypr*` user units.

### Nix path

`nixosModules.hypr` enables `programs.hyprland`, the xdg portals, and the
ecosystem packages. `homeManagerModules.hypr` deploys the repo as
`~/.config/hypr`, the uwsm env (NVIDIA block gated by a `gpu` option), and the
custom `hypridle`/`hyprpaper` user units. `nix develop` gives the dev/CI shell.

### CI

Validate-only: `just check-all` (fmt + lua/shell/yaml lint + ansible
syntax/lint) and `nix flake check`. No Galaxy/cachix publishing yet.
