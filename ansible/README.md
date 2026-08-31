# hypr — Ansible deployment

Installs the runtime packages this Hyprland config shells out to and links the
config.

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
