{ customTop, ... }:
{
  flake.modules.nixos.rpi-configuration =
    {
      config,
      pkgs,
      ...
    }:
    let
      keys = import "${customTop.secretsDir}/keys.nix";
    in
    {
      networking.hostName = "raspberry-pi-4";

      # Fix for missing dw-hdmi module on RPi4 generic image
      boot = {
        initrd.allowMissingModules = true;
        kernel.sysctl."vm.swappiness" = 100;
        tmp.useTmpfs = true;
      };

      # CPU Performance optimization
      powerManagement.cpuFreqGovernor = "ondemand";

      # Memory optimization: SSD swap and zRAM
      zramSwap.enable = true;
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size = 8192; # 8GB of swap on SSD
        }
      ];

      # Network configuration
      networking.networkmanager.enable = true;
      time.timeZone = "Europe/Warsaw";

      # SSH: bazowe ustawienia (tylko klucze) z base-ssh. Logowanie roota
      # kluczem zostaje — to ścieżka administracyjna przez tunel
      # (`Host ssh.*` → `User root` w base-ssh).
      services.openssh.settings.PermitRootLogin = "prohibit-password";
      # Headless: bez x11-ssh-askpass (zależności X11).
      programs.ssh.enableAskPassword = false;

      # Stała sieć domowa — nie banuj hostów z LAN.
      services.fail2ban.ignoreIP = [ customTop.lan.subnet ];

      # More frequent Nix GC for small storage (nadpisuje mkDefault z nix-settings)
      nix = {
        settings.max-jobs = 2;
        gc = {
          dates = "daily";
          options = "--delete-older-than 3d";
        };
      };

      # Serwer headless: bez /share/doc. Przy okazji nie buduje się
      # python3.11-doc (nixpkgs#499166), więc overlay python-docs-fix jest zbędny.
      documentation.doc.enable = false;

      environment.systemPackages = with pkgs; [
        # micro, htop i uv pochodza z base (sharedPackages); git z base-git
        nodejs_22
        ripgrep
        ffmpeg
        python311
        tea # Gitea official CLI client
        antigravity-cli
        # Claude Code — agent kodujący w terminalu (nixpkgs)
        claude-code
      ];

      users.users = {
        ${config.customBot.defaultUser} = {
          initialPassword = "${config.customBot.defaultUser}";
          isNormalUser = true;
          description = "${config.customBot.defaultUser}";
          extraGroups = [
            "networkmanager"
            "wheel"
          ];
          # Klucze roota laptopa i RPi oraz telefonu (SSH z komórki).
          openssh.authorizedKeys.keys = builtins.attrValues keys.hosts ++ [ keys.users.phone ];
        };
        # Twój klucz z laptopa (ssh ssh.janusz-bit.com loguje się jako root).
        root.openssh.authorizedKeys.keys = [ keys.users.janusz-bit ];
      };
    };
}
