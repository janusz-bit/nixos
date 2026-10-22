# Sprzęt dysku RPi z nixos-generate-config: moduły initrd dla SSD po USB
# i system plików. Platformę ustawia rejestr hostów; obraz SD (sd-image.nix)
# tego pliku nie importuje.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "uas"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
    fsType = "ext4";
  };
}
