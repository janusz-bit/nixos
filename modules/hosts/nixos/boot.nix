# Rozruch laptopa: Limine podpisany własnymi kluczami Secure Boot (sbctl) i
# wpis Windows z drugiego dysku NVMe. Firmware Insyde ukrywa zmienne EFI
# przed Linuksem, więc stan Secure Boot i wpisywanie kluczy opisuje AGENTS.md
# (`post-install secure-boot`).
#
# Sprawdzenie: `journalctl -k -b | grep -i "secure boot"`.
_: {
  flake.modules.nixos.nixos-boot =
    { pkgs, ... }:
    {
      boot.loader = {
        limine = {
          enable = true;
          # Podpis kluczami sbctl (/var/lib/sbctl/keys) i suma kontrolna
          # konfiguracji wbudowana w binarkę.
          secureBoot = {
            enable = true;
            # Świeża instalacja nie ma /var/lib/sbctl, a bez kluczy limine-install
            # przerwałby nixos-install. Klucze powstają lokalnie (firmware
            # nietknięty; do ich wpisania Secure Boot w BIOS musi być wyłączony),
            # istniejących nie rusza.
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
