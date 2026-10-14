# Agregat base: wspólna podstawa importowana przez każdego hosta (narzędzia
# CLI i DNS, powłoka, git, Nix, aliasy update, SSH, Prime Agent, opcje
# customBot). Poza nim, importowane jawnie przez nixos i raspberry-pi-4:
# base-agenix (sekrety użytkownika i wrappery; WSL nie jest odbiorcą
# agenix), base-fail2ban i base-ssh-lan.
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
      self.modules.nixos.base-prime-agent
      self.modules.nixos.base-options
    ];
  };
}
