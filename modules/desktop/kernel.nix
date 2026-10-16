# Kernel CachyOS (https://github.com/xddxdd/nix-cachyos-kernel, gałąź
# release): BORE + LTO, wariant x86-64-v3 — wymaga procesora z AVX2
# (Haswell lub nowszy; i5-13450HX laptopa wspiera v3, nie avx512).
# overlays.pinned buduje kernel nixpkgs-em inputu, więc przebudowuje się
# tylko po bumpie nix-cachyos-kernel, a nie po każdym bumpie naszego nixpkgs.
# Żaden cache go nie ma: nowy kernel kompiluje się lokalnie (długo) albo
# w CI cachyos-kernel-update, które wypycha go do własnego cachix.
# Strojenie pod ten kernel: desktop/tuning.nix.
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
