# Drukowanie przez CUPS; splix to sterownik drukarek Samsung (SPL).
_: {
  flake.modules.nixos.desktop-printing =
    { pkgs, ... }:
    {
      services.printing = {
        enable = true;
        drivers = [ pkgs.splix ];
      };
    };
}
