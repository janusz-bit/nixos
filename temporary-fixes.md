# Temporary fixes — tracker tymczasowych obejść

Ten plik śledzi **tymczasowe fixy** w repo: obejścia błędów upstream, które
trzeba wycofać, gdy nixpkgs / dany projekt naprawi usterkę. `update-boot`
robi `--refresh`, więc nixpkgs przesuwa się przy każdej aktualizacji —
przejrzyj tę listę przy większych bumpach i przed `nix-collect-garbage`.

## Zasady

- Dodając fix: dopisz wpis w „Aktywne" z **warunkiem usunięcia** i linkiem
  do issue upstream; w kodzie zostaw komentarz z odesłaniem do tej listy.
- Wycofując fix: przenieś wpis do „Zamknięte" (z datą) zamiast kasować
  bez śladu.

## Aktywne

### 1. NVIDIA open 615.71.09 — nieaktualny patch GPIO z nix-cachyos-kernel

- **Od:** 2026-09-28.
- **Plik:** `modules/hardware/LOQ-15IRX10.nix` (`hardware.nvidia.package`).
- **Objaw:** `nvidia-open-615.71.09-7.2.4` kończy `patchPhase` błędem
  `pattern static inline int __to_hwgpio(const struct gpio_device *gdev, doesn't match anything`.
- **Przyczyna:** [nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel/blob/444d135dde71c1de547cf7bfd73e67145e67aebb/kernel-cachyos/packages.nix#L27-L45)
  wymusza zamianę sygnatury z `const` na bez `const`; źródło
  [NVIDIA 615.71.09](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/61dcc93)
  ma już poprawną sygnaturę.
- **Obejście:** tylko dla otwartego modułu NVIDIA zamienić w `postPatch`
  `--replace-fail` na `--replace-warn`. Jeżeli starsze źródło zawiera `const`,
  zamiana nadal działa; przy obecnym źródle brak wzorca nie blokuje budowy.
- **Kiedy usunąć:** gdy `nix-cachyos-kernel` usunie zbędny patch lub doda
  sprawdzenie obecności starej sygnatury. Po aktualizacji inputu sprawdzić
  `postPatch` w derywacji `hardware.nvidia.package.open`, usunąć override
  i zbudować moduł ponownie.

### 2. `PREEMPT_LAZY n` dla kernela RPi4 (`argsOverride`)

- **Od:** patrz komentarz w `modules/hosts/raspberry-pi-4/configuration.nix`
- **Pliki:** `modules/hosts/raspberry-pi-4/configuration.nix`
  (`boot.kernelPackages`)
- **Przyczyna:** `common-config.nix` w nixpkgs ustawia `PREEMPT_LAZY=yes`
  dla kerneli ≥ 6.18, co koliduje z `PREEMPT=yes` kernela vendorowego RPi.
  `nixos-hardware` hardcoduje `kernelPatches` wewnątrz `buildLinux`, więc
  mechanizm `boot.kernelPatches` nie ma zastosowania — stąd `argsOverride`.
  Ref: nixpkgs `d79e72ee0533cd5ce021dcd8863599e9dd290a33`.
- **Kiedy usunąć:** gdy nixpkgs/nixos-hardware naprawi konflikt
  (sprawdzać przy podbijaniu kernela / `nixos-hardware`); objawem powrotu
  problemu byłoby konfliktowe Kconfig choice przy budowie kernela.

## Zamknięte

- **`python-docs-fix` (pin docutils/sphinx w docs-builderze cpythona,
  nixpkgs#499166)** — zamknięte 2026-09-28. Budowę `python3.11-doc` ciągnęło
  tylko `documentation.doc.enable = true` + `python311` w `systemPackages`
  raspberry-pi-4; headless serwer ma teraz `documentation.doc.enable = false`,
  więc overlay `modules/overlays/python-docs-fix.nix` usunięto (issue upstream
  nadal otwarte — przy ponownym włączeniu dokumentacji wróci błąd).

- **`droid` AVF kernel patch (6.1.188)** — zamknięte 2026-09-27. Po migracji
  `nixosConfigurations.droid` do `nixOnDroidConfigurations.droid` nie budujemy
  kernela Android VM. Usunięto `_kernel-patches.nix`,
  `arm64-balloon-6.1.188.patch` i `virtual-cpufreq.patch`.

- **`trilium-server` `overrideAttrs` (better-sqlite3 prebuilds)** — zamknięte
  2026-09-11. nixpkgs ma już w `installPhase` delete-if-present
  (`rm -f .../prebuilds/linuxmusl-*.node`), więc lokalne nadpisanie
  w `modules/hosts/raspberry-pi-4/trilium.nix` zostało usunięte
  (`services.trilium-server.package` wraca do domyślnego z nixpkgs).


- **Pin `hermes-agent` `3f2a389c`** — zdjęty; upstream naprawił broken
  import `@hermes/shared/charge-settlement` (`topup.ts` → `nix/tui.nix`),
  flake znowu śledzi upstream (komentarz w `flake.nix`).
