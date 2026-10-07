{ inputs, ... }:
{
  flake.modules.nixos.rpi-sdImage = {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ];
    sdImage = {
      expandOnBoot = true;
      compressImage = false;
    };
    # firmware.nix z nixos-hardware nadpisuje (mkForce) populateFirmwareCommands
    # z sd-image-aarch64 i kopiuje u-boot.bin oraz wpisuje `kernel=u-boot.bin`
    # do config.txt tylko przy uboot.enable. Bez tego partycja FIRMWARE ma
    # firmware GPU bez jądra, a obraz nie startuje (jądra są w ext4 /boot,
    # extlinux czyta je U-Boot).
    hardware.raspberry-pi.firmware.uboot.enable = true;
    # sd-image-aarch64 włącza hardware.enableAllHardware (m.in. dw-hdmi),
    # a jądra RPi tych modułów nie mają. Tylko obraz — na hoście brak modułu
    # initrd ma przerwać budowę, a nie uruchomienie bez dysku root.
    boot.initrd.allowMissingModules = true;
  };
}
