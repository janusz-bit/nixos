{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      text = ''
        sudo ${lib.getExe pkgs.disko} --mode destroy,format,mount --flake ${config.customTop.repository.linkFlake}#nixos
        sudo mkdir -p /mnt/etc/nixos
        sudo ${pkgs.git}/bin/git clone ${config.customTop.repository.url} /mnt/etc/nixos
        sudo ${pkgs.nixos-install-tools}/bin/nixos-install --flake /mnt/etc/nixos#nixos --no-root-passwd
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
