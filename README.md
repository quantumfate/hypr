# Hypr

This configuration encompasses the common options between my machines.
The gaps are filled by my [dotfiles](https://codeberg.org/quantumfate/dotfiles) and some private sources.

Window placement is a scene document executed by engines — [docs/scenes.md](docs/scenes.md). Agent/CI notes: [AGENTS.md](AGENTS.md).

- Colorscheme: [Catppuccin](https://catppuccin.com/)

![hypr](./assets/rice.png)

## Install

### Ansible

See [Ansible](./ansible/)

### Nix (NixOS / nix-managed hosts)

Import `nixosModules.hypr` (system) and `homeManagerModules.hypr`
(home-manager) from this flake, then:

```nix
programs.hyprEnvironment.enable = true;
programs.hyprEnvironment.channel = "git";   # optional: rolling flake set (default "stable")
programs.hyprEnvironment.gpu = "nvidia";    # home module: keep the NVIDIA env block
```
