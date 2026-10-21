# Opcje customBot: ustawienia zależne od hosta z wartościami domyślnymi
# (cel aliasów update/push, fastfetch w powitaniu fish, główny użytkownik,
# endpoint MCP Trilium); host nadpisuje je w swoim default.nix.
#
# To opcje NixOS (`config.customBot.*`), bo różnią się między hostami;
# stałe wspólne dla całego repo są w customTop (modules/args.nix).
# flakeTarget (bez domyślnej) ustawia rejestr hostów; raspberry-pi-4 powtarza
# go u siebie tylko dla obrazu SD, składanego poza rejestrem. Opisy opcji
# trafiają do generowanego docs/reference/options.md.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.wsl.config.customBot`.
_: {
  flake.modules.nixos.base-options =
    { lib, ... }:
    {
      options.customBot = {
        # Bez wartości domyślnej: dawne "default" (= laptop) dawało hostowi,
        # który zapomniał tej opcji, aliasy wdrażające system laptopa.
        flakeTarget = lib.mkOption {
          type = lib.types.str;
          description = "Nazwa nixosConfigurations używana przez aliasy update/push; ustawia ją rejestr hostów (modules/hosts/registry.nix).";
        };
        enableFastfetch = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Czy fish_greeting ma uruchamiać fastfetch.";
        };
        defaultUser = lib.mkOption {
          type = lib.types.str;
          default = "nixos";
          description = "Główny użytkownik interaktywny hosta (właściciel sekretów użytkownika).";
        };
        triliumMcpUrl = lib.mkOption {
          type = lib.types.str;
          # trilium-server z raspberry-pi-4 (modules/hosts/raspberry-pi-4/trilium.nix)
          default = "http://127.0.0.1:8081/mcp";
          description = ''
            Endpoint MCP Trilium dla prime-agenta (settings.json) i skilla
            trilium-notes (TRILIUM_MCP_URL). Zależny od hosta: RPi ma
            trilium-server na 8081, laptop desktopowy Trilium na 37840.
          '';
        };
        primeAgentProviders = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
          description = ''
            Dodatkowi providerzy prime-agenta (providers.<nazwa> w models.json,
            schemat jak w modules/hosts/base/prime-agent.nix), np. lokalny
            serwer, który działa tylko na tym hoście. Nazwa zajęta przez
            providera z prime-agent.nix kończy ewaluację błędem.
          '';
        };
      };
    };
}
