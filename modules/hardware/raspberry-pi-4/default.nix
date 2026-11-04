# Płytka Raspberry Pi 4B: profil nixos-hardware (device tree, nakładki),
# kernel producenta z gotowego cache nixos-raspberrypi, wyłączone diody,
# governor CPU. Wentylator na GPIO: fan.nix.
#
# Kernel nadpisuje mkDefault z nixos-hardware: tamten buduje się nixpkgs-em
# hosta, więc każdy bump nixpkgs to nowa kompilacja (godziny na RPi, w CI
# runner ARM padał w trakcie). nixos-raspberrypi buduje go własnym nixpkgs
# i trzyma w swoim cache. Sprawdzenie, że kernel jest w cache (200):
#   curl -sI https://nixos-raspberrypi.cachix.org/$(nix eval --raw .#nixosConfigurations.raspberry-pi-4.config.boot.kernelPackages.kernel.outPath | cut -d/ -f4 | cut -d- -f1).narinfo
#
# Ustawień firmware (config.txt na partycji FIRMWARE) ten flake nie
# zarządza; zmienia się je ręcznie:
#   sudo mount /dev/disk/by-label/FIRMWARE /mnt
#   sudo micro /mnt/config.txt   # np. dtparam=audio=on
{ inputs, ... }:
{
  flake.modules.nixos.hardware-raspberry-pi-4 = _: {
    imports = [ inputs.nixos-hardware.nixosModules.raspberry-pi-4 ];

    boot.kernelPackages = inputs.nixos-raspberrypi.packages.aarch64-linux.linuxPackages_rpi4;

    # Tymczasowe (temporary-fixes.md nr 14): kernel z nixpkgs 26.05 nie ma
    # passthru target i buildDTBs, z których te opcje biorą wartości domyślne.
    system.boot.loader.kernelFile = "Image";
    hardware.deviceTree.enable = true;

    # Bez tego budowa initrd pada na brakującym module dw-hdmi (generyczny
    # obraz RPi4).
    boot.initrd.allowMissingModules = true;

    powerManagement.cpuFreqGovernor = "ondemand";

    # Diody ACT, PWR i Ethernet (PHY przy RJ45, poza /sys/class/leds) gaszą
    # nakładki device tree z nixos-hardware.
    hardware.raspberry-pi."4".leds = {
      eth.disable = true;
      act.disable = true;
      pwr.disable = true;
    };

    # Diody, których nixos-hardware nie obejmuje: aktywność karty SD (mmc0,
    # alternatywna nazwa mmc0::) i resztkowa default-on.
    systemd.tmpfiles.rules = [
      ''w "/sys/class/leds/mmc0/trigger" - - - - none''
      ''w "/sys/class/leds/mmc0/brightness" - - - - 0''
      ''w "/sys/class/leds/mmc0::/trigger" - - - - none''
      ''w "/sys/class/leds/mmc0::/brightness" - - - - 0''
      ''w "/sys/class/leds/default-on/trigger" - - - - none''
      ''w "/sys/class/leds/default-on/brightness" - - - - 0''
    ];
  };
}
