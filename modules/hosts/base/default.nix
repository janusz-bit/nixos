{
  self,
  inputs,
  config,
  ...
}:
{
  flake.modules.nixos.base =
    { ... }:
    {
      imports = [
        self.modules.nixos.base-configuration
        self.modules.nixos.base-shell
        self.modules.nixos.base-git
        self.modules.nixos.nix-settings
        self.modules.nixos.base-ssh
        self.modules.nixos.base-agenix
        self.modules.nixos.base-opencode
        self.modules.nixos.options
        self.modules.nixos.customTop-options
      ];
    };
}
