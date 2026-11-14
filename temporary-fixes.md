# Temporary fixes — tracker tymczasowych obejść

Ten plik śledzi **tymczasowe fixy** w repo: obejścia błędów upstream, które
trzeba wycofać, gdy nixpkgs / dany projekt naprawi usterkę. `update-boot`
robi `--refresh`, więc nixpkgs przesuwa się przy każdej aktualizacji —
przejrzyj tę listę przy większych bumpach i przed `nix-collect-garbage`.

## Zasady

- Dodając fix: dopisz wpis w „Aktywne” z **warunkiem usunięcia** i linkiem
  do issue upstream; w kodzie zostaw komentarz z odesłaniem do tej listy.
- Wycofując fix: przenieś wpis do „Zamknięte” (z datą) zamiast kasować
  bez śladu.

## Aktywne

### 1. Runtime PM dGPU NVIDIA — reguła udev także na coldplug

- **Od:** 2026-09-29.
- **Plik:** `modules/hardware/LOQ-15IRX10/default.nix` (`services.udev.extraRules`).
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

### 4. Zed — Vulkan tylko z ICD Intela (`VK_LOADER_DRIVERS_SELECT`)

- **Od:** 2026-10-10.
- **Plik:** `modules/desktop/dev.nix` (`zedIntelOnly`: `symlinkJoin`
  + `wrapProgram $out/bin/zeditor --set VK_LOADER_DRIVERS_SELECT 'intel_icd*'`).
- **Objaw:** `zeditor ~/projekt` zmienia
  `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` z `suspended` na
  `active` (zmierzone); pierwsze okno czeka na wybudzenie RTX 5060 z D3cold.
- **Przyczyna:** Zed (wgpu) tworzy instancję Vulkan przy starcie, a ICD
  NVIDII budzi dGPU już przy `vkCreateInstance`, choć Zed renderuje na iGPU
  (błąd NVIDII 4770124). `ZED_DEVICE_ID` i `VK_LOADER_DEVICE_ID_FILTER` działają
  dopiero po załadowaniu ICD, więc nie pomagają.
  https://forums.developer.nvidia.com/t/550-67-nvidia-vulkan-icd-wakes-up-dgpu-on-initialization-and-exit/288095 ,
  https://github.com/zed-industries/zed/issues/25320
- **Obejście:** loader filtruje manifesty po nazwie pliku przed `dlopen`;
  `intel_icd*` dopuszcza tylko `intel_icd.x86_64.json` (ANV), bez
  `intel_hasvk_icd`, `nvidia_icd.json` i pozostałych ICD Mesy. Tylko dla Zeda
  (Steam/gry/`GAMEMODERUNEXEC` potrzebują Vulkana NVIDII).
- **Ograniczenie:** zmienną dziedziczą procesy uruchamiane z Zeda (wbudowany
  terminal, taski, LSP) — gra albo `nvidia-offload` z terminala Zeda nie zobaczy
  Vulkana NVIDII. CUDA/ollama bez zmian (nie używają loadera Vulkan).
- **Kiedy usunąć:** gdy sterownik NVIDII przestanie budzić dGPU przy
  `vkCreateInstance`. Sprawdzenie: usunąć nakładkę (wrócić do `zed-editor`),
  przebudować, przy uśpionym dGPU uruchomić `zeditor ~/projekt; sleep 2;
  cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` — musi zostać
  `suspended`.

### 6. Deadlock, Dead by Daylight — DXVK bez `VK_NV_raw_access_chains` (Xid 109)

- **Od:** 2026-10-12.
- **Pliki:** `modules/gaming/deadlock.nix` (`deadlockrun`) i
  `modules/gaming/dbd.nix` (`dbdrun`, od 2026-10-12, zapobiegawczo: DBD
  z `-dx11` renderuje przez DXVK; zawiasu w DBD nie zaobserwowano) —
  `DXVK_CONFIG="dxvk.enableNvRawAccessChains=False"`.
