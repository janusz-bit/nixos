_: {
  flake.nixosModules."nixos/specific" = _: {
    system.stateVersion = "25.11";

    boot.loader.limine.enable = true;
    boot.loader.limine.extraEntries = ''
      /Windows
        protocol: efi
        path: uuid(73694715-1b52-4ef1-a4cb-cb512936cd48):/EFI/Microsoft/Boot/bootmgfw.efi
    '';
    boot.loader.efi.canTouchEfiVariables = true;
  };
}
