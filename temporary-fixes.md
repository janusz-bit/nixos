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

### 2. `PREEMPT_LAZY n` dla kernela RPi4 (`argsOverride`) — do usunięcia

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
- **Stan 2026-10-07:** warunek spełniony — nixos-hardware 06f9ecae
  (`raspberry-pi/common/kernel.nix`) wymusza `PREEMPT = mkForce yes`,
  `PREEMPT_LAZY = mkForce no`, a `raspberry-pi/4` sam ustawia
  `boot.kernelPackages`. Usunięcie zmienia jednak derywację jądra (lokalna
  kompilacja na RPi trwa godziny), więc zrobić to razem z najbliższym bumpem
  jądra: skasować blok `boot.kernelPackages` w `configuration.nix` i argument
  `inputs`, zbudować `nixosConfigurations.raspberry-pi-4` (najlepiej w CI
  `raspberry-pi-4`, które wypycha wynik do Cachix).

### 3. Runtime PM dGPU NVIDIA — reguła udev także na coldplug

- **Od:** 2026-09-29.
- **Plik:** `modules/hardware/LOQ-15IRX10.nix` (`services.udev.extraRules`).
- **Objaw:** `/sys/bus/pci/devices/0000:01:00.0/power/control` = `on`
  (domyślna wartość PCI), `runtime_status` stale `active` — RTX 5060 nigdy
  nie przechodzi w D3cold mimo `powerManagement.finegrained = true`.
- **Przyczyna:** reguły finegrained w nixpkgs
  (`nixos/modules/hardware/video/nvidia.nix`) ustawiają `auto` wyłącznie na
  `ACTION=="bind"`. Przy otwartych modułach nixpkgs ładuje `nvidia_uvm`
  z `boot.kernelModules` (systemd-modules-load), więc GPU może zostać
  zbindowane wcześniej, niż udev przetworzy zdarzenie; coldplug odtwarza
  potem tylko `add`, na które reguła nie reaguje (najbardziej prawdopodobne
  wyjaśnienie, niepotwierdzone logiem).
- **Obejście:** reguła jak `71-nvidia.rules` z CachyOS-Settings —
  `ACTION=="add|bind"` + `DRIVERS=="nvidia"`.
- **Kiedy usunąć:** gdy reguły w nixpkgs obejmą `add` (lub przestaną ładować
  `nvidia_uvm` przed udevem). Sprawdzenie: usunąć regułę, przebudować,
  po restarcie `cat .../power/control` musi dać `auto`.
- **Druga hipoteza (audyt 2026-10-07, niezweryfikowana na laptopie):** facter
  zapisał w `facter.json` sterownik `nvidia` i moduł graficzny facter dodaje go
  do `boot.initrd.kernelModules` (efektywnie `[btrfs dm_mod i915 nvidia]`).
  Bind następuje wtedy w initrd, którego udev nie ma `services.udev.extraRules`,
  a po switch-root coldplug odtwarza tylko `add`. Test:
  `hardware.facter.detected.boot.graphics.kernelModules = [ "i915" ]`,
  `update-local-boot`, restart, sprawdzić `power/control` z regułą i bez niej.

### 4. Kopia modułu NixOS hermes-agent (aktywacja bez zapisów roota)

- **Od:** 2026-10-07.
- **Pliki:** `modules/hosts/raspberry-pi-4/_hermes-agent/nixos-module.nix`
  (kopia `nix/nixosModules.nix` z NousResearch/hermes-agent @ 0a374d16, MIT),
  import w `modules/hosts/raspberry-pi-4/hermes.nix`, test
  `checks.<system>.hermes-activation`.
- **Przyczyna:** aktywacja upstreamu (przy każdym switch i boot) robi jako root
  `mkdir -p` + `chown`/`chmod` na `stateDir/{.hermes,home,workspace}` i
  podkatalogach, `install`/merge `config.yaml` i `.env` — w katalogach, których
  właścicielem jest agent (2770 hermes). Symlink podłożony przez agenta
  (np. `/var/lib/hermes/home -> /etc`) daje mu roota przy najbliższej
  aktywacji. Kontrola negatywna testu na module upstream: `/target-home`
  root → `hermes:hermes 750`.
- **Obejście:** root zakłada tylko `stateDir`; resztę aktywacji wykonuje
  `setpriv --reuid=hermes … --no-new-privs`. Tryb kontenerowy wyłączony asercją.
- **Kiedy usunąć:** gdy upstream przestanie pisać jako root w `stateDir`
  (zgłosić upstream). Do tego czasu przy każdym `nix flake update hermes-agent`
  nałożyć diff upstreamowego `nix/nixosModules.nix` na kopię (procedura
  w nagłówku pliku) i uruchomić `hermes-activation`.

### 5. hermes-agent — kasowanie `gateway.lock`/`gateway.pid`/`gateway_state.json`

- **Od:** przed 2026-10 (wcześniej bez wpisu).
- **Plik:** `modules/hosts/raspberry-pi-4/hermes.nix` (`ExecStartPre`, jako
  użytkownik usługi).
- **Przyczyna:** pliki blokady/stanu pozostałe po przerwanym procesie albo
  utworzone przez sesję interaktywną blokowały start bramki (PermissionError).
- **Kiedy usunąć:** gdy hermes sam wykrywa nieaktualne blokady (pid nie żyje)
  — sprawdzić: usunąć `ExecStartPre`, `kill -9` bramki, Restart musi wstać.

### 6. ISO — `image.baseName = lib.mkForce`

- **Od:** przed 2026-10 (wcześniej bez wpisu).
- **Plik:** `modules/installer/iso.nix`.
- **Przyczyna:** legacy `isoImage.isoBaseName` i domyślne `image.baseName`
  w `iso-image.nix` lądują na tym samym priorytecie („conflicting definition
  values”).
- **Kiedy usunąć:** gdy nixpkgs usunie alias `isoBaseName` albo rozdzieli
  priorytety — sprawdzić: ustawić `isoImage.isoBaseName` bez `mkForce`,
  `nix eval .#packages.x86_64-linux.nixos-iso.drvPath`.

### 7. Obraz SD — `boot.initrd.allowMissingModules = true`

- **Od:** przed 2026-10; 2026-10-07 przeniesione z hosta do `rpi-sdImage`.
- **Plik:** `modules/hosts/raspberry-pi-4/sdImage.nix`.
- **Przyczyna:** `sd-image-aarch64.nix` włącza `hardware.enableAllHardware`
  (m.in. `dw-hdmi`), a jądro RPi tych modułów nie ma. Na hoście flaga tylko
  ukrywała brak sterownika dysku root w initrd.
- **Kiedy usunąć:** gdy `all-hardware.nix` przestanie wymagać modułów spoza
  jądra RPi — sprawdzić: usunąć flagę, `nix build .#raspberry-pi-4-sd-image`.

## Zamknięte

- **NVIDIA open 615.71.09 — `--replace-fail` → `--replace-warn` w `postPatch`
  (`modules/hardware/LOQ-15IRX10.nix`)** — zamknięte 2026-10-07. Warunek
  usunięcia spełniony: nix-cachyos-kernel b1332396 używa już
  `substituteInPlace … --replace-quiet`, więc zamiana niczego nie dopasowywała —
  `drvPath` `hardware.nvidia.package.open` z override i bez był identyczny
  (`yiawrgcs…-nvidia-open-615.71.09-7.2.8.drv`). Override usunięty; przy okazji
  nie maskuje już po cichu przyszłych `--replace-fail`.

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
