# Nix i nixpkgs na każdym hoście: flakes, cache binarne (te same listy co
# nixConfig we flake.nix), okresowe GC i deduplikacja sklepu, pakiety
# niewolne i overlaye repo (opencode z konfiguracją, pakiety lokalne).
#
# nix.settings.trusted-users celowo zostaje domyślne (tylko root) — bez
# @wheel. Trusted user nixa może importować niepodpisane ścieżki i zmieniać
# substitutery, czyli ma roota bez hasła, a jako użytkownik działa tu wiele
# agentów AI. Wszystkie potrzebne cache są w nix.settings, więc zwykły
# użytkownik z nich korzysta; nixos-rebuild i tak idzie przez sudo.
#
# Sprawdzenie: `nix config show | grep -E '^(extra-)?(substituters|trusted)'`.
{ customTop, self, ... }:
{
  flake.modules.nixos.base-nix =
    { lib, ... }:
    {
      nixpkgs = {
        config.allowUnfree = true;
        overlays = [
          # self.overlays.opencode-config
          self.overlays.local-packages
        ];
      };

      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          inherit (customTop.nixConfig) extra-substituters extra-trusted-public-keys;
        };
        # mkDefault: RPi ma ciaśniejszy dysk i nadpisuje harmonogram GC.
        gc = {
          automatic = true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 7d";
        };
        # Deduplikacja okresowym timerem zamiast auto-optimise-store, które
        # hardlinkuje przy każdym buildzie/substytucji i spowalnia rebuildy.
        optimise.automatic = true;
      };
    };
}
