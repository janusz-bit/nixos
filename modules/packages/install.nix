{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.install-system = pkgs.writeShellScriptBin "install-system" ''
        #!/usr/bin/env bash
        set -e
        sudo nix run github:nix-community/disko -- --mode disko --flake github:janusz-bit/nixos#nixos
        sudo nixos-install --flake github:janusz-bit/nixos#nixos --no-root-passwd
      '';
    };
}
