{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      text = ''
        sudo nix run github:nix-community/disko  --experimental-features 'nix-command flakes' -- --mode destroy,format,mount --flake github:janusz-bit/nixos#nixos
        sudo nixos-install --flake github:janusz-bit/nixos#nixos --no-root-passwd
      '';
    in
    {
      packages.install-system = pkgs.writeShellScriptBin "install-system" ''
        #!/usr/bin/env bash
        set -e
        echo "${text}"
      '';
    };
}
