# GameMode na czas gry: renice procesów gry, profil power-profiles-daemon
# "performance" i zmienne uruchamiania (GAMEMODERUNEXEC) — na hybrydzie
# NVIDIA PRIME gra idzie na dGPU. Wrappery per gra (dbdrun, deadlockrun)
# wołają gamemoderun, więc dziedziczą to samo.
#
# Bez ananicy-cpp (reguły CachyOS): przy cgroup v2 każda aplikacja ma własny
# scope, a nice działa tylko w obrębie jednej cgroup (zmierzone: nice -4 vs +15
# w osobnych scope'ach 50/50 CPU, w jednym 91/9); ioclass ignoruje scheduler
# NVMe `none`. Jego nice -4/16 dla Konsoli/Steama blokował za to renice
# GameMode'a, który zmienia tylko wątki z nice 0 („Refused to renice … prio was
# (-4)”), a nixpkgs wymusza mu cgroup_realtime_workaround (KWin i Xwayland
# w root cgroup).
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
      # Na czas gry profil "performance" (platform_profile Lenovo jak Fn+Q: wyższe
      # limity mocy i EPP), po grze profil sprzed startu. gamemoded ma PATH
      # zawężony do pkexec, stąd runtimeInputs.
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
      # GameMode 1.8.2 domyślnie: governor "performance", gra na P-rdzeniach,
      # mitygacja split-lock wyłączona; ioprio pomija, a NVMe `none` i tak je ignoruje.
      programs.gamemode = {
        enable = true;
        settings = {
          # nice -10 (CAP_SYS_NICE z wrappera NixOS) działa tylko w cgroup gry (scope
          # Steama: steamwebhelper, fossilize_replay); między aplikacjami decyduje
          # cpu.weight.
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

      # Polkit GameMode: grupa gamemode zmienia governor CPU i zegary GPU bez hasła.
      users.users.${config.customBot.defaultUser}.extraGroups = [ "gamemode" ];
    };
}
