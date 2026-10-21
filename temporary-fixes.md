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

### 2. Kopia modułu NixOS hermes-agent (aktywacja bez zapisów roota)

- **Od:** 2026-10-07.
- **Pliki:** `modules/hosts/raspberry-pi-4/_hermes-agent/nixos-module.nix`
  (kopia `nix/nixosModules.nix` z NousResearch/hermes-agent @ 848fc0ad, MIT),
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
  `setpriv --reuid=hermes … --no-new-privs`. Wpisy `HERMES_HOME` innych
  właścicieli (stare uruchomienia CLI jako root/nixos) przejmuje kopią jako
  hermes; oryginalne katalogi zostają jako `.foreign-<nazwa>` do ręcznego
  usunięcia. Tryb kontenerowy wyłączony asercją.
- **Kiedy usunąć:** gdy upstream przestanie pisać jako root w `stateDir`
  (zgłosić upstream). Do tego czasu przy każdym `nix flake update hermes-agent`
  nałożyć diff upstreamowego `nix/nixosModules.nix` na kopię (procedura
  w nagłówku pliku) i uruchomić `hermes-activation`.

### 3. hermes-agent — kasowanie `gateway.lock`/`gateway.pid`/`gateway_state.json`

- **Od:** przed 2026-10 (wcześniej bez wpisu).
- **Plik:** `modules/hosts/raspberry-pi-4/hermes.nix` (`ExecStartPre`, jako
  użytkownik usługi).
- **Przyczyna:** pliki blokady/stanu pozostałe po przerwanym procesie albo
  utworzone przez sesję interaktywną blokowały start bramki (PermissionError).
  Od 2026-10-14 także rekord hosta
  `/var/lib/hermes/.local/state/hermes/gateway-locks/host-gateway.{json,token}`:
  po twardym resecie RPi zapisany PID (1501) z czasem startu w taktach od
  rozruchu (tolerancja 2 s) trafił na cloudflared o tym samym PID i czasie,
  więc `host_attach` uznawał go za żywą bramkę i usługa restartowała się
  bez końca (exit 75, „has not published its served set yet”). Rekord nie
  zawiera `boot_id`.
- **Kiedy usunąć:** gdy hermes sam wykrywa nieaktualne blokady (pid nie żyje,
  rekord z innego rozruchu) — sprawdzić: usunąć `ExecStartPre`, `kill -9`
  bramki, Restart musi wstać; rekord hosta z PID i `start_time` procesu
  z bieżącego rozruchu nie może blokować startu.

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

### 5. hermes-agent — pakiet językowy `hermes-lang-pl` bez `requires_hermes`

- **Od:** 2026-10-11.
- **Plik:** `modules/hosts/raspberry-pi-4/hermes.nix` (`polishLanguagePack`:
  `applyPatches` + `substituteInPlace --replace-fail` na `plugin.yaml`).
- **Objaw:** `Plugin 'hermes-lang-pl' skipped: requires hermes >=0.22, running
  0.0.0` — mimo `plugins.enabled` interfejs zostaje po angielsku.
- **Przyczyna:** `nix/packages.nix` w NousResearch/hermes-agent nie przekazuje
  `version` do `nix/hermes-agent.nix` (domyślnie `"0.0.0"`, a `pyproject.toml`
  na `main` też ma `0.0.0`; prawdziwy numer jest tylko na tagach wydań, np.
  v2026.9.24 = 0.21.5), więc stempel instalacji ma `baseVersion = "0.0.0"`
  i loader pomija każdy plugin z `requires_hermes` (poza `model-provider`).
  Przypięty `main` (0a374d16, po 0.21.5) ma już `provides_locales`;
  `hermes plugins validate` przechodzi.
- **Kiedy usunąć:** gdy pakiet Nix Hermesa stempluje prawdziwą wersję `>=0.22`
  (zgłosić upstream). Sprawdzenie: usunąć `postPatch`, przebudować, w
  `journalctl -u hermes-agent -b` nie może być `hermes-lang-pl' skipped`.

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

### 9. llama.cpp (fork PrismML) — testy niezgodne z flagami nixpkgs

- **Od:** 2026-10-20.
- **Plik:** `modules/packages/_llama-cpp-prism/default.nix` (`postPatch` — dwa
  `substituteInPlace --replace-fail`, `disabledTests`).
- **Objaw:** przy `GGML_BACKEND_DL=ON` i `BUILD_SHARED_LIBS` (flagi z nixpkgs)
  `test-dfly-fusion` nie linkuje (`undefined reference to ggml_graph_compute`),
  `test-kv-mean-center` pada z `no backends are loaded`, `test-llama-archs` na
  asercie `ggml_is_padded_1d` w grafie qwen35, a `test-generate-models` na
  `key not found in model: dspark.dspark.block_size`; `test-save-load-state`
  i testy rollback wymagają fixture'ów pobierających modele z sieci.
- **Przyczyna:** `test-dfly-fusion` i `test-kv-mean-center` to testy forka:
  pierwszy używa wewnętrznego `ggml_graph_compute` (mainline bramkuje tak
  `test-barrier` przez `if (NOT GGML_BACKEND_DL)`), drugi nie woła
  `llama_backend_init()` — ta sama klasa błędu, którą upstream naprawił
  w `test-llama-archs` (ggml-org/llama.cpp#30034). Asercja qwen35 i brak
  metadanych dspark to błędy forka w kodzie grafu/testów. `test-save-load-state`
  dodano po wersji nixpkgs, dla której pisano `disabledTests`.
- **Obejście:** `test-dfly-fusion` pod `if (NOT GGML_BACKEND_DL)` (jak
  mainline), `llama_backend_init()` w `test-kv-mean-center`, reszta w
  `disabledTests`.
- **Kiedy usunąć:** gdy fork naprawi te testy — `--replace-fail` padnie wtedy
  na zmienionym kontekście; sprawdzenie: `nix build .#llama-cpp-prism` z `doCheck`
  i bez `postPatch`/wyłączeń musi przejść.

## Zamknięte

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
  flake znowu śledzi upstream (komentarz w `flake.nix`).
