_:
{
  flake.nixosModules.nixos-specific =
    _:
    {
      system.stateVersion = "25.11";
      boot.initrd.luks.devices."luks-ebb6d9c8-350c-4291-a8bd-74ec17ab4a67".device =
        "/dev/disk/by-uuid/ebb6d9c8-350c-4291-a8bd-74ec17ab4a67";

      boot.loader.limine.enable = true;
      boot.loader.limine.extraEntries = ''
        /Windows
          protocol: efi
          path: uuid(5257c7fd-64d0-42ca-9ee0-0c77f7c0e2db):/EFI/Microsoft/Boot/bootmgfw.efi
      '';
      boot.loader.efi.canTouchEfiVariables = true;
    };
}
