# Płytka Raspberry Pi 4B: profil nixos-hardware (kernel producenta,
# device tree), wyłączone diody, governor CPU. Wentylator na GPIO: fan.nix.
#
# Ustawień firmware (config.txt na partycji FIRMWARE) ten flake nie
# zarządza; zmienia się je ręcznie:
#   sudo mount /dev/disk/by-label/FIRMWARE /mnt
#   sudo micro /mnt/config.txt   # np. dtparam=audio=on
# Nakładki device tree (diody niżej) idą przez nixos-hardware.
{ inputs, ... }:
{
  flake.modules.nixos.hardware-raspberry-pi-4 = {
    imports = [ inputs.nixos-hardware.nixosModules.raspberry-pi-4 ];

    # Fix for missing dw-hdmi module on RPi4 generic image
    boot.initrd.allowMissingModules = true;

    powerManagement.cpuFreqGovernor = "ondemand";

    # Disable all LEDs on Raspberry Pi 4.
    # ACT, PWR, and Ethernet LEDs are controlled via device tree overlays
    # using the nixos-hardware raspberry-pi/4/leds.nix module.
    # Ethernet PHY LEDs (amber/green on RJ45 port) are NOT in /sys/class/leds/
    # — they require a DT overlay setting led-modes = <0x04 0x04> (Off).
    hardware.raspberry-pi."4".leds = {
      eth.disable = true; # Ethernet amber + green LEDs via DT overlay
      act.disable = true; # Green ACT LED via DT overlay
      pwr.disable = true; # Red PWR LED via DT overlay
    };

    # Remaining LEDs (mmc0 SD activity, default-on) are not covered by
    # nixos-hardware — disable them via systemd-tmpfiles.
    systemd.tmpfiles.rules = [
      # mmc0 - SD controller activity LED
      ''w "/sys/class/leds/mmc0/trigger" - - - - none''
      ''w "/sys/class/leds/mmc0/brightness" - - - - 0''
      # mmc0:: - SD/eMMC controller LED (alternative name)
      ''w "/sys/class/leds/mmc0::/trigger" - - - - none''
      ''w "/sys/class/leds/mmc0::/brightness" - - - - 0''
      # default-on - residual default-on LED
      ''w "/sys/class/leds/default-on/trigger" - - - - none''
      ''w "/sys/class/leds/default-on/brightness" - - - - 0''
    ];
  };
}
