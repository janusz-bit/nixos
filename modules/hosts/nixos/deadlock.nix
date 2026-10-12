# Deadlock (appid 1422450): wrapper w stylu gamemoderun.
# W Launch Options Steama wpisz:  deadlockrun %command%
# Proton: Właściwości gry -> Zgodność -> wymuś "Proton-CachyOS x86-64-v3".
# Valve mapuje Deadlocka na Proton Experimental z priorytetem 100, wyżej niż
# domyślne narzędzie (75), więc domyślny proton-cachyos z gaming.nix tu nie
# działa; wygrywa tylko wybór dla gry (250), który Steam trzyma w
# config/config.vdf (CompatToolMapping) i nadpisuje przy wyjściu — nie da się
# go ustawić z flake'a. 2026-10-12: na experimental-11.0-20261001 gra działała
# słabo, na cachyos-11.0-20260703 dobrze (ten sam runtime SteamLinuxRuntime_4).
# Sprawdzenie: log Protona (PROTON_LOG=1) zawiera
# "dxvk.enableNvRawAccessChains = False" i "shaderRawAccessChains : 0",
# a `journalctl -k | grep Xid` po meczu jest pusty.
{
  flake.modules.nixos.nixos-deadlock =
    { lib, pkgs, ... }:
    let
      # See temporary-fixes.md: na sterownikach NVIDIA 610/615 (tu 615.71.09)
      # DXVK z VK_NV_raw_access_chains zawiesza GPU w walce (Xid 109
      # CTX SWITCH TIMEOUT, obraz stoi, dźwięk gra). Fix DXVK (PR 5958) nie
      # trafił jeszcze do żadnego Protona.
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
