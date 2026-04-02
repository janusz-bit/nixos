{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      text = ''
        sudo nix run github:nix-community/disko  --experimental-features 'nix-command flakes' -- --mode destroy,format,mount --flake github:janusz-bit/nixos#nixos
        sudo nixos-install --flake github:janusz-bit/nixos#nixos --no-root-passwd --option extra-substituters "https://attic.xuyh0120.win/lantian https://janusz-bit.cachix.org" --option  extra-trusted-public-keys "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc= janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo="
      '';
    in
    {
      packages.install-system = pkgs.writeShellScriptBin "install-system" ''
        #!/usr/bin/env bash
        set -e
        ${text}
      '';
    };
}
