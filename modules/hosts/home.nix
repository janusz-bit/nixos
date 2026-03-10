{ self, inputs, ... }:
{
  flake = {
    nixosModules.home =
      { ... }:
      {
        home-manager.backupFileExtension = "backup";
        imports = [
          inputs.home-manager.nixosModules.default
        ];
      };
  };
}
