{ self, ... }:
{
  flake.modules.nixos.base = _: {
    imports = [
      self.modules.nixos.base-configuration
      self.modules.nixos.base-shell
      self.modules.nixos.base-git
      self.modules.nixos.base-nix
      self.modules.nixos.base-rebuild
      self.modules.nixos.base-ssh
      self.modules.nixos.base-agenix
      self.modules.nixos.base-prime-agent
      self.modules.nixos.base-options
    ];
  };
}
