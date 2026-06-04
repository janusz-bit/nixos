{ ... }:
{
  flake.modules.nixos.nixos-appimage-run = {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
