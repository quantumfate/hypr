{
  description = "quantumfate Hyprland environment — dual delivery (nix modules + devShell)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # === Ecosystem package set, shared by the nixos module and the devShell ===
      # Mirrors ansible/roles/hypr defaults. Package names track the binaries
      # scanned from hypr/**.lua, *.conf and scripts/*.sh.
      runtimeDeps = pkgs: with pkgs; [
        # compositor + hypr* ecosystem (own .conf files in this repo)
        hyprland hypridle hyprlock hyprpaper hyprsunset hyprpicker hyprshot
        hyprpolkitagent hyprcursor
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        # shell / launcher / session
        quickshell uwsm rofi kitty foot
        # tools invoked from binds / lua / scripts
        xdotool brightnessctl gamemode satty grim jq libnotify procps
        xorg.setxkbmap inetutils
        # Not declared (host/proprietary): ankama-launcher, nvidia driver,
        # hyprqt6engine — install per-host.
      ];
    in
    # System-agnostic outputs: modules other flakes/NixOS/home-manager import.
    {
      # NixOS module — system scope: enable Hyprland, portals, ecosystem pkgs.
      nixosModules.hypr = { config, lib, pkgs, ... }:
        let cfg = config.programs.hyprEnvironment;
        in {
          options.programs.hyprEnvironment.enable =
            lib.mkEnableOption "the quantumfate Hyprland environment (system scope)";

          config = lib.mkIf cfg.enable {
            programs.hyprland.enable = true;               # compositor + session
            xdg.portal = {
              enable = true;
              extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
            };
            environment.systemPackages = runtimeDeps pkgs;
          };
        };

      # home-manager module — user scope: deploy the config dir + session glue.
      homeManagerModules.hypr = { config, lib, pkgs, ... }:
        let cfg = config.programs.hyprEnvironment;
        in {
          options.programs.hyprEnvironment = {
            enable = lib.mkEnableOption "deploy the quantumfate Hyprland config";
            gpu = lib.mkOption {
              type = lib.types.enum [ "nvidia" "other" ];
              default = "other";
              description = "Keep the NVIDIA env block in uwsm/env-hyprland.";
            };
          };

          config = lib.mkIf cfg.enable {
            # The repo root IS ~/.config/hypr (same as the ansible symlink).
            xdg.configFile."hypr".source = self;

            # uwsm env: strip the NVIDIA block on non-nvidia hosts.
            xdg.configFile."uwsm/env-hyprland".text =
              let
                raw = builtins.readFile (self + "/session/uwsm/env-hyprland");
                nvidiaGated = builtins.replaceStrings
                  [ "export GBM_BACKEND" "export __GLX_VENDOR_LIBRARY_NAME"
                    "export LIBVA_DRIVER_NAME" "export NVD_BACKEND" ]
                  [ "# export GBM_BACKEND" "# export __GLX_VENDOR_LIBRARY_NAME"
                    "# export LIBVA_DRIVER_NAME" "# export NVD_BACKEND" ]
                  raw;
              in
              if cfg.gpu == "nvidia" then raw else nvidiaGated;

            # Custom hypr* user units, deployed as raw files (bound to the
            # hyprland session target). Packaged hyprsunset/hyprpolkitagent units
            # are enabled at system scope, not managed here.
            xdg.configFile."systemd/user/hypridle.service".source =
              self + "/session/systemd/hypridle.service";
            xdg.configFile."systemd/user/hyprpaper.service".source =
              self + "/session/systemd/hyprpaper.service";
          };
        };
    }
    # Per-system outputs: the dev / CI shell.
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Repo tooling for editing + CI (formatters, linters, ansible checks).
        devTools = with pkgs; [
          git just pre-commit
          stylua luajit lua-language-server luarocks luaPackages.luacheck
          shfmt shellcheck yamllint prettier nixpkgs-fmt
          ansible ansible-lint
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = devTools ++ runtimeDeps pkgs;
          shellHook = ''
            command -v pre-commit >/dev/null && \
              pre-commit install --hook-type pre-commit --hook-type commit-msg 2>/dev/null || true
          '';
        };
      });
}
