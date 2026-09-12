{ inputs, ... }:
{
  flake.modules.nixos.nixos-packages =
    { pkgs, config, ... }:
    let
      # Hermes Desktop (Electron) z flake hermes-agent; stan w ~/.hermes
      hermes-desktop = inputs.hermes-agent.packages.${pkgs.system}.desktop;
      # Waywallen (flake nix-waywallen): unified = daemon + UI + pluginy
      # (image/video/wallhaven + open-wallpaper-engine dla tapet .pkg)
      waywallen = inputs.waywallen.packages.${pkgs.system}.waywallen;
      # Plugin tapety dla Plazmy 6: oficjalny wariant "embed" z release
      # waywallen-display (moduł QML skompilowany i wbudowany w kpackage,
      # więc samowystarczalny). Kpackage z flake'a community ma zepsuty
      # układ plików (Plugin/qmldir wskazuje na nieistniejące QML), stąd
      # własna derivacja. To podpisany hashem prekompilowany zip
      # oficjalnego releasu (x86_64) — nie buduje się ze źródeł.
      waywallen-kde-plugin = pkgs.stdenvNoCC.mkDerivation {
        pname = "waywallen-kde-plugin";
        version = "0.3.3";
        src = pkgs.fetchurl {
          url = "https://github.com/waywallen/waywallen-display/releases/download/v0.3.3/waywallen-kde-0.3.3-x86_64-embed.zip";
          hash = "sha256-0SGuTy/KLSZkts1qb1x3GticUwOI3CQVWyRNhzOuBZ4=";
        };
        nativeBuildInputs = [ pkgs.unzip ];
        dontBuild = true;
        dontFixup = true;
        installPhase = ''
          runHook preInstall
          # setup.sh sam wchodzi do jedynego katalogu zipa (source root)
          mkdir -p $out/share/plasma/wallpapers/org.waywallen.kde
          cp -r . $out/share/plasma/wallpapers/org.waywallen.kde/
          runHook postInstall
        '';
        meta.description = "Waywallen KDE Plasma 6 wallpaper plugin (official embed package)";
      };
    in
    {
      environment.systemPackages = with pkgs; [
        vscode
        vscodium
        zed-editor
        kdePackages.partitionmanager
        qbittorrent-enhanced
        heroic # install heroic launcher
        protonup-qt
        vesktop
        vlc
        tor-browser
        # proton-ge-bin
        # niri
        alacritty
        sqlite
        # brave
        libreoffice-qt
        kdePackages.qrca
        # Waywallen — dynamiczne tapety (zamiennik Wallpaper Engine Plugin).
        # Nie wymaga Steama/Protonu; tapety Wallpaper Engine przez wbudowany
        # plugin open-wallpaper-engine. Ustawianie tapet: aplikacja waywallen.
        waywallen
        waywallen-kde-plugin
        signal-desktop
        element-desktop
        (prismlauncher.override {
          # Add binary required by some mod
          additionalPrograms = [ ffmpeg ];

          # Change Java runtimes available to Prism Launcher
          jdks = [
            graalvmPackages.graalvm-ce
            zulu8
            zulu17
            zulu
          ];
        })
        lutris
        bootdev-cli
        kdePackages.kcalc
        nextcloud-client
        haruna
        kdePackages.elisa
        sbctl
        joplin-desktop
        # bitwarden-desktop
        trilium-desktop
        foliate
        ungoogled-chromium
        # Compilers & build tools
        cmake
        ninja
        clang
        pkgs.pkgsCross.mingwW64.buildPackages.gcc
        wine64
        clang-tools
        lldb
        boost
        tea
        kdePackages.kdenlive
        opencode
        losange
        freecad-qt6
        antigravity-ide-fhs
        antigravity-cli
        hermes-desktop
      ];

      hardware.wooting.enable = true;

      programs = {
        # Install firefox.
        firefox.enable = true;

        obs-studio = {
          enable = true;

          # optional Nvidia hardware acceleration
          package = pkgs.obs-studio.override {
            cudaSupport = true;
          };

          plugins = with pkgs.obs-studio-plugins; [
            wlrobs
            obs-backgroundremoval
            obs-pipewire-audio-capture
            obs-gstreamer
            obs-vkcapture
          ];
        };
      };

      # Mullvad split upstream: pkgs.mullvad = daemon (module default),
      # pkgs.mullvad-vpn = GUI only, enabled via gui.enable.
      services = {
        mullvad-vpn = {
          enable = true;
          gui.enable = true;
        };

        syncthing = {
          enable = true;
          user = "${config.customBot.defaultUser}";
          dataDir = "/home/${config.customBot.defaultUser}/Sync";
          configDir = "/home/${config.customBot.defaultUser}/.config/syncthing";
          openDefaultPorts = true;
        };
      };
    };
}
