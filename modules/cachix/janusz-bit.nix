{ self, inputs, ... }:
{
  flake.nixosModules.cachix-janusz-bit =
    { ... }:
    {
      nix = {
        settings = {
          substituters = [
            "https://janusz-bit.cachix.org"
          ];
          trusted-public-keys = [
            "janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo="
          ];
        };
      };
    };

}
