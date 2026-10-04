# nixos-iso — bootowalny instalator (USB/DVD ISO) dla hosta `nixos`, oparty na
# stockowym installerze NixOS (installation-cd-minimal.nix: NetworkManager +
# wpa_supplicant, sshd, root bez hasła na konsoli — jak każdy oficjalny ISO).
# Dodatki względem stocka:
#   - flakes włączone od razu (bez --extra-experimental-features);
#   - wbudowany `install-system` W WARIANCIE OFFLINE (install.nix) — po
#     zalogowaniu wystarczy `install-system [--disk URZĄDZENIE]`, BEZ SIECI:
#     toplevel hosta nixos, skrypt disko i źródła flake'a (self) są w
#     domknięciu install-system-offline, więc przez environment.systemPackages
#     trafiają do squashfs ISO.
# Koszt: ISO zawiera CAŁE domknięcie hosta nixos (kernel CachyOS LTO, KDE,
# gaming, NVIDIA, CUDA...) — build trwa jak build samego hosta, a ISO ma
# rozmiar skompresowanego systemu (patrz github-actions.nix: tags = false,
# tylko PR/dispatch, jak przy `nixos`). Lokalnie najtaniej na laptopie, gdzie
# domknięcie już jest w store.
#
# Build:  nix build .#packages.x86_64-linux.nixos-iso
# Wynik:  result/iso/*.iso — nagraj na USB (dd/ventoy) albo wypal na DVD.
#         ISO nie jest podpisane: Secure Boot w BIOS musi być wyłączony.
{ self, inputs, ... }:
{
  flake.modules.nixos.nixos-iso =
    { lib, ... }:
    {
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

  perSystem = _: {
    packages.nixos-iso =
      let
        image = inputs.nixpkgs.lib.nixosSystem {
          modules = [
            { nixpkgs.hostPlatform = "x86_64-linux"; }
            self.modules.nixos.nixos-iso
          ];
        };
      in
      image.config.system.build.isoImage;
  };
}
