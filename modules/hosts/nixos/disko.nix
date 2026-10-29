# Układ dysku laptopa (disko): ESP 6 GB, zaszyfrowany swap 36 GB pod
# hibernację (>= RAM) i LUKS + Btrfs z podwolumenami /, /home i /nix.
# install-system (modules/installer/install.nix) formatuje według niego
# dowolny wskazany dysk; system montuje partycje po etykietach
# by-partlabel/disk-main-*, więc `device` to tylko podpowiedź instalatora.
#
# Sprawdzenie: `lsblk -f`, `sudo btrfs subvolume list /`.
{ inputs, ... }:
let
  btrfsSubvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = [
      "compress=zstd"
      "noatime"
    ];
  };
in
{
  flake.modules.nixos.nixos-disko = _: {
    imports = [ inputs.disko.nixosModules.default ];

    # Hibernacja na zaszyfrowany swap z układu niżej (resumeDevice sam
    # dodaje parametr resume=).
    boot.resumeDevice = "/dev/mapper/swap";
    services.btrfs.autoScrub.enable = true;

    disko.devices.disk.main = {
      # Stabilna ścieżka: numeracja nvme0/nvme1 zmienia się między bootami, a
      # drugi dysk (Micron 1 TB) to Windows — install-system robi destroy.
      device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_4000GB_244363800090";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            start = "1M";
            end = "6G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          swap = {
            size = "36G";
            content = {
              type = "luks";
              name = "swap";
              settings.allowDiscards = true;
              content.type = "swap";
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypted";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = btrfsSubvolume "/";
                  "/home" = btrfsSubvolume "/home";
                  "/nix" = btrfsSubvolume "/nix";
                };
              };
            };
          };
        };
      };
    };
  };
}
