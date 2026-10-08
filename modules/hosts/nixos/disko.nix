{ inputs, ... }:
{
  flake.modules.nixos.disko = _: {
    imports = [ inputs.disko.nixosModules.default ];
    disko.devices = {
      disk = {
        main = {
          type = "disk";
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
                  settings = {
                    allowDiscards = true;
                  };
                  content = {
                    type = "swap";
                  };
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted";
                  settings = {
                    allowDiscards = true;
                  };
                  content = {
                    type = "btrfs";
                    extraArgs = [ "-f" ];
                    subvolumes = {
                      "/root" = {
                        mountpoint = "/";
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/home" = {
                        mountpoint = "/home";
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/nix" = {
                        mountpoint = "/nix";
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
