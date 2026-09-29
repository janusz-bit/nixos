{
  inputs,
  customTop,
  ...
}:
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

      # The RPi vendor kernel from nixos-hardware uses PREEMPT=yes but does not
      # set PREEMPT_LAZY=no. nixpkgs common-config.nix sets PREEMPT_LAZY=yes for
      # kernel >= 6.18, which conflicts with PREEMPT=yes (same kconfig choice).
      # boot.kernelPatches is not applied because nixos-hardware hardcodes
      # kernelPatches inside buildLinux (via callPackage), bypassing the NixOS
      # kernel module's apply hook. Use argsOverride on the nixos-hardware
      # kernel.nix to inject PREEMPT_LAZY=n via extraConfig (legacy string format
      # appended to the intermediate kernel config, overriding structured config).
      # Ref: https://github.com/NixOS/nixpkgs/commit/d79e72ee0533cd5ce021dcd8863599e9dd290a33
      boot.kernelPackages =
        let
          rpiKernel = pkgs.callPackage "${inputs.nixos-hardware}/raspberry-pi/common/kernel.nix" {
            rpiVersion = 4;
            argsOverride = {
              extraConfig = ''
                PREEMPT_LAZY n
              '';
            };
          };
        in
        pkgs.linuxPackagesFor rpiKernel;

      # CPU Performance optimization
      powerManagement.cpuFreqGovernor = "ondemand";

      # Memory optimization: SSD swap and zRAM
      zramSwap.enable = true;
      zramSwap.algorithm = "zstd";
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
          # Klucze roota laptopa i RPi (bez starej maszyny AVF droid-android).
          openssh.authorizedKeys.keys = builtins.attrValues keys.hosts;
        };
        # Twój klucz z laptopa (ssh ssh.janusz-bit.com loguje się jako root).
        root.openssh.authorizedKeys.keys = [ keys.users.janusz-bit ];
      };
    };
}
