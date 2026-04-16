{ ... }:
{
  flake.nixosModules.raspberry-pi-4-configuration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Bootloader is handled by nixos-raspberrypi module
      # boot.loader.grub.enable = false;
      # boot.loader.generic-extlinux-compatible.enable = true;

      networking.hostName = "raspberry-pi-4"; # Define your hostname.

      # Configure network connections interactively with nmcli or nmtui.
      networking.networkmanager.enable = true;

      # Set your time zone.
      time.timeZone = "Europe/Warsaw";

      # Configure network proxy if necessary
      # networking.proxy.default = "http://user:password@proxy:port/";
      # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

      # Select internationalisation properties.
      # i18n.defaultLocale = "en_US.UTF-8";
      # console = {
      #   font = "Lat2-Terminus16";
      #   keyMap = "us";
      #   useXkbConfig = true; # use xkb.options in tty.
      # };

      # Enable the X11 windowing system.
      # services.xserver.enable = true;

      # Configure keymap in X11
      # services.xserver.xkb.layout = "us";
      # services.xserver.xkb.options = "eurosign:e,caps:escape";

      # Enable CUPS to print documents.
      # services.printing.enable = true;

      # Enable sound.
      # services.pulseaudio.enable = true;
      # OR
      # services.pipewire = {
      #   enable = true;
      #   pulse.enable = true;
      # };

      # Enable touchpad support (enabled default in most desktopManager).
      # services.libinput.enable = true;

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.${config.custom.defaultUser} = {
        initialPassword = "${config.custom.defaultUser}";
        isNormalUser = true;
        description = "${config.custom.defaultUser}";
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
      };

      # programs.firefox.enable = true;

      # List packages installed in system profile.
      # You can use https://search.nixos.org/ to find more packages (and options).
      environment.systemPackages = with pkgs; [
        micro
        wget
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
      services.openssh.enable = true;

      # Open ports in the firewall.
      # networking.firewall.allowedTCPPorts = [ ... ];
      # networking.firewall.allowedUDPPorts = [ ... ];
      # Or disable the firewall altogether.
      # networking.firewall.enable = false;
    };
}
