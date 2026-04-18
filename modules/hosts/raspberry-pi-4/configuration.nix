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

      # Security hardening
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        settings.KbdInteractiveAuthentication = false;
      };

      # Logging optimization (SD card protection)
      services.journald.extraConfig = ''
        SystemMaxUse=250M
        MaxFileSec=1month
      '';

      # Headless optimization
      # Reduce GPU memory to 16MB for a headless server
      # hardware.raspberry-pi.config.all.options.gpu_mem = { value = 16; }; # For older nixos-hardware
      # boot.loader.raspberryPi.firmwareConfig = "gpu_mem=16"; # For generic raspberry pi images

      # Fail2ban security
      services.fail2ban = {
        enable = true;
        maxretry = 5;
        ignoreIP = [
          "127.0.0.1/8"
          "192.168.1.0/24"
        ];
      };

      # More frequent Nix GC for small storage
      nix.gc.dates = "daily";
      nix.gc.options = "--delete-older-than 3d";

      environment.systemPackages = with pkgs; [
        micro
        wget
        htop
      ];

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
    };
}
