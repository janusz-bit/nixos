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
        self.nixosModules.home
      ];
    };

}
