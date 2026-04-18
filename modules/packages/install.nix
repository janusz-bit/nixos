{ inputs, custom, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      text = ''
        sudo ${lib.getExe pkgs.disko} --mode destroy,format,mount --flake ${custom.repository.linkFlake}#nixos
        sudo mkdir -p /mnt/etc/nixos
        sudo ${pkgs.git}/bin/git clone ${custom.repository.url} /mnt/etc/nixos
        sudo ${pkgs.nixos-install-tools}/bin/nixos-install --flake /mnt/etc/nixos#nixos --no-root-passwd --accept-flake-config
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
