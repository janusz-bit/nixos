{
  inputs,
  self,
  ...
}:
let
  # Pakiety lokalne — jedno źródło dla hostów (overlay) i dla
  # `packages.<system>` (nix build / nix-update w flake-update).
  localPackages = pkgs: {
    bootdev-cli = pkgs.callPackage ./_bootdev-cli { };
    waywallen = pkgs.callPackage ./_waywallen { };
    waywallen-kde-plugin = pkgs.callPackage ./_waywallen-kde-plugin { };
  };
in
{
  flake.overlays.local-packages =
    final: prev:
    let
      local = localPackages final;
    in
    local
    // {
      # Lokalny bootdev-cli (podbijany przez flake-update) tylko wtedy, gdy
      # jest nowszy niż w nixpkgs — przy tej samej wersji pakiet z nixpkgs
      # przychodzi z cache.nixos.org zamiast kompilować się lokalnie i w CI.
      bootdev-cli =
        if
          prev ? bootdev-cli && final.lib.versionAtLeast prev.bootdev-cli.version local.bootdev-cli.version
        then
          prev.bootdev-cli
        else
          local.bootdev-cli;
    };

  perSystem =
    { pkgs, ... }:
    {
      packages = localPackages pkgs // {
        raspberry-pi-4-sd-image =
          let
            image = inputs.nixpkgs.lib.nixosSystem {
              modules = [
                { nixpkgs.hostPlatform = "aarch64-linux"; }
                self.modules.nixos.raspberry-pi-4
                self.modules.nixos.rpi-sdImage
              ];
            };
          in
          image.config.system.build.sdImage;
      };
    };
}
