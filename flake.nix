{
  description = "quantumfate Hyprland environment — dual delivery (nix modules + devShell)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    hyprland.url = "github:hyprwm/Hyprland";

    hypridle.url = "github:hyprwm/hypridle";
    hypridle.inputs.nixpkgs.follows = "nixpkgs";
    hypridle.inputs.hyprlang.follows = "hyprland/hyprlang";
    hypridle.inputs.hyprutils.follows = "hyprland/hyprutils";

    hyprlock.url = "github:hyprwm/hyprlock";
    hyprlock.inputs.nixpkgs.follows = "nixpkgs";
    hyprlock.inputs.hyprlang.follows = "hyprland/hyprlang";
    hyprlock.inputs.hyprutils.follows = "hyprland/hyprutils";
    hyprlock.inputs.hyprgraphics.follows = "hyprland/hyprgraphics";

    hyprpaper.url = "github:hyprwm/hyprpaper";
    hyprpaper.inputs.nixpkgs.follows = "nixpkgs";
    hyprpaper.inputs.hyprlang.follows = "hyprland/hyprlang";
    hyprpaper.inputs.hyprutils.follows = "hyprland/hyprutils";
    hyprpaper.inputs.hyprgraphics.follows = "hyprland/hyprgraphics";

    hyprsunset.url = "github:hyprwm/hyprsunset";
    hyprsunset.inputs.nixpkgs.follows = "nixpkgs";
    hyprsunset.inputs.hyprlang.follows = "hyprland/hyprlang";
    hyprsunset.inputs.hyprutils.follows = "hyprland/hyprutils";

    hyprpicker.url = "github:hyprwm/hyprpicker";
    hyprpicker.inputs.nixpkgs.follows = "nixpkgs";
    hyprpicker.inputs.hyprutils.follows = "hyprland/hyprutils";

    xdph.url = "github:hyprwm/xdg-desktop-portal-hyprland";
    xdph.inputs.nixpkgs.follows = "nixpkgs";
    xdph.inputs.hyprland-protocols.follows = "hyprland/hyprland-protocols";
    xdph.inputs.hyprlang.follows = "hyprland/hyprlang";
    xdph.inputs.hyprutils.follows = "hyprland/hyprutils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , hyprland
    , hypridle
    , hyprlock
    , hyprpaper
    , hyprsunset
    , hyprpicker
    , xdph
    }:
    let
      runtimeDeps = pkgs: with pkgs; [
        pkgs.hyprland
        pkgs.hypridle
        pkgs.hyprlock
        pkgs.hyprpaper
        pkgs.hyprsunset
        pkgs.hyprpicker
        hyprpolkitagent
        hyprcursor
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        quickshell
        uwsm
        rofi
        kitty
        foot
        xdotool
        brightnessctl
        gamemode
        satty
        grim
        jq
        libnotify
        procps
        xorg.setxkbmap
        inetutils
      ];

      hyprGitOverlay = final: prev: {
        hyprland = hyprland.packages.${prev.system}.hyprland;
        hypridle = hypridle.packages.${prev.system}.hypridle;
        hyprlock = hyprlock.packages.${prev.system}.hyprlock;
        hyprpaper = hyprpaper.packages.${prev.system}.hyprpaper;
        hyprsunset = hyprsunset.packages.${prev.system}.hyprsunset;
        hyprpicker = hyprpicker.packages.${prev.system}.hyprpicker;
        xdg-desktop-portal-hyprland = xdph.packages.${prev.system}.xdg-desktop-portal-hyprland;
      };
    in
    {
      overlays.hyprGit = hyprGitOverlay;

      # NixOS module — system scope: Hyprland, portals, ecosystem packages, and
      # the release channel (stable = nixpkgs, git = the pinned flake set).
      nixosModules.hypr = { config, lib, pkgs, ... }:
        let cfg = config.programs.hyprEnvironment;
        in {
          options.programs.hyprEnvironment = {
            enable = lib.mkEnableOption "the quantumfate Hyprland environment (system scope)";
            channel = lib.mkOption {
              type = lib.types.enum [ "stable" "git" ];
              default = "stable";
              description = "stable = nixpkgs; git = the coupled hypr* flake set (soname-unified via follows).";
            };
          };

          config = lib.mkIf cfg.enable {
            # git channel swaps the whole coupled set at once via the overlay.
            nixpkgs.overlays = lib.mkIf (cfg.channel == "git") [ hyprGitOverlay ];
            programs.hyprland = {
              enable = true;
              package = pkgs.hyprland; # follows the overlay on the git channel
            };
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
                  [
                    "export GBM_BACKEND"
                    "export __GLX_VENDOR_LIBRARY_NAME"
                    "export LIBVA_DRIVER_NAME"
                    "export NVD_BACKEND"
                  ]
                  [
                    "# export GBM_BACKEND"
                    "# export __GLX_VENDOR_LIBRARY_NAME"
                    "# export LIBVA_DRIVER_NAME"
                    "# export NVD_BACKEND"
                  ]
                  raw;
              in
              if cfg.gpu == "nvidia" then raw else nvidiaGated;

            xdg.configFile."systemd/user/hypridle.service".source =
              self + "/session/systemd/hypridle.service";
            xdg.configFile."systemd/user/hyprpaper.service".source =
              self + "/session/systemd/hyprpaper.service";
          };
        };
    }
    // flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
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
        ansible
        ansible-lint
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
