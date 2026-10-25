# Deklaracja opcji customTop: stałe tego repozytorium i jego właściciela
# (konto GitHub, e-mail, domena, konta użytkowników, język i strefa czasowa,
# domowy LAN, cache binarne, sekrety i klucze publiczne) jako opcja tylko do
# odczytu `config.customTop`, w modułach flake-parts i NixOS. Wartości są
# w modules/args.nix.
#
# Typy i opisy trafiają do docs/reference/options.md; pola wyliczane
# (repository.flake/url, cachix.url/pubKey) mają tu wartości domyślne.
# readOnly: moduł inny niż args.nix, który spróbuje ustawić wartość, kończy
# ewaluację błędem. Moduły NixOS widzą tę samą wartość przez opcję customTop
# z base-options (modules/hosts/base/options.nix); w module NixOS zapisanym
# w pliku flake-parts `config` to już konfiguracja NixOS, a let na górze
# pliku czyta customTop z flake-parts — wartość jest ta sama. Ustawienia
# zależne od hosta to opcje customBot.
#
# Nowe pole: deklaracja tutaj, wartość w args.nix (submoduł nie przyjmuje
# pól niezadeklarowanych).
{ lib, ... }:
let
  strOption =
    description:
    lib.mkOption {
      type = lib.types.str;
      inherit description;
    };
in
{
  options.customTop = lib.mkOption {
    readOnly = true;
    description = "Stałe repozytorium i jego właściciela, te same na każdym hoście; wartości w modules/args.nix.";
    type = lib.types.submodule (
      { config, ... }:
      {
        options = {
          owner = strOption "Konto GitHub, zarazem autor commitów (git user.name).";
          email = strOption "E-mail autora commitów (git user.email).";
          domain = strOption ''
            Strefa w Cloudflare: Nextcloud i server_name Matrixa pod samą
            domeną, reszta usług RPi pod <usługa>.<domena> (cloudflared.nix).
          '';

          repository = {
            name = strOption "Nazwa repozytorium na GitHubie.";
            flake = lib.mkOption {
              type = lib.types.str;
              default = "github:${config.owner}/${config.repository.name}";
              defaultText = lib.literalExpression ''"github:''${owner}/''${repository.name}"'';
              description = "Referencja flake'a dla update i push.";
            };
            url = lib.mkOption {
              type = lib.types.str;
              default = "https://github.com/${config.owner}/${config.repository.name}.git";
              defaultText = lib.literalExpression ''"https://github.com/''${owner}/''${repository.name}.git"'';
              description = "Adres klonu git (install-system).";
            };
            path = strOption "Lokalny klon na każdym hoście (update-local, claude-nixos, install-system).";
          };

          users = {
            laptop = strOption "Główne konto laptopa (jego customBot.defaultUser).";
            default = strOption "Główne konto pozostałych hostów (domyślne customBot.defaultUser).";
            matrix = strOption "Konto Matrix (@<nazwa>:<domena>), jedyne, któremu odpowiada Hermes.";
          };

          locale = {
            timeZone = strOption "Strefa czasowa (time.timeZone).";
            defaultLocale = strOption "Locale systemu (i18n.defaultLocale).";
            keyMap = strOption "Układ klawiatury w konsoli (console.keyMap).";
            xkbLayout = strOption "Układ klawiatury w sesji graficznej (services.xserver.xkb.layout).";
            wifiRegdom = strOption "Domena regulacyjna Wi-Fi (cfg80211.ieee80211_regdom).";
          };

          lan = {
            subnet = strOption ''
              Domowy LAN: SSH laptopa i RPi tylko z tej podsieci, fail2ban na
              RPi jej nie banuje.
            '';
            laptop = strOption ''
              Adres, pod którym RPi łączy się z laptopem (`ssh laptop`; RPi nie
              ma mDNS) — po zmianie w routerze popraw go w modules/args.nix.
            '';
          };

          nixConfig = lib.mkOption {
            type = lib.types.attrsOf (lib.types.listOf lib.types.str);
            description = ''
              nixConfig z flake.nix, jedyna lista cache (literał: nix czyta go
              przed ewaluacją); hosty biorą z niej nix.settings (base-nix),
              a cachix swój klucz.
            '';
          };

          cachix = {
            name = strOption "Własny cache: alias `push` i CI (cachix-action).";
            url = lib.mkOption {
              type = lib.types.str;
              default = "https://${config.cachix.name}.cachix.org";
              defaultText = lib.literalExpression ''"https://''${cachix.name}.cachix.org"'';
              description = "Adres własnego cache.";
            };
            pubKey = lib.mkOption {
              type = lib.types.str;
              default =
                lib.findFirst (lib.hasPrefix "${config.cachix.name}.cachix.org-1:")
                  (throw "options.nix: brak klucza ${config.cachix.name}.cachix.org w nixConfig (flake.nix)")
                  config.nixConfig.extra-trusted-public-keys;
              defaultText = lib.literalExpression ''lib.findFirst (lib.hasPrefix "''${cachix.name}.cachix.org-1:") (throw "…") nixConfig.extra-trusted-public-keys'';
              description = "Klucz publiczny własnego cache.";
            };
          };

          secretsDir = lib.mkOption {
            type = lib.types.path;
            description = ''
              Katalog plików .age. Literał ścieżki, nie `self + "/modules/_secrets"`:
              string ze ścieżką do źródła flake'a niesie kontekst całego repo,
              więc każdy commit zmieniałby toplevel wszystkich hostów. Ścieżka
              kopiuje do store tylko użyty plik.
            '';
          };
          keys = lib.mkOption {
            type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
            description = "Klucze publiczne (odbiorcy agenix, authorized_keys, known_hosts) z modules/_secrets/keys.nix.";
          };
        };
      }
    );
  };
}
