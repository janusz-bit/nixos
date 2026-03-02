{ self, inputs, ... }:
{
  flake = {
    nixosModules.wsl-home =
      { ... }:
      {
        imports = [
          self.nixosModules.git-home
        ];
        home-manager.backupFileExtension = "backup";
      };
  };
}
