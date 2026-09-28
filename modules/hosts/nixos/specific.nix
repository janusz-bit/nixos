_: {
  flake.modules.nixos.nixos-specific = _: {
    system.stateVersion = "25.11";

    boot.loader = {
      limine = {
        enable = true;
        # Podpis limine kluczami sbctl (/var/lib/sbctl/keys) + suma kontrolna
        # konfiguracji wbudowana w binarkę. Secure Boot jest włączony w
        # firmware z własnymi kluczami. Firmware Insyde ukrywa zmienne EFI
        # przed Linuksem, więc `sbctl enroll-keys` nie działa — procedura
        # (export .auth + efi-updatevar, odtworzenie dbx) jest w AGENTS.md.
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
