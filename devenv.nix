{ pkgs, ... }:

{
  languages.lua.enable = true;

  packages = with pkgs; [
    just
    pre-commit
    stylua
    shfmt
    shellcheck
    yamllint
    prettier
  ];

  # Install the shared pre-commit hooks on shell entry.
  enterShell = ''
    pre-commit install --hook-type pre-commit --hook-type commit-msg 2>/dev/null || true
  '';
}
