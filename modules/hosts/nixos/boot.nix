# Rozruch laptopa: Limine podpisany własnymi kluczami Secure Boot (sbctl) i
# wpis Windows z drugiego dysku NVMe. Firmware Insyde ukrywa zmienne EFI
# przed Linuksem (sbctl status, bootctl i efibootmgr pokazują bzdury), więc
# stan czyta się z logu kernela albo dziennika TPM (AGENTS.md), a klucze
# wpisuje `nix run /etc/nixos#post-install secure-boot`. Z tego samego
# powodu limine-install odtwarza swój wpis NVRAM przy każdym rebuildzie.
# Sprawdzenie: `journalctl -k -b | grep -i "secure boot"`.
_: {
  flake.modules.nixos.nixos-boot =
    { pkgs, ... }:
    {
      boot.loader = {
        limine = {
          enable = true;
          # Podpis limine kluczami sbctl (/var/lib/sbctl/keys) + suma kontrolna
          # konfiguracji wbudowana w binarkę. Secure Boot jest włączony w
          # firmware z własnymi kluczami.
          secureBoot = {
            enable = true;
            # Świeża instalacja (install-system) nie ma /var/lib/sbctl — bez tego
            # limine-install przerwałby nixos-install. Klucze powstają lokalnie,
            # firmware zostaje nietknięty: do wpisania ich (post-install)
            # Secure Boot w BIOS musi być wyłączony. Istniejących kluczy nie rusza.
            autoGenerateKeys = true;
          };
          extraEntries = ''
            /Windows
              protocol: efi
              path: uuid(73694715-1b52-4ef1-a4cb-cb512936cd48):/EFI/Microsoft/Boot/bootmgfw.efi
          '';
        };
        efi.canTouchEfiVariables = true;
      };

      environment.systemPackages = [ pkgs.sbctl ];
    };
}