- **Objaw:** na NVIDIA 610/615 (tu 615.71.09, RTX 5060) Deadlock w trybie DX11
  zawiesza się w walce: obraz stoi, dźwięk gra, w `journalctl -k`
  `NVRM: Xid … 109 … CTX SWITCH TIMEOUT`.
- **Przyczyna:** shadery DXVK z `VK_NV_raw_access_chains` przy nakładających
  się odczytach buforów. Fix w DXVK: PR 5958 (merge 081ee5c, 2026-10-10), nie
  ma go w proton-cachyos 11.0.20260703, którego używa gra (DXVK
  v3.0.2-2-g0ff9cd3, opcja domyślnie włączona), ani w Proton Experimental
  11.0-20261001 (DXVK v3.1.1-47-g68530156).
  https://github.com/doitsujin/dxvk/pull/5958 ,
  https://github.com/ValveSoftware/Proton/issues/8020
- **Kiedy usunąć:** gdy proton-cachyos ma DXVK zawierające 081ee5c
  (`cat "$(nix eval --raw .#nixosConfigurations.nixos.pkgs.proton-cachyos_x86_64_v3)"/files/lib/wine/dxvk/version`,
  potem `gh api repos/doitsujin/dxvk/compare/081ee5c...<hash>` musi dać
  `ahead`/`identical`). Wtedy `deadlockrun` = sam `gamemoderun`: usunąć
  moduł i w Launch Options wrócić do `gamemoderun %command%`; z `dbdrun`
  usunąć tylko `DXVK_CONFIG`.

### 7. Wentylator RPi — `RPI_LGPIO_REVISION` podane ręcznie

- **Od:** przed 2026-10 (przeniesione do tego rejestru 2026-10-14).
- **Plik:** `modules/hardware/raspberry-pi-4/fan.nix`
  (`environment.RPI_LGPIO_REVISION = "0xc03114"`, RPi 4B Rev 1.4).
- **Objaw:** bez zmiennej rpi-lgpio nie ustala modelu płytki i
  `GPIO.setup` pada, więc usługa `pwm-fan` nie startuje.
- **Przyczyna:** rpi-lgpio czyta rewizję z
  `/proc/device-tree/system/linux,revision` albo z pola `Revision`
  w `/proc/cpuinfo`; na kernelu 6.18 z nixos-hardware nie ma ani węzła
  `system/` w device tree, ani tego pola.
- **Kiedy usunąć:** gdy na RPi
  `ls /proc/device-tree/system/linux,revision` albo
  `grep '^Revision' /proc/cpuinfo` coś zwraca — wtedy zmienną usunąć
  i sprawdzić `systemctl status pwm-fan`.

### 8. Baloo — `QT_QPA_PLATFORM=offscreen` dla `kde-baloo.service`

- **Od:** 2026-10-20.
- **Plik:** `modules/desktop/plasma.nix` (`systemd.user.services.kde-baloo`).
- **Objaw:** po zalogowaniu `baloo_file_extractor` abortuje (SIGABRT,
  coredump) z `Failed to create wl_display (No such file or directory)` i
  `could not connect to display`; `baloo_file` loguje `Extractor crashed`.
- **Przyczyna:** `kde-baloo.service` startuje z `plasma-workspace.target`,
  zanim startplasma zaimportuje `WAYLAND_DISPLAY`/`DISPLAY` do
  `systemd --user`. `baloo_file` ma w `/proc/<pid>/environ` tylko
  `XDG_SESSION_TYPE=wayland` (bez obu zmiennych), a jego dzieci dziedziczą to
  środowisko. Qt bierze domyślny socket `wayland-0`, podczas gdy KWin tworzy
  `wayland-1`; fallback xcb nie ma `DISPLAY`. KDE bug 524392,
  https://invent.kde.org/frameworks/baloo/-/merge_requests/331 opóźnia start,
  ale na razie wpada w cykl kolejności jednostek.
- **Obejście:** drop-in `QT_QPA_PLATFORM=offscreen` — ekstraktor nie potrzebuje
  okna. Skutek uboczny: `KIdleTime` nie znajduje pollera, więc Baloo uznaje
  system za zajęty i indeksuje treść wolniej.
