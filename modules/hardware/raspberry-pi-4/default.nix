# Płytka Raspberry Pi 4B: profil nixos-hardware (kernel producenta,
# device tree), wyłączone diody, governor CPU. Wentylator na GPIO: fan.nix.
#
# Ustawień firmware (config.txt na partycji FIRMWARE) ten flake nie
# zarządza; zmienia się je ręcznie:
#   sudo mount /dev/disk/by-label/FIRMWARE /mnt
#   sudo micro /mnt/config.txt   # np. dtparam=audio=on
{ inputs, ... }:
{
  flake.modules.nixos.hardware-raspberry-pi-4 = {
    imports = [ inputs.nixos-hardware.nixosModules.raspberry-pi-4 ];

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
