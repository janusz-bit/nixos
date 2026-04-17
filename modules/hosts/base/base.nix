{ self, inputs, ... }:
{
  flake.nixosModules."base" =
    { ... }:
    {
      imports = [
        self.nixosModules."base/configuration"
        self.nixosModules."base/shell"
        self.nixosModules."base/git"
        self.nixosModules."nix/settings"
        self.nixosModules."base/ssh"
        self.nixosModules."base/agenix"
        self.nixosModules."options"
      ];
    };

}
