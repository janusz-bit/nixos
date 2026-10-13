# Agregat base: wspólna podstawa importowana przez każdego hosta (narzędzia
# CLI i DNS, powłoka, git, Nix, aliasy update/push, SSH, agenix z sekretami
# użytkownika, Prime Agent, opcje customBot). base-fail2ban jest poza nim:
# importują go tylko nixos i raspberry-pi-4.
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
