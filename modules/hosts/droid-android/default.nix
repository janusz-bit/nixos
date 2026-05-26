{ inputs, self, ... }:
{
  flake.nixosConfigurations.droid = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      self.nixosModules."base"
      inputs.avf.nixosModules.avf
      self.nixosModules."droid/stateVersion"
      (
        { lib, pkgs, ... }:
        {
          custom.flakeTarget = "droid";
          custom.enableFastfetch = false;
          custom.defaultUser = "droid";

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
