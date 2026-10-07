_: {
  # Strojenie pamięci i systemd wzorowane na CachyOS (CachyOS-Settings
  # e27ea45, 2026-10-04). Są tu tylko ustawienia, których efekt pokazuje
  # test VM z kernelem hosta (nix build .#checks.x86_64-linux.tuning) albo
  # journal hosta; efekt THP 409 i zRAM = RAM na samym laptopie nie był
  # jeszcze mierzony. Reszta pakietu cachyos-settings:
  # - już domyślna: thp.conf (defrag defer+madvise = domyślne CONFIG_CACHY;
  #   kernel CachyOS ma też sam z siebie watermark_boost 0,
  #   compaction_proactiveness 0, MGLRU min_ttl 100 ms), resolved jako DNS
  #   w NetworkManagerze (włącza go moduł mullvad-vpn), ntsync (gaming.nix),
  #   runtime PM dGPU (LOQ-15IRX10.nix);
  # - nie ma na czym działać: pci-latency (brak konwencjonalnej szyny PCI:
  #   PCIe i funkcje zintegrowane w CPU/PCH), reguły SATA/hdparm (brak
  #   dysków SATA), regdomain Wi-Fi (AP i tak ustawia PL);
  # - bez zysku: vfs_cache_pressure 50 i dirty_writeback_centisecs 1500
  #   (usunięte jako kosmetyka w ab57792), NOFILE (domyślne 1024:524288
  #   wystarcza, NTSYNC zamiast esync), NVreg_InitializeSystemMemoryAllocations=0
  #   (kernel i tak zeruje strony przez init_on_alloc, a przepadłby wstępnie
  #   wyczyszczony pool NVIDII), journal 50M, blacklist iTCO_wdt (w pracy
  #   nieaktywny, a systemd uzbraja go przy wyłączaniu: RebootWatchdogSec=10min);
  # - czeka na A/B na hoście: scheduler NVMe kyber (60-ioschedulers.rules),
  #   power_save snd_hda_intel na zasilaczu (20-audio-pm.rules);
  # - decyzje: DefaultTimeoutStartSec=15s pominięte (nic tu nie skraca).
  flake.modules.nixos.nixos-tuning = _: {
    boot = {
      # Kernel CachyOS ma CONFIG_ZSWAP_DEFAULT_ON=y, a moduł boot.zswap
      # przy enable = false nic nie wyłącza: zswap kompresowałby strony
      # przed zapisem do zRAM (podwójna kompresja, zmarnowany CPU).
      kernelParams = [ "zswap.enabled=0" ];

      kernel.sysctl = {
        # Strojenie pod swap w zRAM (jak 30-zram.rules i 70-cachyos-settings
        # z CachyOS): dekompresja z RAM jest tańsza niż ponowny odczyt page
        # cache z dysku, a readahead swapu (8 stron) nie ma sensu dla zRAM.
        "vm.swappiness" = 150;
        "vm.page-cluster" = 0;
        # Domyślnie 20%/10% pamięci dostępnej do zabrudzenia (do ~6/3 GB
        # przy 32 GB): duże zrzuty zapisu (pobieranie/aktualizacja w Steamie,
        # cache shaderów) mogą blokować I/O i dawać przycięcia w grze.
        # Mniejsze, częstsze porcje writeback.
        "vm.dirty_bytes" = 268435456; # 256 MiB
        "vm.dirty_background_bytes" = 67108864; # 64 MiB
        # Watchdog NMI (HARDLOCKUP_DETECTOR_PERF): okresowe NMI na każdym
        # rdzeniu i zajęty licznik PMU — zbędne na desktopie.
        "kernel.nmi_watchdog" = 0;
        # Magic SysRq (CachyOS f99252b: kernel.sysrq = 1, „REISUB”). Zamiast
        # 1 (wszystko) maska 244 = 4 unraw/SAK + 16 sync + 32 remount ro +
        # 64 sygnały i ręczny OOM-kill (Alt+PrtSc+F) + 128 reboot — bez
        # zrzutów debug (8). Domyślne 16 z systemd pozwala tylko na sync.
        "kernel.sysrq" = 244;
      };

      # thp-shrinker.conf z CachyOS. Przy domyślnym 511 shrinker
      # niedopełnionych THP jest martwy (mm/huge_memory.c thp_underused():
      # max_ptes_none == 511 → nigdy nie dzieli): hugepage z jednym
      # regularnie dotykanym bajtem trzyma 2 MiB (MGLRU widzi jeden młody
      # folio), więc pod presją do swapu idą zamiast niego prawdziwe dane.
      # Przy 409 THP z >409 zerowymi podstronami jest dzielony
      # (thp_underused_split_page w /proc/vmstat); khugepaged składa THP
      # dopiero przy ≥103 zajętych stronach. Zmierzone w VM (checks.tuning)
      # przy globalnej presji ze swapem, 200 rzadkich, gorących THP: przy 511
      # 400 MiB zer w RAM i ~1,1 GiB danych w swapie, przy 409 0,8 MiB i
      # ~0,7 GiB. Ile rzadkich THP mają ciężkie sesje na hoście (swap do
      # 14,7 GiB) — niezmierzone. Przy lekkiej presji w memcg ze swapem
      # zwykle bez podziału (0 w 8 z 12 przebiegów): shrinker skanuje licznik >>
      # priority, więc rusza dopiero, gdy reclaim się męczy. Po update-local
      # działa od razu dla nowych THP; THP przeskanowane wcześniej przy 511
      # wypadły z kolejki deferred split — pełny efekt dopiero po restarcie.
      kernel.sysfs.kernel.mm.transparent_hugepage.khugepaged.max_ptes_none = 409;
    };

    # zRAM ze zstd (priorytet 100 > swap dyskowy -1). Rozmiar = cały RAM jak
    # zram-generator.conf w CachyOS: przy 50% (15,5 GiB) user.slice doszedł
    # już do 14,7 GiB swapu (journal, 2026-08-28, jeszcze z włączonym
    # zswap), a nadmiar szedłby na LUKS-owy swap dyskowy (losowe odczyty 4k
    # przez dm-crypt zamiast dekompresji z RAM). RAM zajmują tylko
    # skompresowane strony i tablica slotów (16 B/stronę: ~130 MB, +~65 MB
    # względem 50%). Swap NVMe LUKS (/dev/mapper/swap) zostaje na potrzeby
    # hibernacji. Nowy rozmiar obowiązuje po restarcie (restartIfChanged = false).
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      priority = 100;
      memoryPercent = 100;
    };

    systemd = {
      # 00-timeout.conf z CachyOS (tylko stop; system i user — niżej
      # user.settings). Jednostki bez własnego TimeoutStopSec są zabijane
      # po 10 s zamiast 90 s (ExecStop= ma 10 s, potem SIGTERM i SIGKILL
      # po kolejnych 10 s). W 225 wyłączeniach
      # (mediana 2,2 s) były dwa zawieszenia: cups-browsed z domyślnym
      # limitem („stop-sigterm timed out” po 90 s, 2026-08-25) — to skraca
      # ta zmiana — i plasma-plasmashell po 40 s (2026-07-23), który ma
      # własny TimeoutStopSec=40s. Najdłuższy normalny stop jednostki z
      # domyślnym limitem: 6,5 s (sleep-actions). Mount/swap biorą limit z
      # DefaultTimeoutStartSec — bez zmian.
      settings.Manager.DefaultTimeoutStopSec = "10s";

      # 10-oomd-per-slice-defaults.conf z CachyOS (presja pamięci): oomd
      # zabija liść cgroup z największym pgscan, gdy cała monitorowana
      # cgroup stoi >80% czasu na reclaimie przez 30 s — zamiast
      # wielominutowego thrashingu. Domyślnie NixOS pilnuje tylko scope'ów,
      # które same o to proszą (np. karty Konsoli). Uwaga: nix-daemon
      # (use-cgroups = false) to jeden liść, więc padnie cały build.
      # Odstępstwa od CachyOS:
      # - user@.service zamiast user-.slice (układ Fedory): user-<uid>.slice
      #   należy do roota, a oomd ignoruje ManagedOOMPreference kandydatów
      #   innego właściciela — sesji (KWin, szyna D-Bus) nie dałoby się
      #   osłonić; user@<uid>.service należy do użytkownika, więc omit działa;
      # - bez ManagedOOMSwap=kill: limit 90% swapu liczy też 36 GiB swapu
      #   pod hibernację, więc nigdy by nie zadziałał.
      oomd.enableSystemSlice = true;
      services."user@" = {
        overrideStrategy = "asDropin";
        serviceConfig = {
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "80%";
        };
      };
      user = {
        settings.Manager.DefaultTimeoutStopSec = "10s"; # jak wyżej, menedżer użytkownika

        # KWin i szyna sesji mają Restart=no — ich zabicie kończy całą sesję
        # Plasmy. plasmashell/PipeWire wstają same, więc tylko „avoid”.
        # Jednostki KDE przez units.*.text, nie user.services: drop-in z
        # services dokleja Environment=PATH=coreutils… i nadpisałby PATH sesji
        # (dziedziczą go aplikacje uruchamiane z Plasmy). dbus-broker, pipewire
        # i wireplumber definiuje już NixOS (z własnym PATH), więc tam wprost.
        units =
          let
            prefer = p: {
              overrideStrategy = "asDropin";
              text = ''
                [Service]
                ManagedOOMPreference=${p}
              '';
            };
          in
          {
            "plasma-kwin_wayland.service" = prefer "omit";
            "plasma-plasmashell.service" = prefer "avoid";
          };
        services = {
          dbus-broker.serviceConfig.ManagedOOMPreference = "omit";
          pipewire.serviceConfig.ManagedOOMPreference = "avoid";
          wireplumber.serviceConfig.ManagedOOMPreference = "avoid";
        };
      };
    };
  };
}
