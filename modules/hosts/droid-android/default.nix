{ inputs, ... }:
{
  # Nix-on-Droid runs inside the Android app, not as an AVF NixOS guest.
  flake.nixOnDroidConfigurations.droid = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "aarch64-linux";
      overlays = [ inputs.nix-on-droid.overlays.default ];
    };
    modules = [
      ./_nix-on-droid.nix
    ];
  };
}
