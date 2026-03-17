{ inputs, ... }:
{
  flake.nixosModules.nixos-configuration =
    {
      config,
      pkgs,
      lib,
      ...
    }:

    {
      # Bootloader.
      # boot.loader.systemd-boot.enable = true;
      #
      specialisation = {
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
      powerManagement.cpuFreqGovernor = "performance";
      nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-lts-lto-x86_64-v3;
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

      networking.hostName = "nixos"; # Define your hostname.
      # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

      # Configure network proxy if necessary
      # networking.proxy.default = "http://user:password@proxy:port/";
      # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

      # Enable networking
      networking.networkmanager.enable = true;

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
      security.rtkit.enable = true;

      # Enable touchpad support (enabled default in most desktopManager).
      # services.xserver.libinput.enable = true;

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.dinosaur = {
        isNormalUser = true;
        description = "dinosaur";
        extraGroups = [
          "networkmanager"
          "wheel"
          "gamemode"
        ];
        packages = with pkgs; [
          # kdePackages.kate
          #  thunderbird
          # kdePackages.bluedevil
          # kdePackages.bluez-qt
          # openobex
          # obexftp
        ];
      };

      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

      # List packages installed in system profile. To search, run:
      # $ nix search wget
      environment.systemPackages = with pkgs; [
        #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
        #  wget
      ];

      # Some programs need SUID wrappers, can be configured further or are
      # started in user sessions.
      # programs.mtr.enable = true;
      # programs.gnupg.agent = {
      #   enable = true;
      #   enableSSHSupport = true;
      # };

      # List services that you want to enable:

      # Enable the OpenSSH daemon.
      # services.openssh.enable = true;

      # Open ports in the firewall.
      # networking.firewall.allowedTCPPorts = [ ... ];
      # networking.firewall.allowedUDPPorts = [ ... ];
      # Or disable the firewall altogether.
      # networking.firewall.enable = false;
    };

}
