{ ... }:
{
  flake.modules.nixos.leds-off = _: {
    # Disable all LEDs on Raspberry Pi 4:
    #   ACT (green, heartbeat), PWR (red, default-on),
    #   mmc0/mmc1 (SD activity), Ethernet amber/green.
    # systemd-tmpfiles runs during sysinit.target, after the LED
    # subsystem has created the /sys/class/leds/ entries.
    systemd.tmpfiles.rules = [
      # ACT - green activity LED on the board
      "w /sys/class/leds/ACT/trigger - - - - none"
      "w /sys/class/leds/ACT/brightness - - - - 0"
      # PWR - red power LED on the board
      "w /sys/class/leds/PWR/trigger - - - - none"
      "w /sys/class/leds/PWR/brightness - - - - 0"
      # mmc0 - SD/eMMC controller LED
      ''w "/sys/class/leds/mmc0::/trigger" - - - - none''
      ''w "/sys/class/leds/mmc0::/brightness" - - - - 0''
      # mmc1 - second MMC controller LED
      ''w "/sys/class/leds/mmc1::/trigger" - - - - none''
      ''w "/sys/class/leds/mmc1::/brightness" - - - - 0''
      # Ethernet amber LED
      ''w "/sys/class/leds/unimac-mdio--19:01:amber:lan/trigger" - - - - none''
      ''w "/sys/class/leds/unimac-mdio--19:01:amber:lan/brightness" - - - - 0''
      # Ethernet green LED
      ''w "/sys/class/leds/unimac-mdio--19:01:green:lan/trigger" - - - - none''
      ''w "/sys/class/leds/unimac-mdio--19:01:green:lan/brightness" - - - - 0''
    ];
  };
}