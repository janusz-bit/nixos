# Deadlock (appid 1422450): wrapper w stylu gamemoderun.
# W Launch Options Steama wpisz:  deadlockrun %command%
# Proton wybiera Steam: Valve mapuje grę na Proton Experimental (priorytet 100,
# wyżej niż domyślny proton-cachyos z gaming.nix); 2026-10-12 na
# experimental-11.0-20261001 gra startuje i renderuje na RTX 5060.
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
