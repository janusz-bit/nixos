{ lib, ... }:
{
  _module.args.customTop = rec {
    repository = {
      name = "nixos";
      site = "github";
      user = "janusz-bit";
      linkFlake = "${repository.site}:${repository.user}/${repository.name}";
      url = "https://${repository.site}.com/${repository.user}/${repository.name}.git";
      place = "/etc/nixos";
    };
    email.full = "janusz-bit@proton.me";
    site = rec {
      name = "janusz-bit";
      end = "com";
      full = name + "." + end;
    };
    # Domowa sieć LAN (laptop: enp8s0 192.168.100.14, RPi: 192.168.100.x).
    # SSH laptopa jest otwarte tylko z tej podsieci; fail2ban na RPi jej nie banuje.
    # lan.laptop: adres, pod którym RPi łączy się z laptopem (`ssh laptop`,
    # remote-agent.nix); RPi nie ma mDNS. Zmiana adresu w routerze → popraw tutaj.
    lan = {
      subnet = "192.168.100.0/24";
      laptop = "192.168.100.14";
    };
    # Cache binarne: jedyną listą jest nixConfig we flake.nix (musi być tam
    # literałem — nix czyta go przed ewaluacją). nix.settings hostów (base)
    # bierze z niego te same listy, więc nie ma drugiej kopii do pilnowania.
    inherit (import ../flake.nix) nixConfig;
    # Własny cache: alias `push` i CI (cachix-action).
    cache.cachix = rec {
      name = "janusz-bit";
      url = "https://${name}.cachix.org";
      pubKey =
        lib.findFirst (lib.hasPrefix "${name}.cachix.org-1:")
          (throw "args.nix: brak klucza ${url} w nixConfig (flake.nix)")
          nixConfig.extra-trusted-public-keys;
    };
    # Literał ścieżki, nie `self + "/modules/_secrets"`: string ze ścieżką do
    # źródła flake'a niesie kontekst CAŁEGO repo, więc każdy commit (nawet
    # komentarz) zmieniał toplevel wszystkich hostów. Ścieżka kopiuje do store
    # tylko używany plik (`<hash>-<nazwa>.age`, adres zależny od treści).
    secretsDir = ./_secrets;
    # Klucze publiczne (odbiorcy agenix, authorized_keys, known_hosts).
    keys = import ./_secrets/keys.nix;
  };
}
