_: {
  flake.nixosModules."nixos/specific" = _: {
    system.stateVersion = "25.11";

    boot.loader.limine.enable = true;
    boot.loader.limine.extraEntries = ''
      /Windows
        protocol: efi
        path: uuid(1E23-E4A4):/EFI/Microsoft/Boot/bootmgfw.efi
    '';
    boot.loader.efi.canTouchEfiVariables = true;
  };
}
