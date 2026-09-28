_: {
  flake.modules.nixos.nix-settings =
    { lib, ... }:
    {
      nix = {
        # mkDefault: RPi ma ciaśniejszy dysk i nadpisuje harmonogram GC.
        gc = {
          automatic = true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 7d";
        };
        # Deduplikacja okresowym timerem zamiast auto-optimise-store, które
        # hardlinkuje przy każdym buildzie/substytucji i spowalnia rebuildy.
        optimise.automatic = true;
        # nix.settings.trusted-users celowo zostaje domyślne (tylko root) —
        # bez @wheel. Trusted user nixa może importować niepodpisane ścieżki
        # i zmieniać substitutery, czyli ma roota bez hasła, a jako użytkownik
        # działa tu wiele agentów AI. Wszystkie potrzebne cache są w
        # nix.settings (base-configuration), więc zwykły użytkownik z nich
        # korzysta; nixos-rebuild i tak idzie przez sudo.
      };
    };
}
