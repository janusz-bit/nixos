# nixos-iso — bootowalny instalator (USB/DVD ISO) dla hosta `nixos`, oparty na
# stockowym installerze NixOS (installation-cd-minimal.nix: NetworkManager +
# wpa_supplicant, sshd, root bez hasła na konsoli — jak każdy oficjalny ISO).
# Dodatki względem stocka:
#   - flakes włączone od razu (bez --extra-experimental-features);
#   - wbudowany `install-system` (modules/packages/install.nix) — po
#     zalogowaniu wystarczy `install-system [--disk URZĄDZENIE]`, bez
#     `nix run github:janusz-bit/nixos`.
# Sam install-system i tak klonuje repo z GitHuba (potrzebna sieć) i instaluje
# rewizję flake'a wbudowaną w ten ISO (self) — ISO tylko eliminuje ręczne
# wpisywanie `nix run` i flag flake'owych.
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

    environment.systemPackages = [ self.packages.x86_64-linux.install-system ];

    services.getty.helpLine = ''

      === janusz-bit/nixos ===
      Zaloguj się jako root (bez hasła) i uruchom:

        install-system [--disk URZĄDZENIE]

      Instaluje host `nixos` (laptop LOQ-15IRX10). CAŁY wybrany dysk
      zostanie wyczyszczony. Bez --disk: wybór z listy (Enter = dysk
      skonfigurowany w disko.nix).
    '';
  };
}
