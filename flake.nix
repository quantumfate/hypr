{
  description = "Development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
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
          # Wire the repo into git on shell entry.
          shellHook = ''
            command -v pre-commit >/dev/null && \
              pre-commit install --hook-type pre-commit --hook-type commit-msg 2>/dev/null || true
          '';
        };
      });
}
