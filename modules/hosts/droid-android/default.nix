{
  inputs,
  self,
  config,
  ...
}:
{
  flake.modules.nixos.droid-stateVersion = _: {
    system.stateVersion = "26.05";
  };

  flake.nixosConfigurations.droid = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      self.modules.nixos.base
      inputs.avf.nixosModules.avf
      self.modules.nixos.droid-stateVersion
      (
        { lib, pkgs, ... }:
        {
          customBot.flakeTarget = "droid";
          customBot.enableFastfetch = false;
          customBot.defaultUser = "droid";

          environment.systemPackages = with pkgs; [
            ollama
          ];

          programs.bash.interactiveShellInit = lib.mkBefore ''
            # Fix for bogus screen size on Android/AVF
            if [ "$COLUMNS" = "131072" ] || [ "$COLUMNS" = "0" ] || [ -z "$COLUMNS" ]; then
              export COLUMNS=80
              export LINES=24
              stty cols 80 rows 24 2>/dev/null || true
            fi
          '';
        }
      )
    ];
  };
}
