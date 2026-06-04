{ self, inputs, ... }:
{
  _module.args.customTop = rec {
    enableOpenWebUi = false;
    repository = {
      name = "nixos";
      site = "github";
      user = "janusz-bit";
      linkFlake = "${repository.site}" + ":" + "${repository.user}" + "/" + "${repository.name}";
      url = "https://${repository.site}.com/${repository.user}/${repository.name}.git";
      place = "/etc/nixos";
    };
    email.full = "janusz-bit@proton.me";
    site = rec {
      name = "janusz-bit";
      end = "com";
      full = name + "." + end;
    };
    cache = rec {
      cachix = rec {
        name = "janusz-bit";
        url = "https://${name}.cachix.org";
        pubKey = "${name}.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=";
      };
    };
    secretsDir = self + "/modules/_secrets";
  };
}
