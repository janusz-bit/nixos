{ inputs, self, ... }:
{
  flake.nixosModules.nixos-configuration =
    {
      config,
      pkgs,
      lib,
      ...
    }:

    {
      specialisation = {
        power-save.configuration = {
          powerManagement.cpuFreqGovernor = lib.mkForce "powersave";
          services.power-profiles-daemon.enable = lib.mkForce false;
          services.tlp = {
            enable = lib.mkForce true;
            settings = {
              CPU_SCALING_GOVERNOR_ON_AC = "powersave";
              CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
              CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
              CPU_ENERGY_PERF_POLICY_ON_AC = "power";
              PLATFORM_PROFILE_ON_BAT = "low-power";
              PLATFORM_PROFILE_ON_AC = "low-power";
            };
          };
          services.scx.extraArgs = lib.mkForce [
            "--powersave"
          ];
        };
        reverse-sync.configuration = {
          hardware.nvidia = {
            powerManagement.finegrained = false;
            prime = {
              offload.enable = false;
              offload.enableOffloadCmd = false;
              reverseSync.enable = true;
            };
          };
        };
        sync-mode.configuration = {
          hardware.nvidia = {
            powerManagement.finegrained = false;
            prime = {
              offload.enable = false;
              offload.enableOffloadCmd = false;
              sync.enable = true;

            };
          };
        };
      };
      nixpkgs.overlays = [
        inputs.nix-cachyos-kernel.overlays.default
        self.overlays.bootdev-cli-overlay
      ];
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v3;
      environment.sessionVariables = {
        GAMEMODERUNEXEC = "env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only PROTON_ENABLE_WAYLAND=1 PROTON_FSR4_UPGRADE=1	PROTON_DLSS_UPGRADE=1 PROTON_XESS_UPGRADE=1 PROTON_USE_NTSYNC=1";
      };
      boot.supportedFilesystems = [ "btrfs" ];
      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
      boot.extraModprobeConfig = ''
        options cfg80211 ieee80211_regdom=PL
        options rtw89_core disable_aspm_l1=y disable_aspm_l1ss=y
        options rtw89pci disable_aspm_l1=y disable_aspm_l1ss=y disable_clkreq=y
      '';
      services.btrfs.autoScrub.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      services.flatpak.enable = true;

      services.ollama.enable = true;
      services.ollama.package = pkgs.ollama-cuda;
      services = {

        ananicy = {
          enable = true;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };

        scx.enable = true;
        scx.scheduler = "scx_lavd";
        scx.extraArgs = [
          "--performance"
        ];

        displayManager = {
          sddm.wayland.enable = true;
          sddm.enable = true;
        };
        desktopManager.plasma6.enable = true;

        # Enable the X11 windowing system.
        # You can disable this if you're only using the Wayland session.
        xserver.enable = true;

        # Configure keymap in X11
        xserver.xkb = {
          layout = "pl";
          variant = "";
        };

        # Enable CUPS to print documents.
        printing.enable = true;

        # Enable sound with pipewire.
        pulseaudio.enable = false;
        pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
          # If you want to use JACK applications, uncomment this
          #jack.enable = true;

          # use the example session manager (no others are packaged yet so this is enabled by default,
          # no need to redefine it in your config for now)
          #media-session.enable = true;
        };

      };
      hardware = {
        bluetooth.enable = true;
      };

      networking = {
        hostName = "nixos";
        networkmanager = {
          # Enable networking
          enable = true;
          # wifi.backend = "iwd";
          wifi.powersave = false;
        };
      };

      # Set your time zone.
      time.timeZone = "Europe/Warsaw";

      # Select internationalisation properties.
      i18n.defaultLocale = "pl_PL.UTF-8";

      i18n.extraLocaleSettings = {
        LC_ADDRESS = "pl_PL.UTF-8";
        LC_IDENTIFICATION = "pl_PL.UTF-8";
        LC_MEASUREMENT = "pl_PL.UTF-8";
        LC_MONETARY = "pl_PL.UTF-8";
        LC_NAME = "pl_PL.UTF-8";
        LC_NUMERIC = "pl_PL.UTF-8";
        LC_PAPER = "pl_PL.UTF-8";
        LC_TELEPHONE = "pl_PL.UTF-8";
        LC_TIME = "pl_PL.UTF-8";
      };

      # Configure console keymap
      console.keyMap = "pl2";
      security = {
        pam.services.${config.custom.defaultUser}.kwallet.enable = true;
        rtkit.enable = true;
      };
      systemd.settings.Manager = {
        DefaultLimitNOFILE = "524288";
      };
      security.pam.loginLimits = [
        {
          domain = "${config.custom.defaultUser}";
          type = "hard";
          item = "nofile";
          value = "524288";
        }
      ];

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.${config.custom.defaultUser} = {
        initialPassword = "${config.custom.defaultUser}";
        isNormalUser = true;
        description = "${config.custom.defaultUser}";
        extraGroups = [
          "networkmanager"
          "wheel"
          "gamemode"
        ];
      };
      users.users.root.initialPassword = "root";
      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

    };

}
