{ ... }:
{
  flake.nixosModules."raspberry-pi-4/configuration" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      networking.hostName = "raspberry-pi-4";

      # Fix for missing dw-hdmi module on RPi4 generic image
      boot.initrd.allowMissingModules = true;

      # Storage & RAM optimizations (SD card protection)
      zramSwap.enable = true;
      boot.tmp.useTmpfs = true;
      boot.tmp.tmpfsSize = "50%"; # Allow tmpfs to use up to half of RAM

      # CPU Performance optimization
      powerManagement.cpuFreqGovernor = "ondemand";
      nix.settings.max-jobs = 2;

      # Network configuration
      networking.networkmanager.enable = true;
      time.timeZone = "Europe/Warsaw";

      # User configuration
      users.users.${config.custom.defaultUser} = {
        initialPassword = "${config.custom.defaultUser}";
        isNormalUser = true;
        description = "${config.custom.defaultUser}";
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
      };

      environment.systemPackages = with pkgs; [
        micro
        wget
        htop # Added for monitoring
      ];

      services.openssh.enable = true;
    };
}
