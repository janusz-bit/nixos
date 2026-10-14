# GameMode na czas gry: renice procesów gry, profil power-profiles-daemon
# "performance" i zmienne uruchamiania (GAMEMODERUNEXEC) — na hybrydzie
# NVIDIA PRIME gra idzie na dGPU. Wrappery per gra (dbdrun, deadlockrun)
# wołają gamemoderun, więc dziedziczą to samo.
#
# Bez ananicy-cpp (reguły CachyOS): przy cgroup v2 każda aplikacja ma własny
# scope, a nice działa tylko wewnątrz jednej cgroup — zmierzone: nice -4 vs
# +15 w osobnych scope'ach 50/50 CPU, w jednym 91/9; ioclass ignoruje
# scheduler NVMe `none`. Za to ustawiał Konsoli/Steamowi nice -4/16, przez co
# GameMode odmawiał renice („Refused to renice … prio was (-4)”), a nixpkgs
# wymusza cgroup_realtime_workaround = true (KWin i Xwayland w root cgroup).
#
# Sprawdzenie: `gamemoded -s` w trakcie gry („gamemode is active”),
# `powerprofilesctl get` → performance.
_: {
  flake.modules.nixos.gaming-gamemode =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # GameMode → power-profiles-daemon: na czas gry profil "performance"
      # (platform_profile firmware Lenovo jak Fn+Q: wyższe limity mocy,
      # głośniejsze wentylatory + EPP "performance"), po grze przywraca
      # profil sprzed startu (np. power-saver na baterii).
      # gamemoded (usługa użytkownika) ma PATH zawężony do pkexec, więc
      # skrypt niesie własny PATH (runtimeInputs).
      gamemodePowerProfile = pkgs.writeShellApplication {
        name = "gamemode-power-profile";
        runtimeInputs = [
          pkgs.coreutils
          config.services.power-profiles-daemon.package
        ];
        text = ''
          state="$XDG_RUNTIME_DIR/gamemode-power-profile"
          case "$1" in
            start)
              powerprofilesctl get > "$state"
              powerprofilesctl set performance
              ;;
            end)
              prev=$(cat "$state" 2>/dev/null || true)
              rm -f "$state"
              powerprofilesctl set "''${prev:-balanced}"
              ;;
          esac
        '';
      };

      # PRIME render offload dla gier: GLX i Vulkan na dGPU NVIDII.
      primeOffloadEnv = lib.optionals config.hardware.nvidia.prime.offload.enable [
        "__NV_PRIME_RENDER_OFFLOAD=1"
        "__VK_LAYER_NV_optimus=NVIDIA_only"
        "__GLX_VENDOR_LIBRARY_NAME=nvidia"
      ];
      protonEnv = [
        "PROTON_ENABLE_WAYLAND=1"
        "PROTON_ENABLE_NGX_UPDATER=1"
        "PROTON_FSR4_UPGRADE=1"
        "PROTON_DLSS_UPGRADE=1"
        "PROTON_XESS_UPGRADE=1"
      ];
    in
    {
      # GameMode: dynamiczne zarządzanie priorytetami CPU/GPU i profili energetycznych.
      # Domyślnie (1.8.2) już: governor "performance", pinning gry na
      # P-rdzenie (hybryda P+E), wyłączona mitygacja split-lock. GameMode
      # pomija ioprio („ioprio was (0) but we expected (4)” w journalu),
      # a scheduler NVMe `none` i tak ignoruje priorytety I/O.
      programs.gamemode = {
        enable = true;
        settings = {
          # nice -10 dla procesów gry (gamemoded ma CAP_SYS_NICE z wrappera NixOS).
          # Działa tylko względem procesów z tej samej cgroup (scope Steama:
          # steamwebhelper, fossilize_replay); między aplikacjami decyduje
          # cpu.weight. GameMode renicuje wątki tylko z nice 0 — dlatego bez
          # ananicy-cpp (nagłówek).
          general.renice = 10;
          custom = lib.mkIf config.services.power-profiles-daemon.enable {
            start = "${lib.getExe gamemodePowerProfile} start";
            end = "${lib.getExe gamemodePowerProfile} end";
          };
        };
      };

      environment.sessionVariables.GAMEMODERUNEXEC = lib.concatStringsSep " " (
        [ "env" ] ++ primeOffloadEnv ++ protonEnv
      );

      # Reguła polkit GameMode pozwala członkom grupy gamemode zmieniać
      # governor CPU i zegary GPU bez hasła.
      users.users.${config.customBot.defaultUser}.extraGroups = [ "gamemode" ];
    };
}
