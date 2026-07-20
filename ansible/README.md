# hypr — Ansible deployment

Installs the runtime packages this Hyprland config shells out to and links the
config into place. Mirrors the sibling [`quickshell`](https://github.com/quantumfate/quickshell)
role — deploy both for the full desktop.

## Deploy locally

```sh
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbook.yml --ask-become-pass
```

## What it does

- Installs `hypr_packages` (compositor + `hypr*` ecosystem, terminals, menu,
  and the tools binds/scripts call — see `roles/hypr/defaults/main.yml`).
- Symlinks the checkout to `~/.config/hypr` (skipped when you edit in place).
- Seeds the shared Dofus state dir (`$XDG_STATE_HOME/dofus`).

## Not installed here

AUR / proprietary / per-host bits the config touches but can't come from the
official repos — install yourself:

- `ankama-launcher` (Dofus), the NVIDIA driver, `hyprqt6engine` (Qt theming).
- User scripts on `PATH` (`,hyprshot.sh`, `,brightness.sh`, `dofus_swap.py`).

Set `hypr_install_extra_packages: true` (with an AUR helper configured) to let
the role attempt `hypr_extra_packages`.
