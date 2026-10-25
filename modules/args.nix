# Wartości customTop: stałe tego repozytorium i jego właściciela, wspólne
# dla wszystkich hostów (deklaracja z typami i opisami: modules/options.nix).
# Literałów stąd nie powiela się w modułach; czytają je z `config.customTop`.
#
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
# Sprawdzenie: `nix eval --json .#nixosConfigurations.wsl.config.customTop.lan`
# oraz `nix eval --json .#nixosConfigurations.wsl.config.nix.settings.extra-substituters`
# (ta sama lista co nixConfig we flake.nix).
{
  config.customTop = {
    owner = "janusz-bit";
    email = "janusz-bit@proton.me";
    domain = "janusz-bit.com";
    repository = {
      name = "nixos";
      path = "/etc/nixos";
    };
    users = {
      laptop = "dinosaur";
      default = "nixos";
      matrix = "janusz";
    };
    locale = {
      timeZone = "Europe/Warsaw";
      defaultLocale = "pl_PL.UTF-8";
      keyMap = "pl2";
      xkbLayout = "pl";
      wifiRegdom = "PL";
    };
    lan = {
      subnet = "192.168.100.0/24";
      laptop = "192.168.100.14";
    };
    inherit (import ../flake.nix) nixConfig;
    cachix.name = "janusz-bit";
    secretsDir = ./_secrets;
    keys = import ./_secrets/keys.nix;
  };
}
