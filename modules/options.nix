{ self, inputs, ... }:
{
  flake.nixosModules.options =
    { lib, config, ... }:
    {
      options.custom.flakeTarget = lib.mkOption {
        type = lib.types.str;
        default = "default";
      };
      options.custom.enableFastfetch = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      options.custom.defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "nixos";
      };
    };
  _module.args.custom = rec {
    repository = {
      name = "nixos";
      site = "github";
      user = "janusz-bit";
      linkFlake = "${repository.site}" + ":" + "${repository.user}" + "/" + "${repository.name}";
      url = "https://${repository.site}.com/${repository.user}/${repository.name}.git";
      place = "/etc/nixos";
    };
    email.full = "janusz-bit@proton.me";
  };
}
