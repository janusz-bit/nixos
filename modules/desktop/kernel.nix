# Kernel CachyOS (nix-cachyos-kernel, gałąź release): BORE + LTO, wariant
# x86-64-v3 (procesor z AVX2). overlays.pinned buduje go nixpkgs-em inputu,
# więc przebudowuje się tylko po bumpie nix-cachyos-kernel. Poza własnym
# cachix żaden cache go nie ma: kompiluje się lokalnie albo w CI
# cachyos-kernel-update, które go tam wypycha.
#
# Bez planisty sched_ext (scx_loader), bo nie był lepszy od BORE: w VM z tym
# kernelem (4 vCPU, zadanie 60 Hz z 5 ms CPU na klatkę obok 8 wątków
# stress-ng --cpu, po 2 przebiegi, 2026-11-28) wybudzenie p99 przy BORE
# wynosiło 0,08–0,16 ms (jeden przebieg zaszumiony przez hosta: 2,7 ms), przy
# scx_lavd 4,6–5,7 ms (z --performance do 34 pominiętych klatek na 900),
# przy scx_bpfland i scx_cosmos 1,3–1,8 ms. VM nie ma rdzeni P/E, pod które
# lavd jest strojony, więc A/B w grze tylko na hoście:
# `sudo "$(nix build --no-link --print-out-paths nixpkgs#scx.rustscheds)/bin/scx_lavd"`
# (Ctrl+C wraca do BORE).
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
