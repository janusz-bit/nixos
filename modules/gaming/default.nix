# Gry na stacji roboczej: Steam z Protonem, GameMode, launchery i wrappery
# per gra. Proton-CachyOS jest w wariancie x86-64-v3 (procesor z AVX2).
{ self, ... }:
{
  flake.modules.nixos.gaming = {
    imports = [
      self.modules.nixos.gaming-steam
      self.modules.nixos.gaming-gamemode
      self.modules.nixos.gaming-launchers
      self.modules.nixos.gaming-dbd
      self.modules.nixos.gaming-deadlock
    ];
  };
}