- **Kiedy usunąć:** gdy upstream opóźni start `kde-baloo.service` do czasu
  importu środowiska (baloo MR 331). Sprawdzenie: usunąć wpis, przebudować,
  po zalogowaniu `tr '\0' '\n' < /proc/$(pgrep -x baloo_file)/environ` musi
  zawierać `WAYLAND_DISPLAY` i `DISPLAY`, a
  `journalctl --user -u kde-baloo.service -b` nie może mieć `Extractor
  crashed`.

### 10. Kernel CachyOS — `aggregateModules` z nixpkgs inputu

- **Od:** 2026-10-22.
- **Plik:** `modules/desktop/kernel.nix` (drugi overlay w `nixpkgs.overlays`).
- **Objaw:** `update` na laptopie pada na
  `linux-cachyos-bore-lto-x86_64-v3-7.2.8-modules.drv` z
  `cp: cannot stat '…/lib/modules/7.2.8-cachyos-lto/modules.cer'`.
- **Przyczyna:** NixOS/nixpkgs 6bd7526 (2026-10-13) podpisuje moduły
  kmodigestem: kernel instaluje `modules.cer`, moduły zewnętrzne `*.ko.cer`, a
  `aggregateModules` bezwarunkowo je scala. `overlays.pinned` buduje kernel
  i nvidia nixpkgs-em inputu `nix-cachyos-kernel` (545c226, 2026-09-27), więc
  plików brak. Gałąź `release` stoi od 2026-09-28 (budowa 7.2.9 pada,
  xddxdd/nix-cachyos-kernel#108). Zgłoszenie:
  https://github.com/xddxdd/nix-cachyos-kernel/issues/111; brakujące `*.ko.cer`
  pakietów nixpkgs: https://github.com/NixOS/nixpkgs/issues/575192.
- **Obejście:** `aggregateModules` z nixpkgs inputu (tego, które zbudowało
  moduły) — drzewo jak przed bumpem, bez przebudowy kernela.
- **Kiedy usunąć:** gdy nixpkgs zablokowany przez `nix-cachyos-kernel` zawiera
  6bd7526 (kernel ma wtedy `modules.cer`) albo upstream naprawi #111.
  Sprawdzenie: `nix flake metadata --json | jq '.locks.nodes[.locks.nodes[.locks.nodes.root.inputs."nix-cachyos-kernel"].inputs.nixpkgs].locked.lastModified'`
  ≥ 1791856909 (2026-10-13), potem usunąć overlay i `nix build` toplevelu
  `nixos` musi przejść.

### 12. Nextcloud — PHP z inputu `nixpkgs-unstable-small` (PHP2Shell)

- **Od:** 2026-10-22.
- **Pliki:** `flake.nix` (input `nixpkgs-unstable-small` = `nixos-unstable-small`),
  `modules/hosts/raspberry-pi-4/nextcloud.nix` (`services.nextcloud.phpPackage`).
- **Objaw:** `phpfpm-nextcloud` działa na PHP 8.4.26, podatnym na PHP2Shell
  (CVE-2026-109618, CVE-2026-109619: nieuwierzytelnione RCE), a Nextcloud był
  wtedy wystawiony do internetu przez Cloudflare Tunnel (dziś tylko w
  tailnecie, gdzie odpowiada każdemu urządzeniu przed zalogowaniem).
- **Przyczyna:** poprawka (php 8.4.26 -> 8.4.27,
  https://github.com/NixOS/nixpkgs/pull/576853, merge c53532a938) jest w
  `nixos-unstable-small`, ale jeszcze nie w `nixos-unstable`, z którego
  przypięty jest główny `nixpkgs`.
- **Obejście:** `phpPackage = php84` z osobnego inputu; główny `nixpkgs`
  (i pozostałe hosty) bez zmian. Asercja w `nextcloud.nix` wymaga PHP ≥ 8.4.27.
- **Kiedy usunąć:** gdy przypięty `nixpkgs` ma `php84` ≥ 8.4.27. Sprawdzenie:
  `nix eval --raw .#nixosConfigurations.raspberry-pi-4.pkgs.php84.version`;
  potem usunąć `phpPackage` i, jeśli nic innego go nie używa, input
  `nixpkgs-unstable-small` (`nix flake lock`) — asercja zostaje.

### 13. Lutris — środowisko FHS bez `gtk2` (broken w nixpkgs)

- **Od:** 2026-11-02.
- **Plik:** `modules/gaming/launchers.nix` (`lutrisWithoutGtk2`).
- **Objaw:** `nixos-rebuild` kończy się `Refusing to evaluate package
  'gtk+-2.24.33' ... broken` (ślad: `man-db` → `lutris-fhsenv-rootfs`).
- **Przyczyna:** `pkgs/by-name/lu/lutris/package.nix` ma `gtk2` na sztywno
  w `multiPkgs`, a gtk2 jest oznaczone jako broken
  (https://github.com/NixOS/nixpkgs/issues/410814, usunięcie przed NixOS 27.05).
  Tego samego `gtk2` ciągnął `zulu8` w `prismlauncher`; `zulu8` usunięto z
  `jdks` (Minecraft sprzed 1.17 wymaga Javy 8 — dodać inne JDK 8, np.
  `temurin-bin-8`, jeśli będzie potrzebne).
- **Obejście:** `lutris.override` owija `buildFHSEnv` i odfiltrowuje z
  `multiPkgs` pakiety o `pname == "gtk+"`. Gry/instalatory wymagające 32-bitowego
  gtk2 przez Lutris mogą przestać działać.
- **Kiedy usunąć:** gdy nixpkgs usunie `gtk2` z `lutris` (lub zwykły
  `pkgs.lutris` znów się ewaluuje). Sprawdzenie: podmienić
  `lutrisWithoutGtk2` na `lutris` i `nix eval --raw
  .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath`.

### 14. Kernel RPi4 z nixos-raspberrypi — `kernelFile` i `deviceTree.enable` podane ręcznie

- **Od:** 2026-11-04.
- **Plik:** `modules/hardware/raspberry-pi-4/default.nix`
  (`system.boot.loader.kernelFile = "Image"`, `hardware.deviceTree.enable = true`).
- **Objaw:** bez nich ewaluacja `raspberry-pi-4` pada na
  `attribute 'buildDTBs' missing` i `attribute 'target' missing`.
- **Przyczyna:** kernel z cache nixos-raspberrypi jest zbudowany nixpkgs-em
  tego wejścia (`nixos-26.05`), którego `buildLinux` nie ma jeszcze passthru
  `target` i `buildDTBs`; nixpkgs hosta (unstable) bierze z nich wartości
  domyślne obu opcji. Kernel buduje `Image` i `dtbs/` tak jak wcześniej.
- **Kiedy usunąć:** gdy nixos-raspberrypi przejdzie na nixpkgs z tymi
  atrybutami (26.11). Sprawdzenie:
  `nix eval .#nixosConfigurations.raspberry-pi-4.config.boot.kernelPackages.kernel.buildDTBs`
  zwraca `true` — wtedy usunąć obie linie i ewaluacja musi przejść.

### 16. nix-update — kopia flake'a przez `nix flake archive` (Nix 2.35)

- **Od:** 2026-11-13.
- **Plik:** `modules/packages/nix-update-flake-archive.nix` (overlay
  `nix-update-flake-archive` w `base-nix` i w `pkgs` perSystem,
  `modules/default.nix`).
- **Objaw:** `flake-update` (i ręczne `nix-update -F <pakiet>`) podbija
  wersję, po czym prefetch hasha albo `--generate-lockfile` pada z
  `error: opening file "/nix/store/…-source": No such file or directory`
  (pierwszy raz przy `rea-agents` 6.8.0 -> 6.9.0).
- **Przyczyna:** nix-update 1.16.0 (`get_flake_store_path` w
  `nix_update/options.py`) bierze ścieżkę flake'a z `nix flake metadata
  --json` i ewaluuje ją `builtins.getFlake`. Nix 2.35 (`pkgs.nix` w nixpkgs
  od bumpu 2026-11-13) zwraca tam ścieżkę bez kopiowania drzewa do sklepu;
  2.34 je kopiował. Upstream master (Mic92/nix-update) wciąż używa
  `metadata`, issue jeszcze nie ma.
- **Obejście:** łatka zamienia `metadata` na `archive` (kopiuje drzewo,
  zwraca to samo pole `path`; ~1 s zamiast ~0,04 s na wywołanie).
- **Kiedy usunąć:** gdy przypięty nix-update przestanie brać ścieżkę z
  `nix flake metadata` (`--replace-fail` oblewa wtedy build). Sprawdzenie:
  usunąć overlay i w czystym klonie z pakietem mającym nową wersję
  `nix run .#nixosConfigurations.nixos.pkgs.nix-update -- -F <pakiet>`
  musi podbić wersję i hash.

## Zamknięte

- **Rust bez bibliotek systemowych — overlay `cargo-system-libs` (wpis 15)**
  — zamknięte 2026-11-14. Przypięty nixpkgs (d4f25a3) ma `zstd` w
  `buildInputs` `ark` i `obscura` oraz `aws-lc`, `oniguruma`, `sqlite`,
  `zstd` w `codex`, a Hydra zbudowała wszystkie trzy (są w cache.nixos.org).
  Usunięto `modules/packages/cargo-system-libs.nix` i overlay z `base-nix`.


- **hermes-agent — kopia modułu NixOS, kasowanie blokad bramki, pakiet
  `hermes-lang-pl` bez `requires_hermes`, HERMES_HOME 2750 (wpisy 2, 3, 5
  i 11)** — zamknięte 2026-11-13. Hermes Agent usunięto z repo (moduł
  `rpi-hermes` z kopią `_hermes-agent/` i pluginami, test
  `hermes-activation`, wejście `hermes-agent`), więc obejścia zniknęły razem
  z nim.

- **llama.cpp (fork PrismML) — testy niezgodne z flagami budowania (wpis 9)**
  — zamknięte 2026-11-10. Modele Ternary Bonsai i fork PrismML usunięto
  z repo (pakiet `modules/packages/_llama-cpp-prism`, aliasy `llama-prism`,
  `bonsai-serve`, `bonsai-serve-mtp`), więc obejście `postPatch`
  i `disabledTests` zniknęło razem z pakietem.

- **`PREEMPT_LAZY n` dla kernela RPi4 (`argsOverride`)** — zamknięte
  2026-10-09. Zablokowany `nixos-hardware` (`raspberry-pi/common/kernel.nix`)
  sam ustawia w `structuredExtraConfig` `PREEMPT = mkForce yes;
  PREEMPT_LAZY = mkForce no;` dla `rpiVersion >= 3`, a `raspberry-pi/4`
  domyślnie bierze ten sam `kernel.nix`. Blok `boot.kernelPackages`
  z `modules/hosts/raspberry-pi-4/configuration.nix` usunięto; zbudowany
  configfile ma `CONFIG_PREEMPT=y` i nie ma `CONFIG_PREEMPT_LAZY=y`.

- **NVIDIA open 615.71.09 — nieaktualny patch GPIO z nix-cachyos-kernel** —
  zamknięte 2026-10-09. Zablokowany `nix-cachyos-kernel`
  (`kernel-cachyos/packages.nix`) używa już `--replace-quiet` dla sygnatury
  `__to_hwgpio`, więc override `postPatch` (`--replace-fail` →
  `--replace-warn`) w `modules/hardware/LOQ-15IRX10.nix` usunięto;
  `hardware.nvidia.package` to znowu samo `nvidiaPackages.latest`.

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
  flake znowu śledzi upstream (wejście `hermes-agent` we `flake.nix` bez pinu).
