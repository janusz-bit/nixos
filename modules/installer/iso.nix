# nixos-iso — bootowalny instalator (USB/DVD ISO) hosta `nixos`: stockowy
# installation-cd-minimal.nix z włączonymi flakes i wbudowanym
# `install-system` w wariancie offline (install.nix), który instaluje bez
# sieci, bo toplevel hosta, skrypt disko i źródła flake'a są w jego domknięciu.
#
# Koszt: ISO zawiera całe domknięcie hosta nixos (kernel CachyOS, KDE, NVIDIA,
# CUDA...), więc build trwa jak build hosta (w CI tylko PR/dispatch,
# github-actions.nix); na laptopie, z domknięciem w store, ~20 min (squashfs
# zstd-19), ISO ~17 GB.
#
# Test (QEMU, OVMF, `-nic none`): instalacja na dysk inny niż w disko.nix;
# zainstalowany system uruchamiać z dyskiem `-device nvme` (initrd z facter
# nie ma virtio_blk). Jak oficjalny ISO: root bez hasła na konsoli, obraz
# niepodpisany (Secure Boot w BIOS musi być wyłączony).
#
# Build: `nix build .#packages.x86_64-linux.nixos-iso` → result/iso/*.iso
# (dd albo Ventoy na pendrive od 32 GB).
{
  self,
  inputs,
  ...
}:
{
  flake.modules.nixos.installer-iso =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        # config.customTop dla helpLine niżej.
        self.modules.nixos.base-options
      ];

      # mkForce: iso-image.nix ustawia image.baseName na zwykłym priorytecie,
      # a legacy isoImage.isoBaseName to tylko alias tej opcji, więc kolidowałby
      # tak samo („conflicting definition values”).
      image.baseName = lib.mkForce "nixos-installer";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      environment.systemPackages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.install-system-offline
      ];

      services.getty.helpLine = ''

        === ${config.customTop.owner}/${config.customTop.repository.name} ===
        Zaloguj się jako root (bez hasła) i uruchom:

          install-system [--disk URZĄDZENIE]

        Instaluje host `nixos` (laptop LOQ-15IRX10) BEZ INTERNETU — system
        i repo są wbudowane w ten ISO. CAŁY wybrany dysk zostanie wyczyszczony.
        Bez --disk: wybór z listy (Enter = dysk skonfigurowany w disko.nix).
      '';
    };

  perSystem = _: {
    packages.nixos-iso =
      (inputs.nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          self.modules.nixos.installer-iso
        ];
      }).config.system.build.isoImage;
  };
}
