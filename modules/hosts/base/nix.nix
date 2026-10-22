# Nix i nixpkgs na każdym hoście: flakes, cache binarne (te same listy co
# nixConfig we flake.nix), okresowe GC i deduplikacja sklepu, pakiety
# niewolne i overlay repo (pakiety lokalne).
#
# trusted-users zostaje domyślne (tylko root, bez @wheel): trusted user może
# importować niepodpisane ścieżki i zmieniać substitutery, czyli ma roota bez
# hasła, a jako użytkownik działa tu wiele agentów AI. Cache z nix.settings
# działają i bez tego, a nixos-rebuild idzie przez sudo.
#
# Sprawdzenie: `nix config show | grep -E '^(extra-)?(substituters|trusted)'`.
{ customTop, self, ... }:
{
  flake.modules.nixos.base-nix =
    { lib, ... }:
    {
      nixpkgs = {
        config.allowUnfree = true;
        overlays = [ self.overlays.local-packages ];
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
