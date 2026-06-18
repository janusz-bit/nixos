{ self, inputs, ... }:
{
  flake.modules.nixos.rpi-configuration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      networking.hostName = "raspberry-pi-4";

      nixpkgs.overlays = [
        self.overlays.trilium
        self.overlays.hermes-agent
      ];

      # Fix for missing dw-hdmi module on RPi4 generic image
      boot = {
        initrd.allowMissingModules = true;
        kernel.sysctl."vm.swappiness" = 100;
        tmp.useTmpfs = true;
      };

      # Use the mainline kernel instead of the Raspberry Pi vendor kernel from
      # nixos-hardware. The vendor kernel (linux-rpi 6.18.33) fails to build on
      # nixos-unstable because nixpkgs common-config.nix sets PREEMPT_LAZY=yes
      # (for kernel >= 6.18) which conflicts with nixos-hardware's PREEMPT=yes
      # (vendor defconfig uses full preempt).
      # See: https://github.com/NixOS/nixpkgs/commit/d79e72ee0533cd5ce021dcd8863599e9dd290a33
      # The mainline kernel builds cleanly from the nixos.org binary cache.
      boot.kernelPackages = pkgs.linuxPackages;

      # CPU Performance optimization
      powerManagement.cpuFreqGovernor = "ondemand";

      # Memory optimization: SSD swap and zRAM
      zramSwap.enable = true;
      zramSwap.algorithm = "zstd";
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size = 8192; # 4GB of swap on SSD
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
      nix = {
        settings = {
          max-jobs = 2;
          trusted-users = [
            "root"
            "@wheel"
            "hermes"
          ];
        };
        gc = {
          dates = "daily";
          options = "--delete-older-than 3d";
        };
      };

      # Workaround for python3.12-doc build failure with sphinx/docutils 0.22
      # https://github.com/NixOS/nixpkgs/issues/499166
      documentation.doc.enable = false;

      environment.systemPackages = with pkgs; [
        micro
        htop
        uv
        nodejs_22
        ripgrep
        ffmpeg
        python311
        nix
        git
      ];

      # User configuration
      users.users.${config.customBot.defaultUser} = {
        initialPassword = "${config.customBot.defaultUser}";
        isNormalUser = true;
        description = "${config.customBot.defaultUser}";
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQRhJASMQB1ClDBwqnYGZXSSGAr1S2y5KaQ5Z0Fc5+ root@nixos"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb1ln2lU/lR4NwlfUQ+oPurNDI+O6B0uiFCcWfYuGj3 root@nixos"
        ];
      };
    };
}
