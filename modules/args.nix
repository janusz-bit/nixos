# customTop: wszystko, co jest specyficzne dla tego repozytorium i jego
# właściciela (konto GitHub, e-mail, domena, konta użytkowników, język
# i strefa czasowa, domowy LAN, cache binarne, sekrety i klucze publiczne),
# podane jako argument każdego modułu flake-parts.
#
# To _module.args, nie opcje: wartości są te same na każdym hoście. Moduły
# NixOS biorą je z domknięcia pliku (`{ customTop, ... }:` na górze), nie
# z `config`; ustawienia zależne od hosta to opcje customBot
# (modules/hosts/base/options.nix). Literałów stąd nie powiela się w modułach.
# Wyjątki, które nix czyta bez ewaluacji: inputs i nixConfig we flake.nix
# oraz modules/_secrets/keys.nix (importuje go też agenix CLI).
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.wsl.config.nix.settings.extra-substituters`
# daje tę samą listę co nixConfig we flake.nix.
{ lib, ... }:
let
  owner = "janusz-bit";
  repositoryName = "nixos";
  cachixName = "janusz-bit";
  # Jedyna lista cache to nixConfig we flake.nix (literał — nix czyta go przed
  # ewaluacją); hosty biorą z niego te same listy (base-nix).
  inherit (import ../flake.nix) nixConfig;
in
{
  _module.args.customTop = {
    # Konto GitHub, zarazem autor commitów (git user.name).
    inherit owner nixConfig;
    email = "janusz-bit@proton.me";
    domain = "janusz-bit.com";

    repository = {
      name = repositoryName;
      flake = "github:${owner}/${repositoryName}";
      url = "https://github.com/${owner}/${repositoryName}.git";
      # Klon na każdym hoście (update-local, claude-nixos).
      place = "/etc/nixos";
    };

    users = {
      # customBot.defaultUser laptopa; pozostałe hosty mają domyślne konto.
      laptop = "dinosaur";
      default = "nixos";
      # Konto Matrix (@<nazwa>:<domena>), jedyne, któremu odpowiada Hermes.
      matrix = "janusz";
    };

    locale = {
      timeZone = "Europe/Warsaw";
      language = "pl_PL.UTF-8";
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
