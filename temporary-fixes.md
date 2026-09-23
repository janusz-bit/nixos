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

### 1. `python-docs-fix` — pin docutils 0.21.2 + sphinx 8.2.3 w docs-builderze cpythona

- **Od:** 2026-09-01 (commit `79d96fa`)
- **Pliki:** `modules/overlays/python-docs-fix.nix` + wpis
  `self.overlays.python-docs-fix` w `nixpkgs.overlays`
  (`modules/hosts/raspberry-pi-4/configuration.nix`)
- **Objaw:** budowa `python3.11-3.11.16-doc` (ciągnięta przez
  `documentation.doc.enable = true` + `python311` w `systemPackages` →
  `system-path`) kończy się:
  `TypeError: int() argument must be a string, a bytes-like object or a
  real number, not 'NoneType'` w
  `docutils/parsers/rst/states.py` (`parse_enumerator`), przy okazji
  wywalając `system-path` i cały toplevel. Od nixpkgs `20b1ddd1aa5a`
  (sphinx 9.1.0 + patch `fix-test-stemmer`) dodatkowo: patch ten nie
  pasuje do 8.2.3 (hunk#2: kontekst `findthisstemmedkey` vs
  `findthisstemmedkei` w 8.2.3) — overlay czyści `patches = []` przy
  downgradzie sphinx.
- **Przyczyna:** docs-builder cpythona buduje dokumentację przez
  `pkgsBuildBuild.python3` (3.14 + sphinx 9.1 + **docutils 0.23**); regresja
  w docutils ≥ 0.22 przy enumerowanych listach RST. Upstream:
  <https://github.com/NixOS/nixpkgs/issues/499166> (stan na 2026-09-01: otwarte).
- **Obejście:** overlay podmienia środowisko budujące `passthru.doc` na
  python3.14 z docutils 0.21.2 + sphinx 8.2.3. Interpreter python3.11 i
  reszta systemu zostają na normalnych wersjach. Zweryfikowane lokalnie:
  pełny build docs przechodzi; dry-run toplevela buduje wyłącznie
  docutils/sphinx/hook/theme + `python3.11-3.11.16-doc`.
- **Kiedy usunąć:** gdy #499166 zostanie zamknięte albo zwykłe
  `nix build nixpkgs#python311.doc` zbuduje się bez overlaya.
- **Jak usunąć:** skasować `modules/overlays/python-docs-fix.nix`, wywalić
  `self.overlays.python-docs-fix` z `nixpkgs.overlays` w konfiguracji
  raspberry-pi-4, odpalić testowy build docs, potem `update-boot`.

### 1b. `droid` — poprawiony `arm64-balloon.patch` dla kernela 6.1.188

- **Od:** 2026-09-24 (ten commit)
- **Pliki:** `modules/hosts/droid-android/_kernel-patches.nix`,
  `modules/hosts/droid-android/arm64-balloon-6.1.188.patch`,
  `modules/hosts/droid-android/virtual-cpufreq.patch`
- **Objaw:** CI (tag v507, workflow `droid`) pada na
  `linux-config-6.1.188.drv` — GNU patch przy `arm64-balloon.patch` z avf
  wykrywa `Reversed (or previously applied) patch detected!`, pomija hunk
  (`1 out of 1 hunk ignored`, `*.rej`) i build kernela pada.
- **Przyczyna:** `flake.lock` update (6fb67a5) przesunął nixpkgs na
  `20b1ddd1aa5a` (linux 6.1.187 → 6.1.188). Stable patch 6.1.188 wstawił blok
  „disable indirect descriptors" (komentarz +
  `__virtio_clear_bit(VIRTIO_RING_F_INDIRECT_DESC)`) między
  `__virtio_clear_bit(vdev, VIRTIO_BALLOON_F_REPORTING)` a
  `__virtio_clear_bit(vdev, VIRTIO_F_ACCESS_PLATFORM)` w
  `virtballoon_validate`. Ostatni hunk avf patcha (usunięcie
  `ACCESS_PLATFORM`) zakładał stary kontekst — patch nie znajduje go z
  fuzz=2, a odwrotny match (kontekst `pusta linia` + `/*` występuje w pliku)
  wyzwala fałszywe „Reversed (or previously applied)".
- **Obejście:** `boot.kernelPatches = lib.mkForce` w droid-android z
  poprawionym patchem (hunk przesunięty za blok indirect-desc —
  zweryfikowany na vanilla 6.1.188: `nix build …kernel.configfile`
  przechodzi, `VIRTIO_F_ACCESS_PLATFORM` usunięte, `SND_VIRTIO=m`,
  `ANDROID_V_CPUFREQ_VIRT=y`, `IKCONFIG(_PROC)=y`) + cpufreq patch lokalnie
  (bez fetchgit w ewaluacji opcji). `structuredExtraConfig` 1:1 z avf.
- **Kiedy usunąć:** gdy nixos-avf naprawi patch (sprawdzać przy podbijaniu
  `avf` inputu); wtedy usunąć `_kernel-patches.nix` i wpis w
  `droid-android/default.nix` — moduł avf wróci do własnych patchy.

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

- **`trilium-server` `overrideAttrs` (better-sqlite3 prebuilds)** — zamknięte
  2026-09-11. nixpkgs ma już w `installPhase` delete-if-present
  (`rm -f .../prebuilds/linuxmusl-*.node`), więc lokalne nadpisanie
  w `modules/hosts/raspberry-pi-4/trilium.nix` zostało usunięte
  (`services.trilium-server.package` wraca do domyślnego z nixpkgs).


- **Pin `hermes-agent` `3f2a389c`** — zdjęty; upstream naprawił broken
  import `@hermes/shared/charge-settlement` (`topup.ts` → `nix/tui.nix`),
  flake znowu śledzi upstream (komentarz w `flake.nix`).
