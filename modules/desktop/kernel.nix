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
      nixpkgs.overlays = [
        inputs.nix-cachyos-kernel.overlays.pinned
        # Od NixOS/nixpkgs 6bd7526 (2026-10-13) aggregateModules (drzewo
        # /lib/modules) wymaga modules.cer i *.ko.cer, które daje tylko kernel
        # zbudowany tym nixpkgs; kernel i nvidia z overlays.pinned ich nie mają,
        # więc linux-…-modules pada na `cp: cannot stat …/modules.cer`. Drzewo
        # składa nixpkgs, które zbudowało moduły (temporary-fixes.md, nr 10).
        (final: _: {
          inherit
            (inputs.nix-cachyos-kernel.inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system})
            aggregateModules
            ;
        })
      ];
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
    };
}
