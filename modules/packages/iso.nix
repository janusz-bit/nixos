# nixos-iso — bootowalny instalator (USB/DVD ISO) dla hosta `nixos`, oparty na
# stockowym installerze NixOS (installation-cd-minimal.nix: NetworkManager +
# wpa_supplicant, sshd, root bez hasła na konsoli — jak każdy oficjalny ISO).
# Dodatki względem stocka:
#   - flakes włączone od razu (bez --extra-experimental-features);
#   - wbudowany `install-system` W WARIANCIE OFFLINE
#     (modules/packages/install-offline.nix) — po zalogowaniu wystarczy
#     `install-system [--disk URZĄDZENIE]`, BEZ SIECI: cały target system
#     (toplevel hosta nixos) i kopia repo (self) są już w tym ISO, bo
#     install-offline odwołuje się do nich w tekście skryptu — Nix dolicza
#     je do zależności tego pakietu, a przez environment.systemPackages
#     trafiają do squashfs ISO automatycznie (ten sam mechanizm, którym
#     ${self} i disko script już trafiały do ISO wcześniej).
# Koszt: ISO zawiera CAŁY closure hosta nixos (kernel CachyOS LTO, KDE,
# gaming, NVIDIA...) — build trwa podobnie długo jak build samego hosta
# (3-5 h) i ISO jest dużo większe niż stockowy installer (patrz
# github-actions.nix: tags = false, tylko PR/dispatch, jak przy `nixos`).
#
# Build:  nix build .#packages.x86_64-linux.nixos-iso
# Wynik:  result/iso/*.iso — nagraj na USB (dd/ventoy) albo wypal na DVD.
{ self, inputs, ... }:
{
  flake.modules.nixos.nixos-iso = { lib, ... }: {
    imports = [ "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

    # Nie isoImage.isoBaseName: nowy moduł image.nix w nixpkgs przekłada ten
    # legacy-alias na `image.baseName` RÓWNOLEGLE z własnym (edition-owym)
    # domyślnym przypisaniem w tym samym pliku (iso-image.nix) — oba na tym
    # samym priorytecie, więc "conflicting definition values". Nadpisujemy
    # wprost `image.baseName`, z mkForce, żeby wygrało bez konfliktu.
    image.baseName = lib.mkForce "nixos-installer";

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    environment.systemPackages = [ self.packages.x86_64-linux.install-system-offline ];

    services.getty.helpLine = ''

      === janusz-bit/nixos ===
      Zaloguj się jako root (bez hasła) i uruchom:

        install-system [--disk URZĄDZENIE]

      Instaluje host `nixos` (laptop LOQ-15IRX10) BEZ INTERNETU — system
      i repo są wbudowane w ten ISO. CAŁY wybrany dysk zostanie wyczyszczony.
      Bez --disk: wybór z listy (Enter = dysk skonfigurowany w disko.nix).
    '';
  };
}
