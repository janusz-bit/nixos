# Strojenie pamięci i systemd wzorowane na CachyOS (CachyOS-Settings e27ea45,
# 2026-10-04): zRAM zstd na cały RAM bez zswap, swappiness/page-cluster, limity
# dirty, THP max_ptes_none 409, SysRq, bez watchdoga NMI, stop jednostek 10 s, oomd.
#
# Są tu tylko ustawienia z efektem pokazanym w teście VM z kernelem hosta
# (checks.tuning) albo w journalu hosta; THP 409 i zRAM = RAM na samym laptopie
# nie były jeszcze mierzone. Pominięte z cachyos-settings:
# - już domyślne: thp.conf (defer+madvise z CONFIG_CACHY; kernel ma też
#   watermark_boost 0, compaction_proactiveness 0, MGLRU min_ttl 100 ms),
#   resolved (włącza go mullvad-vpn), ntsync (gaming/steam.nix), runtime PM
#   dGPU (hardware/LOQ-15IRX10);
# - bez zastosowania: pci-latency (brak konwencjonalnej szyny PCI), SATA/hdparm
#   (brak dysków SATA), regdomain Wi-Fi (AP i tak ustawia PL);
# - bez zysku: vfs_cache_pressure, dirty_writeback_centisecs, NOFILE
#   (1024:524288 wystarcza, NTSYNC zamiast esync), journal 50M,
#   NVreg_InitializeSystemMemoryAllocations=0 (init_on_alloc i tak zeruje, a
#   przepadłby wyczyszczony pool NVIDII), blacklist iTCO_wdt (systemd uzbraja
#   go tylko przy wyłączaniu: RebootWatchdogSec=10min);
# - czeka na A/B na hoście: scheduler NVMe kyber, power_save snd_hda_intel;
# - DefaultTimeoutStartSec=15s: nic tu nie skraca.
#
# Sprawdzenie: `nix build -L .#checks.x86_64-linux.tuning` (test VM, A/B
# każdej zmiany); na hoście `zramctl`, `sysctl vm.swappiness kernel.sysrq`,
# `cat /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none` (409).
_: {
  flake.modules.nixos.desktop-tuning = _: {
    boot = {
      # Kernel CachyOS ma CONFIG_ZSWAP_DEFAULT_ON=y, a moduł boot.zswap
      # przy enable = false nic nie wyłącza: zswap kompresowałby strony
      # przed zapisem do zRAM (podwójna kompresja, zmarnowany CPU).
      kernelParams = [ "zswap.enabled=0" ];

      kernel.sysctl = {
        # Pod swap w zRAM (30-zram.rules, 70-cachyos-settings): dekompresja z RAM
        # jest tańsza niż odczyt page cache z dysku, a readahead swapu nic nie daje.
        "vm.swappiness" = 150;
        "vm.page-cluster" = 0;
        # Domyślne 20%/10% to do ~6/3 GB przy 32 GB: duże zrzuty zapisu (Steam,
        # cache shaderów) blokują I/O i dają przycięcia w grze.
        "vm.dirty_bytes" = 268435456; # 256 MiB
        "vm.dirty_background_bytes" = 67108864; # 64 MiB
        # Watchdog NMI: okresowe NMI na każdym rdzeniu i zajęty licznik PMU —
        # zbędne na desktopie.
        "kernel.nmi_watchdog" = 0;
        # Magic SysRq: zamiast 1 z CachyOS maska 244 = 4 unraw/SAK + 16 sync +
        # 32 remount ro + 64 sygnały i OOM-kill (Alt+PrtSc+F) + 128 reboot, bez
        # zrzutów debug (8); domyślne 16 z systemd pozwala tylko na sync.
        "kernel.sysrq" = 244;
      };

      # thp-shrinker.conf z CachyOS. Przy domyślnym 511 shrinker niedopełnionych
      # THP nigdy nie dzieli (thp_underused()), więc hugepage z jednym gorącym
      # bajtem trzyma 2 MiB, a pod presją do swapu idą prawdziwe dane. Przy 409
      # THP z >409 zerowymi podstronami jest dzielony (thp_underused_split_page
      # w /proc/vmstat); khugepaged składa THP dopiero przy ≥103 zajętych stronach.
      # Zmierzone w VM (checks.tuning, 200 rzadkich gorących THP): przy 511 400 MiB
      # zer w RAM i ~1,1 GiB w swapie, przy 409 0,8 MiB i ~0,7 GiB. Przy lekkiej
      # presji w memcg zwykle bez podziału (0 w 8 z 12 przebiegów): shrinker rusza
      # dopiero, gdy reclaim się męczy. THP przeskanowane wcześniej przy 511 wypadły
      # z kolejki deferred split — pełny efekt po restarcie.
      kernel.sysfs.kernel.mm.transparent_hugepage.khugepaged.max_ptes_none = 409;
    };

    # zRAM zstd (priorytet 100 > swap dyskowy -1) na cały RAM jak w CachyOS: przy
    # 50% (15,5 GiB) user.slice doszedł do 14,7 GiB swapu (2026-08-28, jeszcze
    # z zswap), a nadmiar szedłby na swap LUKS (losowe odczyty przez dm-crypt
    # zamiast dekompresji z RAM). RAM zajmują tylko skompresowane strony
    # i tablica slotów (~130 MB). Swap NVMe zostaje dla hibernacji. Nowy rozmiar
    # po restarcie (restartIfChanged = false).
    zramSwap = {
      enable = true;
      priority = 100;
      memoryPercent = 100;
    };

    systemd = {
      # 00-timeout.conf z CachyOS (tylko stop, też menedżer użytkownika niżej):
      # jednostki bez własnego TimeoutStopSec giną po 10 s zamiast 90 s. W 225
      # wyłączeniach (mediana 2,2 s) jedyne zawieszenie do domyślnego limitu to
      # cups-browsed (90 s); najdłuższy normalny stop: 6,5 s (sleep-actions).
      # Mount/swap biorą limit z DefaultTimeoutStartSec — bez zmian.
      settings.Manager.DefaultTimeoutStopSec = "10s";

      # 10-oomd-per-slice-defaults.conf z CachyOS: oomd zabija liść cgroup
      # z największym pgscan, gdy monitorowana cgroup stoi >80% czasu na
      # reclaimie przez 30 s (NixOS domyślnie pilnuje tylko scope'ów, które
      # o to proszą). nix-daemon (use-cgroups = false) to jeden liść: padnie
      # cały build. Odstępstwa od CachyOS:
      # - user@.service zamiast user-.slice: slice należy do roota, a oomd
      #   ignoruje ManagedOOMPreference kandydatów innego właściciela, więc
      #   sesji (KWin, szyna D-Bus) nie dałoby się osłonić;
      # - bez ManagedOOMSwap=kill: limit 90% swapu liczy też 36 GiB swapu pod
      #   hibernację, więc nigdy by nie zadziałał.
      oomd.enableSystemSlice = true;
      services."user@" = {
        overrideStrategy = "asDropin";
        serviceConfig = {
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "80%";
        };
      };
      user = {
        settings.Manager.DefaultTimeoutStopSec = "10s";

        # KWin i szyna sesji mają Restart=no (ich zabicie kończy sesję Plasmy);
        # plasmashell i PipeWire wstają same, więc tylko „avoid”. Jednostki KDE
        # przez units.*.text: drop-in z user.services dokleja Environment=PATH=…
        # i nadpisałby PATH sesji (dziedziczą go aplikacje z Plasmy); dbus-broker,
        # pipewire i wireplumber mają już własny PATH z NixOS, więc tam services.
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
