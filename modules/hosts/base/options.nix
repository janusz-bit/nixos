# Opcje customBot: ustawienia zależne od hosta (cel aliasów update/push,
# fastfetch w powitaniu fish, główny użytkownik, endpoint MCP Trilium, usługi
# zatrzymywane przez lockdown, porty Tailscale Serve). flakeTarget (bez
# wartości domyślnej) ustawia rejestr hostów i sd-image.nix, lockdownServices
# i tailscaleServe moduły usług, a resztę host
# nadpisuje w swoim default.nix. Skille i modele agentów to osobne opcje ai.*
# (modules/ai/). Do tego opcja tylko do odczytu customTop:
# stałe repozytorium z modules/args.nix dla modułów NixOS.
#
# customTop w NixOS to wartość opcji flake-parts customTop (typy i opisy
# w modules/options.nix), żeby moduły NixOS czytały ją z `config.customTop`.
# Moduł base-options importuje każda konfiguracja NixOS z modułami, które ją
# czytają (hosty przez base).
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
        lockdownServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Usługi systemd (nazwy bez .service), które `lockdown on`
            zatrzymuje i blokuje do `lockdown off` (base-lockdown): te, do
            których sieć dochodzi inaczej niż przez port otwarty w firewallu
            (Tailscale Serve, własne połączenia wychodzące, radio). Porty z
            networking.firewall lockdown zamyka sam. Dopisuje je moduł usługi;
            na hoście bez base-lockdown lista nic nie robi.
          '';
        };
        tailscaleServe = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                port = lib.mkOption {
                  type = lib.types.port;
                  description = "Port usługi HTTP na 127.0.0.1.";
                };
                users = lib.mkOption {
                  type = lib.types.nullOr (lib.types.listOf lib.types.str);
                  default = null;
                  description = ''
                    Konta, które oprócz roota (proxy tailscaled) łączą się
                    lokalnie z portem usługi; pozostałe dostają odmowę (reguła
                    iptables owner). null = bez ograniczenia, gdy usługa sama
                    uwierzytelnia każde połączenie.
                  '';
                };
              };
            }
          );
          default = { };
          example = {
            "443" = {
              port = 3773;
              users = [ "t3code" ];
            };
          };
          description = ''
            Tailscale Serve: port HTTPS pod nazwą MagicDNS hosta
            (https://<host>.<customTop.tailnet.domain>:<port>) → usługa HTTP na
            127.0.0.1. Jednostka tailscale-serve (hosts/tailscale.nix) ustawia po
            każdym zalogowaniu dokładnie tę mapę. Dopisuje ją moduł usługi; ten
            sam port z dwóch modułów z różnymi wartościami kończy ewaluację
            błędem.
          '';
        };
      };
    };
}
