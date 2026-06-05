{ self, lib, ... }:

let
  # Single source of truth for the customTop schema and computed defaults.
  customTopSubmodule = lib.types.submodule (
    { config, ... }:
    {
      options = {
        enableOpenWebUi = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        repository = lib.mkOption {
          type = lib.types.submodule (
            { config, ... }:
            {
              options = {
                name = lib.mkOption {
                  type = lib.types.singleLineStr;
                  default = "nixos";
                };
                site = lib.mkOption {
                  type = lib.types.singleLineStr;
                  default = "github";
                };
                user = lib.mkOption {
                  type = lib.types.singleLineStr;
                  default = "janusz-bit";
                };
                linkFlake = lib.mkOption {
                  type = lib.types.singleLineStr;
                };
                url = lib.mkOption {
                  type = lib.types.singleLineStr;
                };
                place = lib.mkOption {
                  type = lib.types.singleLineStr;
                  default = "/etc/nixos";
                };
              };

              config = {
                linkFlake = "${config.site}:${config.user}/${config.name}";
                url = "https://${config.site}.com/${config.user}/${config.name}.git";
              };
            }
          );
          default = { };
        };

        email = lib.mkOption {
          type = lib.types.submodule {
            options = {
              full = lib.mkOption {
                type = lib.types.singleLineStr;
                default = "janusz-bit@proton.me";
              };
            };
          };
          default = { };
        };

        site = lib.mkOption {
          type = lib.types.submodule (
            { config, ... }:
            {
              options = {
                name = lib.mkOption {
                  type = lib.types.singleLineStr;
                  default = "janusz-bit";
                };
                end = lib.mkOption {
                  type = lib.types.singleLineStr;
                  default = "com";
                };
                full = lib.mkOption {
                  type = lib.types.singleLineStr;
                };
              };

              config = {
                full = "${config.name}.${config.end}";
              };
            }
          );
          default = { };
        };

        cache = lib.mkOption {
          type = lib.types.submodule {
            options = {
              cachix = lib.mkOption {
                type = lib.types.submodule (
                  { config, ... }:
                  {
                    options = {
                      name = lib.mkOption {
                        type = lib.types.singleLineStr;
                        default = "janusz-bit";
                      };
                      url = lib.mkOption {
                        type = lib.types.singleLineStr;
                      };
                      pubKey = lib.mkOption {
                        type = lib.types.singleLineStr;
                      };
                    };

                    config = {
                      url = "https://${config.name}.cachix.org";
                      pubKey = "${config.name}.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=";
                    };
                  }
                );
                default = { };
              };
            };
          };
          default = { };
        };

        secretsDir = lib.mkOption {
          type = lib.types.path;
          default = self + "/modules/_secrets";
        };
      };

      config = { };
    }
  );
in

{
  # --- NixOS module (for config.customTop inside nixosConfigurations) ---
  flake.modules.nixos.customTop-options =
    { ... }:
    {
      options.customTop = lib.mkOption {
        type = customTopSubmodule;
        default = { };
      };
    };

  # --- flake-parts perSystem option (for config.customTop inside perSystem) ---
  perSystem =
    { options, ... }:
    {
      options.customTop = lib.mkOption {
        type = customTopSubmodule;
        default = { };
      };
    };
}
