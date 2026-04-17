_: {
  flake.nixosModules."nixos/specific" = _: {
    system.stateVersion = "25.11";

    boot.loader.limine.enable = true;
    boot.loader.limine.extraEntries = ''
      /Windows
        protocol: efi
        path: uuid(5257c7fd-64d0-42ca-9ee0-0c77f7c0e2db):/EFI/Microsoft/Boot/bootmgfw.efi
    '';
    boot.loader.efi.canTouchEfiVariables = true;
  };
}
