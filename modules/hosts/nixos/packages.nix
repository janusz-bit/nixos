{ self, ... }:
{
  flake.nixosModules.nixos-packages =
    { pkgs, config, ... }:
    {
      environment.systemPackages = with pkgs; [
        zed-editor
        gparted
        qbittorrent-enhanced
        heroic # install heroic launcher
        protonup-qt
        vesktop
        vlc
        tor-browser
        self.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos-v3
        noctalia-shell
        niri
        alacritty
        sqlite
        brave
        libreoffice-qt
        kdePackages.qrca
        signal-desktop
        element-desktop
        prismlauncher
        lutris
        bootdev-cli
        kdePackages.kcalc
      ];
      # Install firefox.
      programs.firefox.enable = true;
      hardware.wooting.enable = true;
      services.mullvad-vpn.enable = true;
      services.mullvad-vpn.package = pkgs.mullvad-vpn;
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        dedicatedServer.openFirewall = true; # Open ports for Source Dedicated Server hosting};
        extraCompatPackages = [
          self.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos-v3
        ];
      };
      programs.gamemode.enable = true; # for performance mode
      programs.obs-studio = {
        enable = true;

        # optional Nvidia hardware acceleration
        package = (
          pkgs.obs-studio.override {
            cudaSupport = true;
          }
        );

        plugins = with pkgs.obs-studio-plugins; [
          wlrobs
          obs-backgroundremoval
          obs-pipewire-audio-capture
          obs-gstreamer
          obs-vkcapture
        ];
      };
      services.syncthing = {
        enable = true;
        user = "${config.custom.defaultUser}";
        dataDir = "/home/${config.custom.defaultUser}/Sync";
        configDir = "/home/${config.custom.defaultUser}/.config/syncthing";
      };
    };
}
