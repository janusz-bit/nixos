# customTop: wartości specyficzne dla tego repozytorium i jego właściciela
# (konto GitHub, e-mail, domena, konta użytkowników, język i strefa czasowa,
# domowy LAN, cache binarne, sekrety i klucze publiczne), podane jako argument
# każdego modułu flake-parts.
#
# To _module.args, nie opcje: wartości są te same na każdym hoście. Moduły
# NixOS biorą je z domknięcia pliku (`{ customTop, ... }:` na górze), nie
# z `config`; ustawienia zależne od hosta to opcje customBot
# (modules/hosts/base/options.nix). Literałów stąd nie powiela się w modułach.
# Wyjątki spoza customTop: inputs i nixConfig we flake.nix (nix czyta je przed
# ewaluacją, więc muszą być literałami) oraz modules/_secrets/keys.nix
# (samodzielne wyrażenie bez argumentów: importuje go secrets.nix dla agenix
# CLI, a `post-install ssh` podmienia w nim tekst kluczy).
#
# Fork: poza tym plikiem trzeba zmienić nixConfig i wejście brulion we
# flake.nix, _secrets/keys.nix i wszystkie pliki .age, MATRIX_HOME_ROOM
# (hosts/raspberry-pi-4/matrix.nix), tunel w cloudflared.nix, dysk i wpis
# Windows laptopa (hosts/nixos/disko.nix, boot.nix) oraz modules/hardware/.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.wsl.config.nix.settings.extra-substituters`
# daje tę samą listę co nixConfig we flake.nix.
{ lib, ... }:
let
  owner = "janusz-bit";
  repositoryName = "nixos";
  cachixName = "janusz-bit";
  inherit (import ../flake.nix) nixConfig;
in
{
  _module.args.customTop = {
    # Konto GitHub, zarazem autor commitów (git user.name).
    inherit owner;
    email = "janusz-bit@proton.me";
    # Strefa w Cloudflare: Nextcloud i server_name Matrixa pod samą domeną,
    # reszta usług RPi pod <usługa>.<domena> (cloudflared.nix).
    domain = "janusz-bit.com";

    repository = {
      name = repositoryName;
      flake = "github:${owner}/${repositoryName}";
      url = "https://github.com/${owner}/${repositoryName}.git";
      # Lokalny klon na każdym hoście (update-local, claude-nixos,
      # install-system).
      path = "/etc/nixos";
    };

    users = {
      # Główne konto hosta (customBot.defaultUser): laptop ma własne,
      # pozostałe hosty `default` (base/options.nix).
      laptop = "dinosaur";
      default = "nixos";
      # Konto Matrix (@<nazwa>:<domena>), jedyne, któremu odpowiada Hermes.
      matrix = "janusz";
    };

    locale = {
      timeZone = "Europe/Warsaw";
      defaultLocale = "pl_PL.UTF-8";
      keyMap = "pl2";
      xkbLayout = "pl";
      wifiRegdom = "PL";
    };

    # Domowy LAN: SSH laptopa i RPi tylko z tej podsieci, fail2ban na RPi jej
    # nie banuje. lan.laptop: adres, pod którym RPi łączy się z laptopem
    # (`ssh laptop`; RPi nie ma mDNS) — po zmianie w routerze popraw tutaj.
    lan = {
      subnet = "192.168.100.0/24";
      laptop = "192.168.100.14";
    };

    # Jedyna lista cache to nixConfig we flake.nix (literał: nix czyta go
    # przed ewaluacją); hosty biorą z niej nix.settings (base-nix), a cachix
    # niżej swój klucz.
    inherit nixConfig;

    # Własny cache: alias `push` i CI (cachix-action).
    cachix = {
      name = cachixName;
      url = "https://${cachixName}.cachix.org";
      pubKey =
        lib.findFirst (lib.hasPrefix "${cachixName}.cachix.org-1:")
          (throw "args.nix: brak klucza ${cachixName}.cachix.org w nixConfig (flake.nix)")
          nixConfig.extra-trusted-public-keys;
    };

    # Literał ścieżki, nie `self + "/modules/_secrets"`: string ze ścieżką do
    # źródła flake'a niesie kontekst CAŁEGO repo, więc każdy commit zmieniałby
    # toplevel wszystkich hostów. Ścieżka kopiuje do store tylko użyty plik.
    secretsDir = ./_secrets;
    # Klucze publiczne (odbiorcy agenix, authorized_keys, known_hosts).
    keys = import ./_secrets/keys.nix;
  };
}
