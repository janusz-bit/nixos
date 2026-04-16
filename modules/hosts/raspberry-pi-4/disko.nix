{ inputs, ... }:
{
  flake.nixosModules.raspberry-pi-4-disko =
    { lib, ... }:
    {
      imports = [ inputs.disko.nixosModules.default ];

      disko.enableConfig = true;

      disko.devices = {

        disk = {
          main = {
            type = "disk";
            device = "/dev/sda";
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  size = "1G";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    mountOptions = [ "umask=0077" ];
                    extraArgs = [
                      "-n"
                      "FIRMWARE"
                    ]; # Dla vfat używamy extraArgs by nadać label
                  };
                };
                root = {
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                  };
                };
              };
            };
          };
        };
      };
    };
}
