# Deadlock (appid 1422450): wrapper na gamemoderun; Launch Options:
# `deadlockrun %command%`.
#
# Proton trzeba wymusić w Steamie dla gry (Właściwości → Zgodność →
# "Proton-CachyOS x86-64-v3"): mapowanie Valve na Proton Experimental (priorytet
# 100) wygrywa z domyślnym narzędziem ze steam.nix (75), a wybór dla gry (250)
# Steam trzyma w config.vdf i nadpisuje przy wyjściu, więc flake go nie ustawi.
# 2026-10-12: na experimental-11.0-20261001 gra działała słabo, na
# cachyos-11.0-20260703 dobrze (ten sam SteamLinuxRuntime_4).
# Sprawdzenie: log Protona (PROTON_LOG=1) ma "dxvk.enableNvRawAccessChains = False"
# i "shaderRawAccessChains : 0", a `journalctl -k | grep Xid` po meczu jest pusty.
_: {
  flake.modules.nixos.gaming-deadlock =
    { lib, pkgs, ... }:
    let
      # Tymczasowe (temporary-fixes.md nr 6): na NVIDIA 610/615 DXVK z
      # VK_NV_raw_access_chains zawiesza GPU w walce (Xid 109, obraz stoi, dźwięk gra).
      deadlockrun = pkgs.writeShellApplication {
        name = "deadlockrun";
        text = ''
          export DXVK_CONFIG="dxvk.enableNvRawAccessChains=False"
          exec ${lib.getExe' pkgs.gamemode "gamemoderun"} "$@"
        '';
      };
    in
    {
      environment.systemPackages = [ deadlockrun ];
    };
}
