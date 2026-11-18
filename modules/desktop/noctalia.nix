# Druga sesja graficzna obok Plasmy: kompozytor niri z powłoką Noctalia
# (pasek, launcher, powiadomienia, OSD, blokada ekranu; docs.noctalia.dev),
# do wyboru w SDDM jako „Niri”. Plasma zostaje sesją domyślną, a aplikacje
# KDE, KWallet i agent polkit KDE działają w obu sesjach.
#
# /etc/niri/config.kdl to _noctalia/niri.kdl: include domyślnej konfiguracji
# niri z Noctalią zamiast waybar, potem zalecenia Noctalii i skróty do jej IPC
# (`noctalia msg --help`). niri czyta ją tylko, gdy nie ma
# ~/.config/niri/config.kdl; własne zmiany idą tam, zaczynając od
# `include "/etc/niri/config.kdl"`. Ustawienia Noctalii
# (~/.config/noctalia/) to plik użytkownika, jak ustawienia Plasmy.
#
# Sprawdzenie: `niri validate` sprawdza konfigurację już przy buildzie; po
# zalogowaniu do sesji Niri `noctalia msg status` oraz
# `systemctl --user status plasma-polkit-agent plasma-kwallet-pam`.
_: {
  flake.modules.nixos.desktop-noctalia =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      niri = config.programs.niri.package;
      niriConfig =
        pkgs.runCommand "niri-config"
          {
            nativeBuildInputs = [ niri ];
            defaultConfig = "${niri.doc}/share/doc/niri/default-config.kdl";
            noctaliaConfig = ./_noctalia/niri.kdl;
          }
          ''
            mkdir "$out"
            substitute "$defaultConfig" "$out/default.kdl" \
              --replace-fail 'spawn-at-startup "waybar"' 'spawn-at-startup "noctalia"'
            substitute "$noctaliaConfig" "$out/config.kdl" --subst-var out
            niri validate -c "$out/config.kdl"
          '';
    in
    {
      programs = {
        niri = {
          enable = true;
          # Nautilus (cały stos GNOME) tylko jako okno wyboru plików portalu
          # GNOME; bez niego moduł niri bierze FileChooser z portalu GTK.
          useNautilus = false;
        };
        noctalia.enable = true;
      };

      environment = {
        etc."niri/config.kdl".source = "${niriConfig}/config.kdl";
        # Aplikacje X11 (Steam, gry): niri uruchamia xwayland-satellite na
        # żądanie, gdy jest w PATH, a moduł niri go nie instaluje.
        systemPackages = [ pkgs.xwayland-satellite ];
      };

      services = {
        # Moduły niri i plasma6 dają różne mkDefault (konflikt). SDDM i tak
        # podpowiada ostatnio wybraną sesję; ta wartość działa przy pierwszym
        # logowaniu.
        displayManager.defaultSession = "plasma";
        # Moduł niri włącza gnome-keyring: druga usługa org.freedesktop.secrets
        # obok KWalleta i jego PAM w każdej sesji, także w Plasmie.
        gnome.gnome-keyring.enable = false;
      };

      # Portal Secret (Flatpak) z modułu niri wskazuje wyłączony wyżej
      # gnome-keyring; mkForce przestawia go na portal KWalleta (kwallet.portal).
      xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "kwallet";

      # Jednostki, które w Plasmie startuje plasma-workspace.target, a w sesji
      # niri nic: agent polkit KDE (okna hasła dla pkexec, Discover; agent
      # Noctalii jest domyślnie wyłączony) i odblokowanie KWalleta hasłem
      # z SDDM (wpis autostartu XDG pam_kwallet_init ma X-systemd-skip). After
      # niri.service (Type=notify): wtedy WAYLAND_DISPLAY jest już
      # w środowisku menedżera. asDropin, bo te jednostki leżą w /share
      # profilu, a nie w systemd.packages: domyślne asDropinIfExists
      # wygenerowałoby pełny plik jednostki bez ExecStart i przesłoniło
      # oryginał także w Plasmie. Bez domyślnego PATH NixOS: drop-in działa
      # też w Plasmie, a pam_kwallet_init przekazuje swoje środowisko
      # kwalletd.
      systemd.user.services =
        lib.genAttrs
          [
            "plasma-polkit-agent"
            "plasma-kwallet-pam"
          ]
          (_: {
            overrideStrategy = "asDropin";
            enableDefaultPath = false;
            wantedBy = [ "niri.service" ];
            after = [ "niri.service" ];
          });
    };
}
