# Opcje customBot: ustawienia zależne od hosta (cel aliasów update/push,
# fastfetch w powitaniu fish, główny użytkownik, endpoint MCP Trilium,
# dodatkowi providerzy Prime Agenta). flakeTarget (bez wartości domyślnej)
# ustawia rejestr hostów i sd-image.nix, primeAgentProviders
# skills/external.nix, a resztę host nadpisuje w swoim default.nix.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.wsl.config.customBot`.
{ customTop, ... }:
{
  flake.modules.nixos.base-options =
    { lib, ... }:
    {
      options.customBot = {
        # Bez domyślnej: konfiguracja spoza rejestru, która jej nie ustawi,
        # kończy ewaluację błędem zamiast dostać aliasy wdrażające inny host.
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
          default = customTop.users.default;
          description = "Główny użytkownik interaktywny hosta (właściciel sekretów użytkownika).";
        };
        triliumMcpUrl = lib.mkOption {
          type = lib.types.str;
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
