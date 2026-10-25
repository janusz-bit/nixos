# Opcje customBot: ustawienia zależne od hosta (cel aliasów update/push,
# fastfetch w powitaniu fish, główny użytkownik, endpoint MCP Trilium,
# dodatkowi providerzy Prime Agenta, usługi zatrzymywane przez lockdown,
# skille agentów kodujących). flakeTarget (bez wartości domyślnej) ustawia
# rejestr hostów i sd-image.nix, primeAgentProviders i agentSkills moduły
# skilli (modules/skills/), lockdownServices moduły usług, a resztę host
# nadpisuje w swoim default.nix. Do tego opcja tylko do odczytu customTop:
# stałe repozytorium z modules/args.nix dla modułów NixOS.
#
# customTop w NixOS to wartość opcji flake-parts customTop (typy i opisy
# w modules/options.nix), żeby moduły NixOS czytały ją z `config.customTop`.
# Moduł base-options importuje każda konfiguracja NixOS z modułami, które ją
# czytają (hosty przez base, ISO instalatora wprost).
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.wsl.config.customBot`
# i `nix eval --json .#nixosConfigurations.wsl.config.customTop.lan`.
{ config, ... }:
let
  # Moduł NixOS niżej ma własne `config`.
  inherit (config) customTop;
in
{
  flake.modules.nixos.base-options =
    { lib, ... }:
    {
      options.customTop = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        default = customTop;
        defaultText = lib.literalMD "wartość opcji flake-parts `customTop` (modules/args.nix)";
        description = ''
          Stałe repozytorium (modules/args.nix), te same na każdym hoście;
          typy i opisy pól ma opcja flake-parts customTop.
        '';
      };

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
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Endpoint MCP Trilium dla prime-agenta (settings.json) i skilla
            trilium-notes (TRILIUM_MCP_URL); null = host bez Trilium: bez
            serwera MCP, skilla i tokenu ETAPI. Laptop ustawia desktopowy
            Trilium na 37840.
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
        lockdownServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Usługi systemd (nazwy bez .service), które `lockdown on`
            zatrzymuje i blokuje do `lockdown off` (base-lockdown): te, do
            których sieć dochodzi inaczej niż przez port otwarty w firewallu
            (tunel, własne połączenia wychodzące, radio). Porty z
            networking.firewall lockdown zamyka sam. Dopisuje je moduł usługi;
            na hoście bez base-lockdown lista nic nie robi.
          '';
        };
        agentSkills = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = ''
            Skille (katalog z SKILL.md) dla każdego agenta kodującego hosta:
            Prime Agent, Claude Code, Codex i opencode. Linkuje je ai-skills
            (modules/skills/default.nix), więc działają tylko na hostach, które
            go importują. Ta sama nazwa z dwóch definicji kończy ewaluację
            błędem.
          '';
        };
      };
    };
}
