{ self, inputs, ... }:
{
  flake.nixosModules.base =
    { ... }:
    {
      imports = [
        self.nixosModules.configuration
        self.nixosModules.shell
        self.nixosModules.git-home
        self.nixosModules.shell

        inputs.home-manager.nixosModules.default
        self.nixosModules.home
      ];
    };

}
