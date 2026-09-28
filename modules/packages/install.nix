{ customTop, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      packages.install-system = pkgs.writeShellApplication {
        name = "install-system";
        runtimeInputs = [ pkgs.git ];
        text = ''
          flake="${customTop.repository.linkFlake}#nixos"
          # Dysk docelowy z konfiguracji disko (ścieżka /dev/disk/by-id).
          disk="$(nix eval --raw "${customTop.repository.linkFlake}#nixosConfigurations.nixos.config.disko.devices.disk.main.device")"

          echo "UWAGA: install-system SKASUJE CAŁY dysk $disk ($(readlink -f "$disk" 2>/dev/null || echo 'brak urządzenia'))."
          read -r -p "Wpisz dokładnie 'SKASUJ' aby kontynuować: " answer
          if [[ "$answer" != "SKASUJ" ]]; then
            echo "Przerwano." >&2
            exit 1
          fi

          sudo ${lib.getExe pkgs.disko} --mode destroy,format,mount --flake "$flake"
          sudo mkdir -p /mnt/etc/nixos
          sudo git clone ${customTop.repository.url} /mnt/etc/nixos
          sudo ${pkgs.nixos-install-tools}/bin/nixos-install --flake /mnt/etc/nixos#nixos --no-root-passwd
        '';
      };
    };
}
