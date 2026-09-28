_: {
  flake.modules.nixos.nixos-specific = _: {
    system.stateVersion = "25.11";

    boot.loader = {
      limine = {
        enable = true;
        # Podpis limine kluczami sbctl (/var/lib/sbctl/keys) + suma kontrolna
        # konfiguracji wbudowana w binarkę. Sam podpis niczego nie wymusza —
        # ochronę daje dopiero Secure Boot włączony w firmware po
        # `sudo sbctl enroll-keys -m` (-m = klucze Microsoftu, potrzebne
        # dla Windowsa i opcjonalnych ROM-ów GPU).
        secureBoot.enable = true;
        extraEntries = ''
          /Windows
            protocol: efi
            path: uuid(73694715-1b52-4ef1-a4cb-cb512936cd48):/EFI/Microsoft/Boot/bootmgfw.efi
        '';
      };
      efi.canTouchEfiVariables = true;
    };
  };
}
