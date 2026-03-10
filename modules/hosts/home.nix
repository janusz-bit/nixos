{ self, inputs, ... }:
{
  flake = {
    nixosModules.home =
      { ... }:
      {
        home-manager.backupFileExtension = "backup";
      };
  };
}
