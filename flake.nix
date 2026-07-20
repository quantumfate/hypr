{
  description = "Development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Repo tooling (formatters, hooks, linters) for editing the Lua config.
        devTools = with pkgs; [
          git
          just
          pre-commit
          stylua
          luajit
          lua-language-server
          luarocks
          luaPackages.luacheck
          shfmt
          shellcheck
          yamllint
          prettier
          nixpkgs-fmt
        ];

        # Runtime dependencies the config binds/scripts shell out to, so a
        # `nix develop` shell can drive it. Mirrors the ansible role
        # (ansible/roles/hypr). Package names track the binaries scanned from
        # hypr/**.lua, *.conf and scripts/*.sh.
        runtimeDeps = with pkgs; [
          # --- compositor + hypr* ecosystem (own .conf files in this repo) ---
          hyprland # the compositor
          hypridle # hypridle.conf
          hyprlock # hyprlock.conf / hyprlock-laptop.conf
          hyprpaper # hyprpaper.conf
          hyprsunset # hyprsunset.conf
          hyprpicker # color pick binds
          hyprshot # screenshot binds (,hyprshot.sh)
          xdg-desktop-portal-hyprland # portal backend
          xdg-desktop-portal-gtk # portal (file pickers)
          # --- shell / launcher / session ---
          quickshell # the bar (autostarted: `uwsm app -- qs -c quantumfate`)
          uwsm # session-scoped app launches
          rofi # menus (rofi-wayland was merged into rofi in nixpkgs)
          kitty # terminal
          foot # terminal (alttab preview)
          # --- tools invoked from binds / lua / scripts ---
          xdotool # window poke / click-repeat helpers
          brightnessctl # brightness binds
          gamemode # gamemoderun (Dofus launch)
          satty # screenshot annotate
          grim # screenshot capture
          jq # JSON parsing in lua/scripts
          libnotify # notify-send (fallback path)
          procps # pgrep / pkill
          xorg.setxkbmap # keyboard layout (setxkbmap dvorak-custom)
          inetutils # hostname (per-host config selection)
          # Not declared (host/proprietary, install per-host):
          #   ankama-launcher (AUR) — `gamemoderun ankama-launcher`
          #   nvidia driver, hyprqt6engine (hyprqt6engine.conf) — host Qt theming
          #   dofus_swap.py — provided by the quickshell repo's scripts/bin on PATH
          #   ~/.config/waybar/scripts/*, ,brightness.sh, ,hyprshot.sh — user scripts
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = devTools ++ runtimeDeps;
          # Wire the repo into git on shell entry.
          shellHook = ''
            command -v pre-commit >/dev/null && \
              pre-commit install --hook-type pre-commit --hook-type commit-msg 2>/dev/null || true
          '';
        };
      });
}
