# Wspólne środowisko każdego hosta: narzędzia CLI (Nix, agenty, diagnostyka),
# edytor micro, nix-ld dla obcych binarek (uv, pip), /etc/ssl/cert.pem dla
# Pythona z uv, comma z bazą nix-index, direnv i DNS Quad9. Powłoka:
# shell.nix, Nix: nix.nix.
{ inputs, ... }:
{
  flake.modules.nixos.base-configuration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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
          VISUAL = "micro";
          EDITOR = "micro";
        };
        # uv instaluje narzędzia do ~/.local/bin.
        localBinInPath = true;
        # Python z uv (python-build-standalone, np. venv Unsloth Studio) szuka
        # CA w domyślnym pliku OpenSSL /etc/ssl/cert.pem, a NixOS daje tylko
        # /etc/ssl/certs/ca-certificates.crt (bez katalogu z hashami), więc
        # każde HTTPS kończy się CERTIFICATE_VERIFY_FAILED.
        etc."ssl/cert.pem".source = config.security.pki.caBundle;
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
