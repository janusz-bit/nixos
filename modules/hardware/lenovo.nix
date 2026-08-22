_: {
  flake.modules.nixos.hardware-lenovo = _: {
    boot.kernelModules = [ "ideapad_laptop" ];

    services = {
      # Proaktywny demon zarządzania termicznego procesorów Intel
      thermald.enable = true;

      # Zarządzanie profilami zasilania (KDE Plasma 6 / platform_profile)
      power-profiles-daemon.enable = true;

      # Konfiguracja upower
      upower = {
        enable = true;
        percentageLow = 15;
        percentageCritical = 5;
        percentageAction = 3;
      };
    };

    # Domyślne włączenie trybu ochrony baterii (80%) przy starcie systemu
    systemd.tmpfiles.rules = [
      "w- /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode - - - - 1"
    ];
  };
}
