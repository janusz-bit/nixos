# Kernel CachyOS (nix-cachyos-kernel, gałąź release): BORE + LTO, wariant
# x86-64-v3 (procesor z AVX2). overlays.pinned buduje go nixpkgs-em inputu,
# więc przebudowuje się tylko po bumpie nix-cachyos-kernel; żaden cache go nie
# ma (kompilacja lokalnie albo w CI cachyos-kernel-update).
# Sprawdzenie: `uname -r` kończy się na -cachyos.
{ inputs, ... }:
let
  cachyosNixpkgs = inputs.nix-cachyos-kernel.inputs.nixpkgs.legacyPackages;
in
{
  flake.modules.nixos.desktop-kernel =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [
        inputs.nix-cachyos-kernel.overlays.pinned
        # Tymczasowe (temporary-fixes.md nr 10): nasze aggregateModules wymaga
        # modules.cer i *.ko.cer (nixpkgs 6bd7526), których kernel i nvidia
        # z overlays.pinned nie mają; drzewo składa nixpkgs, które je zbudowało.
        (final: _: { inherit (cachyosNixpkgs.${final.stdenv.hostPlatform.system}) aggregateModules; })
      ];
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
    };
}
