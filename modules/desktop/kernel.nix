# Kernel CachyOS (https://github.com/xddxdd/nix-cachyos-kernel, gałąź
# release): BORE + LTO, wariant x86-64-v3 — wymaga procesora z AVX2
# (Haswell lub nowszy; i5-13450HX laptopa wspiera v3, nie avx512).
# overlays.pinned = ten sam nixpkgs, którym Hydra autora buduje kernele, więc
# kernel przychodzi z cache attic.xuyh0120.win/lantian (nixConfig we
# flake.nix) zamiast kompilować się lokalnie po każdym bumpie naszego
# nixpkgs. Strojenie pod ten kernel: desktop/tuning.nix.
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
