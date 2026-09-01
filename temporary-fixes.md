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
  wywalając `system-path` i cały toplevel.
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

- **Pin `hermes-agent` `3f2a389c`** — zdjęty; upstream naprawił broken
  import `@hermes/shared/charge-settlement` (`topup.ts` → `nix/tui.nix`),
  flake znowu śledzi upstream (komentarz w `flake.nix`).
