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

      # CPU Performance optimization
      powerManagement.cpuFreqGovernor = "ondemand";
      nix.settings.max-jobs = 2;

      # Memory optimization: SSD swap and zRAM
      zramSwap.enable = true;
      zramSwap.algorithm = "zstd";
      boot.kernel.sysctl."vm.swappiness" = 100;
      boot.tmp.useTmpfs = true;
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size = 4096; # 4GB of swap on SSD
        }
      ];

      # Network configuration
      networking.networkmanager.enable = true;
      time.timeZone = "Europe/Warsaw";

      # Security hardening
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        settings.KbdInteractiveAuthentication = false;
      };

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
