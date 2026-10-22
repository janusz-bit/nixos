# Dodatki dla laptopów Lenovo (IdeaPad/LOQ): sterownik ideapad_laptop,
# thermald, power-profiles-daemon (profile zasilania w Plasmie przez
# platform_profile), progi baterii upower i tryb ochrony baterii przy starcie.
#
# Sprawdzenie: `cat /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode`
# (1), `powerprofilesctl list`, `upower -d`.
_: {
  flake.modules.nixos.hardware-lenovo = _: {
    boot.kernelModules = [ "ideapad_laptop" ];

    services = {
      thermald.enable = true;
      power-profiles-daemon.enable = true;
      upower = {
        enable = true;
        percentageLow = 15;
        percentageCritical = 5;
        percentageAction = 3;
      };
    };

    # Tryb ochrony baterii (ładowanie do 80%); `w-`: nieudany zapis nie kończy
    # systemd-tmpfiles błędem.
    systemd.tmpfiles.rules = [
      "w- /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode - - - - 1"
    ];
  };
}
