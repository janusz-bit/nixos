{ ... }:
{
  flake.nixosModules."nixos/appimage-run" = {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
