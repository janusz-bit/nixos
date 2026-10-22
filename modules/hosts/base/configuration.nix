# Wspólne środowisko każdego hosta: narzędzia CLI (Nix, agenty, diagnostyka),
# edytor micro, nix-ld dla obcych binarek (uv, pip), comma z bazą
# nix-index, direnv i DNS Quad9. Powłoka: shell.nix, Nix: nix.nix.
{ inputs, ... }:
{
  flake.modules.nixos.base-configuration =
    { lib, pkgs, ... }:
    let
      editor = "micro";
    in
    {
      imports = [ inputs.nix-index-database.nixosModules.default ];

      # mkDefault: na WSL resolv.conf generuje Windows (modules/hosts/wsl/default.nix).
      networking.nameservers = lib.mkDefault [
        "9.9.9.9"
        "149.112.112.112"
        "2620:fe::fe"
        "2620:fe::9"
      ];

      environment = {
        systemPackages = with pkgs; [
          micro-full
          nil
          nixd
          nixfmt-tree
          uv
          statix
          cachix
          inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
          nix-update
          tlrc
          fzf
          hw-probe
          htop
          vulnix
        ];
        sessionVariables = {
          NIXOS_OZONE_WL = "1";
          VISUAL = editor;
          EDITOR = editor;
        };
        # uv instaluje narzędzia do ~/.local/bin.
        localBinInPath = true;
      };

      programs = {
        # Prekompilowane binarki (uv, pip, pobrane programy) bez patchelf.
        nix-ld.enable = true;
        nix-index-database.comma.enable = true;
        direnv.enable = true;
      };

      # Moduł ZFS jest w nixpkgs importowany zawsze, a przy stateVersion < 26.11
      # domyślne true daje ostrzeżenie ewaluacji (wymuszony import puli omija
      # zabezpieczenia ZFS).
      boot.zfs.forceImportRoot = false;
    };
}
