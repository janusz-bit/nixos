{
  inputs,
  customTop,
  ...
}:
{
  flake.modules.nixos.rpi-configuration =
    {
      config,
      pkgs,
      ...
    }:
    let
      keys = import "${customTop.secretsDir}/keys.nix";
    in
    {
      networking = {
        hostName = "raspberry-pi-4";
        networkmanager.enable = true;
        # Jak na laptopie: port 22 tylko z domowego LAN-u (IPv4), zamknięty na
        # IPv6 — globalny prefiks od ISP wystawiałby inaczej SSH roota do
        # internetu. Tunel łączy się przez lo, które nixos-fw zawsze przepuszcza.
        firewall.extraCommands = ''
          iptables -A nixos-fw -p tcp -s ${customTop.lan.subnet} --dport 22 -j nixos-fw-accept
        '';
      };

      boot = {
        kernel.sysctl = {
          "vm.swappiness" = 100;
          # zRAM: odczyt z wyprzedzeniem (domyślnie 8 stron) nie ma sensu bez
          # dysku — każdy page-in dekompresowałby 8 stron na Cortex-A72.
          "vm.page-cluster" = 0;
          # Headless serwer: panika/oops kończy się restartem po 10 s zamiast
          # wiszącego do fizycznego odłączenia zasilania jądra.
          "kernel.panic" = 10;
          "kernel.panic_on_oops" = 1;
        };
        tmp.useTmpfs = true;
        kernelParams = [
          # Jądro RPi ma CONFIG_PSI_DEFAULT_DISABLED=y: bez PSI nie startuje
          # systemd-oomd i pod presją pamięci zostaje tylko globalny OOM-killer
          # po minutach mielenia swapem.
          "psi=1"
        ];
        # Wbudowany Bluetooth jest nieużywany (serwer headless), a jego
        # inicjalizacja przez UART kończy się błędem przy każdym starcie.
        # Nie nakładka disable-bt: przenosi UART0 na GPIO14/15, a GPIO14
        # steruje wentylatorem (pwm-fan.nix).
        blacklistedKernelModules = [
          "bluetooth"
          "btbcm"
          "btqca"
          "btsdio"
          "hci_uart"
        ];

        # The RPi vendor kernel from nixos-hardware uses PREEMPT=yes but does not
        # set PREEMPT_LAZY=no. nixpkgs common-config.nix sets PREEMPT_LAZY=yes for
        # kernel >= 6.18, which conflicts with PREEMPT=yes (same kconfig choice).
        # boot.kernelPatches is not applied because nixos-hardware hardcodes
        # kernelPatches inside buildLinux (via callPackage), bypassing the NixOS
        # kernel module's apply hook. Use argsOverride on the nixos-hardware
        # kernel.nix to inject PREEMPT_LAZY=n via extraConfig (legacy string format
        # appended to the intermediate kernel config, overriding structured config).
        # Ref: https://github.com/NixOS/nixpkgs/commit/d79e72ee0533cd5ce021dcd8863599e9dd290a33
        # Do usunięcia przy najbliższym bumpie jądra (temporary-fixes.md #2).
        kernelPackages =
          let
            rpiKernel = pkgs.callPackage "${inputs.nixos-hardware}/raspberry-pi/common/kernel.nix" {
              rpiVersion = 4;
              argsOverride = {
                extraConfig = ''
                  PREEMPT_LAZY n
                '';
              };
            };
          in
          pkgs.linuxPackagesFor rpiKernel;
      };

      systemd = {
        # Sprzętowy watchdog BCM2835 (maks. ~15 s): zawieszony PID 1 albo jądro
        # restartuje się samo; RebootWatchdogSec pilnuje zawieszonego restartu.
        settings.Manager = {
          RuntimeWatchdogSec = "15s";
          RebootWatchdogSec = "10min";
        };
        # Pod presją pamięci (PSI) oomd zabija najgorszy zakres użytkownika:
        # sesje interaktywne i agentów (user@1000) oraz zadania cron hermesa
        # (user@991) — zanim host zacznie mielić swapem usługi publiczne.
        oomd.enableUserSlices = true;
        # Kompilatory i GC giną od OOM przed usługami (dziedziczą to buildery).
        services.nix-daemon.serviceConfig.OOMScoreAdjust = 500;
      };

      # Mostek UAS zgłasza SSD Lexar SL500 jako dysk obrotowy: jądro stosuje
      # wtedy heurystyki HDD (alokator swapu, wbt). noatime: brak zapisów
      # metadanych przy każdym odczycie (Postgres, Nextcloud, Gitea).
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTRS{model}=="SL500*", ATTR{queue/rotational}="0"
      '';
      fileSystems."/".options = [ "noatime" ];

      # CPU Performance optimization
      powerManagement.cpuFreqGovernor = "ondemand";

      # Memory optimization: SSD swap and zRAM
      # zRAM zapełniony (50% RAM) wypychał świeże strony na swapfile USB,
      # a stare zostawały w zRAM (odwrócone LRU). Przy ~3:1 zstd pełny zRAM
      # 100% zajmuje ~1,2 GB RAM.
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 100;
      };
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size = 8192; # 8GB of swap on SSD
        }
      ];

      time.timeZone = "Europe/Warsaw";

      # SSH: bazowe ustawienia (tylko klucze) z base-ssh. Logowanie roota
      # kluczem zostaje — to ścieżka administracyjna przez tunel
      # (`Host ssh.*` → `User root` w base-ssh). Port 22 tylko z LAN-u
      # (networking.firewall wyżej).
      services.openssh = {
        settings.PermitRootLogin = "prohibit-password";
        openFirewall = false;
      };
      # Headless: bez x11-ssh-askpass (zależności X11).
      programs.ssh.enableAskPassword = false;

      nix = {
        settings = {
          # 2 zadania × 2 rdzenie = 4 wątki = nproc; z cores = 0 każde zadanie
          # brało wszystkie 4 rdzenie (8 wątków kompilatora na 4 GB RAM).
          max-jobs = 2;
          cores = 2;
        };
        # Budowanie ustępuje usługom (Nextcloud, Postgres, cloudflared).
        daemonCPUSchedPolicy = "batch";
        daemonIOSchedClass = "idle";
        # 1 TB SSD zajęty w 9% — codzienny GC z retencją 3 dni (dawniej mała
        # karta SD) tylko skracał możliwy rollback i codziennie skanował store.
        # Bazowe weekly z nix-settings, retencja wydłużona do 14 dni.
        gc.options = "--delete-older-than 14d";
        optimise.dates = [ "weekly" ];
      };

      # Serwer headless: bez /share/doc. Przy okazji nie buduje się
      # python3.11-doc (nixpkgs#499166), więc overlay python-docs-fix jest zbędny.
      documentation.doc.enable = false;

      environment.systemPackages = with pkgs; [
        # micro, htop i uv pochodza z base (sharedPackages); git z base-git
        nodejs_22
        ripgrep
        ffmpeg
        python311
        tea # Gitea official CLI client
        antigravity-cli
        # Claude Code — agent kodujący w terminalu (nixpkgs)
        claude-code
      ];

      users.users = {
        # Bez initialPassword: hasło równe nazwie użytkownika było publiczne
        # (repo) przy koncie z wheel. Świeży obraz startuje z zablokowanym
        # hasłem; pierwsze logowanie kluczem (root przez LAN/tunel), potem
        # `passwd ${config.customBot.defaultUser}` (AGENTS.md).
        ${config.customBot.defaultUser} = {
          isNormalUser = true;
          description = "${config.customBot.defaultUser}";
          extraGroups = [
            "networkmanager"
            "wheel"
          ];
          # Klucze roota laptopa i RPi oraz telefonu (SSH z komórki).
          openssh.authorizedKeys.keys = builtins.attrValues keys.hosts ++ [ keys.users.phone ];
        };
        # Twój klucz z laptopa (ssh ssh.janusz-bit.com loguje się jako root).
        root.openssh.authorizedKeys.keys = [ keys.users.janusz-bit ];
      };
    };
}
