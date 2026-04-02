{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      text = ''
        sudo nix run github:nix-community/disko  --experimental-features 'nix-command flakes' -- --mode destroy,format,mount --flake github:janusz-bit/nixos#nixos
        sudo nixos-install --flake github:janusz-bit/nixos#nixos --no-root-passwd --option extra-substituters "https://attic.xuyh0120.win/lantian" --option  extra-trusted-public-keys "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
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
