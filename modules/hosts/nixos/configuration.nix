{ inputs, ... }:
{
  flake = {
    nixosModules = {
      nixos-configuration =
        { config, pkgs, ... }:

        {
          # Bootloader.
          # boot.loader.systemd-boot.enable = true;

          nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
          boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-lts-lto-x86_64-v3;
          services.scx.enable = true;
          services.scx.scheduler = "scx_bpfland";
          services.scx.extraArgs = [
            "-m performance"
            "-w"
          ];

          hardware.bluetooth.enable = true;

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

          # Enable the X11 windowing system.
          # You can disable this if you're only using the Wayland session.
          services.xserver.enable = true;

          # Enable the KDE Plasma Desktop Environment.
          services.displayManager.sddm.enable = true;
          services.desktopManager.plasma6.enable = true;

          # Configure keymap in X11
          services.xserver.xkb = {
            layout = "pl";
            variant = "";
          };

          # Configure console keymap
          console.keyMap = "pl2";

          # Enable CUPS to print documents.
          services.printing.enable = true;

          # Enable sound with pipewire.
          services.pulseaudio.enable = false;
          security.rtkit.enable = true;
          services.pipewire = {
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

          # Enable touchpad support (enabled default in most desktopManager).
          # services.xserver.libinput.enable = true;

          # Define a user account. Don't forget to set a password with ‘passwd’.
          users.users.dinosaur = {
            isNormalUser = true;
            description = "dinosaur";
            extraGroups = [
              "networkmanager"
              "wheel"
            ];
            packages = with pkgs; [
              # kdePackages.kate
              #  thunderbird
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
    };
  };
}
