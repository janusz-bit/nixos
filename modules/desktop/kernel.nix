# Kernel CachyOS (nix-cachyos-kernel, gałąź release): BORE + LTO, wariant
# x86-64-v3 (procesor z AVX2). overlays.pinned buduje go nixpkgs-em inputu,
# więc przebudowuje się tylko po bumpie nix-cachyos-kernel. Poza własnym
# cachix żaden cache go nie ma: kompiluje się lokalnie albo w CI
# cachyos-kernel-update, które go tam wypycha.
#
# Sprawdzenie: `uname -r` kończy się na -cachyos.
{ inputs, ... }:
{
  flake.modules.nixos.desktop-kernel =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
    };
}
