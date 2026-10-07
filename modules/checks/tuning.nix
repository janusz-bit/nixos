# Test VM strojenia z modules/hosts/nixos/tuning.nix na tym samym kernelu
# CachyOS co host nixos. Sprawdza, czy ustawienia zostały zastosowane
# (wartości oczekiwane bierze z konfiguracji hosta, więc rozjazd host ↔
# moduł też oblewa test), a dla zmian przejętych z CachyOS mierzy efekt:
# - THP max_ptes_none 409 vs 511 (A/B): rzadkie THP pod presją pamięci,
# - zRAM 100% vs 50% RAM (A/B): czy nadmiar trafia na swap dyskowy,
# - DefaultTimeoutStopSec: czas stopu jednostki ignorującej SIGTERM,
# - kernel.sysrq 244 vs 16 (A/B): Alt+SysRq+R,
# - oomd: kill pod presją w system.slice i user@.service, omit honorowany,
#   niemonitorowany slice bez kill.
#
# Uruchomienie: nix build -L .#checks.x86_64-linux.tuning (wymaga kvm).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      hostCfg = self.nixosConfigurations.nixos.config;
      want = builtins.toJSON {
        sysctl = lib.mapAttrs (_: toString) (
          lib.getAttrs [
            "vm.swappiness"
            "vm.page-cluster"
            "vm.dirty_bytes"
            "vm.dirty_background_bytes"
            "kernel.nmi_watchdog"
            "kernel.sysrq"
          ] hostCfg.boot.kernel.sysctl
        );
        max_ptes_none = toString hostCfg.boot.kernel.sysfs.kernel.mm.transparent_hugepage.khugepaged.max_ptes_none;
        zswap_off = builtins.elem "zswap.enabled=0" hostCfg.boot.kernelParams;
        zram = { inherit (hostCfg.zramSwap) algorithm priority memoryPercent; };
        stop = hostCfg.systemd.settings.Manager.DefaultTimeoutStopSec;
        stop_user = hostCfg.systemd.user.settings.Manager.DefaultTimeoutStopSec;
      };

      # N MiB rzadkich THP (1 bajt na 2 MiB, cały czas „gorące”) + D MiB
      # gęstego bufora (domyślnie D = N); wynik: RSS/Swap obu obszarów.
      thpProbe = pkgs.writeText "thp-probe.py" ''
        import ctypes, json, mmap, re, sys
        MB = 1 << 20
        HP = 2 * MB
        N = int(sys.argv[1])
        D = int(sys.argv[2]) if len(sys.argv) > 2 else N


        def addr_of(m):
            b = (ctypes.c_char * 1).from_buffer(m)
            a = ctypes.addressof(b)
            del b
            return a


        def smaps(addr):
            out, cur = {}, False
            for line in open("/proc/self/smaps"):
                m = re.match(r"^([0-9a-f]+)-([0-9a-f]+) ", line)
                if m:
                    cur = int(m.group(1), 16) <= addr < int(m.group(2), 16)
                    continue
                if cur:
                    k, v = line.split(":", 1)
                    if k in ("Rss", "AnonHugePages", "Swap"):
                        out[k] = int(v.split()[0])
            return out


        flags = mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS
        sp = mmap.mmap(-1, (N + 2) * MB, flags=flags)
        base = addr_of(sp)
        off = (-base) % HP
        # osobny VMA, żeby rzadki i gęsty obszar się nie scaliły
        guard = mmap.mmap(-1, 4096, flags=flags, prot=mmap.PROT_READ)
        sparse = range(off, off + N * MB, HP)
        for i in sparse:
            sp[i] = 1
        de = mmap.mmap(-1, D * MB, flags=flags | mmap.MAP_NORESERVE)
        for r in range(3):
            for i in range(0, D * MB, 4096):
                de[i] = (r + 2) & 255
                if i % (64 * 4096) == 0:
                    for j in sparse:
                        sp[j] = 1
        print(json.dumps({"sparse": smaps(base + off), "dense": smaps(addr_of(de))}))
      '';

      # Trzyma podaną liczbę MiB anonimowej pamięci (~8:1 kompresowalnej) i czeka.
      memHog = pkgs.writeText "mem-hog.py" ''
        import mmap, os, sys, time
        mib, ready = int(sys.argv[1]), sys.argv[2]
        chunk = (os.urandom(512) + b"\x55" * 3584) * 256  # 1 MiB
        m = mmap.mmap(-1, mib << 20, flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS)
        for off in range(0, mib << 20, 1 << 20):
            m[off : off + (1 << 20)] = chunk
        open(ready, "w").close()
        time.sleep(3600)
      '';

      # Gotowość dopiero po trap, inaczej szybki stop wygrywa wyścig.
      hang = ''
        trap "" TERM
        touch "''${XDG_RUNTIME_DIR:-/run}/hang-ready"
        while :; do sleep 1; done
      '';
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.tuning = pkgs.testers.runNixOSTest {
        name = "tuning";
        nodes.machine = {
          imports = [ self.modules.nixos.nixos-tuning ];
          # Ten sam kernel co host (z cache lantian, bez kompilacji).
          boot.kernelPackages = hostCfg.boot.kernelPackages;
          virtualisation = {
            memorySize = 2048;
            diskSize = 4096;
            cores = 2;
          };
          environment.systemPackages = [ pkgs.python3 ];
          # test-instrumentation.nix: mkDefault 2 (panika przy każdym OOM,
          # także w memcg) — scenariusz THP bez swapu celowo wywołuje OOM kill.
          boot.kernel.sysctl."vm.panic_on_oom" = 0;
          users.users.alice = {
            isNormalUser = true;
            linger = true;
          };
          systemd = {
            # Bez własnego TimeoutStopSec — dziedziczą DefaultTimeoutStopSec.
            services.hang.script = hang;
            user.services.hang.script = hang;
            # Powłoka sterownika testu siedzi w system.slice — oomd ma jej nie wybrać.
            services.backdoor.serviceConfig.ManagedOOMPreference = "omit";
          };
        };

        testScript = ''
          import json, time

          want = json.loads('${want}')

          def sh(cmd):
              return machine.succeed(cmd).strip()

          def vmstat(key):
              return int(sh(f"awk '$1==\"{key}\"{{print $2}}' /proc/vmstat"))

          def settle():
              # Po ciężkiej presji wszystkie generacje MGLRU są młodsze niż
              # min_ttl_ms (100 ms), a strefa nie ma wolnych bloków order-9:
              # fault THP budzi kswapd, który robi OOM kill mimo wolnej pamięci.
              machine.succeed("sync; echo 3 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory; sleep 1")

          def no_global_oom(phase):
              rc, out = machine.execute("dmesg | grep -E 'global_oom|kswapd[0-9]* invoked oom-killer'")
              assert rc != 0, f"{phase}: nieoczekiwany globalny OOM kill:\n{out}"

          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("dev-zram0.swap")
          machine.wait_for_unit("user@1000.service")
          # Odpowiednik swapu dyskowego hosta (priorytet -1 jak /dev/mapper/swap,
          # niżej niż zRAM); qemu-vm.nix nadpisuje swapDevices w VM (mkVMOverride []).
          machine.succeed("fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile")
          memtotal = int(sh("awk '/^MemTotal/{print $2}' /proc/meminfo")) * 1024

          with subtest("ustawienia z konfiguracji hosta są zastosowane"):
              assert "cachyos" in sh("uname -r"), sh("uname -r")
              for key, val in want["sysctl"].items():
                  got = sh(f"sysctl -n {key}")
                  assert got == val, f"{key}={got}, want {val}"
              assert want["zswap_off"] and sh("cat /sys/module/zswap/parameters/enabled") == "N"
              assert sh("cat /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none") == want["max_ptes_none"]
              assert "[always]" in sh("cat /sys/kernel/mm/transparent_hugepage/enabled")
              zram = want["zram"]
              assert f"[{zram['algorithm']}]" in sh("cat /sys/block/zram0/comp_algorithm")
              disksize = int(sh("cat /sys/block/zram0/disksize"))
              expect = memtotal * zram["memoryPercent"] // 100
              assert abs(disksize - expect) < memtotal // 50, f"zram {disksize} vs {expect}"
              assert sh("swapon --show=NAME,PRIO --noheadings | awk '$1==\"/dev/zram0\"{print $2}'") == str(zram["priority"])
              assert sh("systemctl show -p DefaultTimeoutStopUSec --value") == want["stop"]
              user = "systemctl --user --machine=alice@"
              assert sh(f"{user} show -p DefaultTimeoutStopUSec --value") == want["stop_user"]
              oomd = sh("oomctl")
              for cg in ("/system.slice", "/user.slice/user-1000.slice/user@1000.service"):
                  assert f"Path: {cg}\n" in oomd, oomd

          def timed_stop(cmd):
              t = time.monotonic()
              machine.execute(cmd)
              return time.monotonic() - t

          with subtest("DefaultTimeoutStopSec=10s: jednostka ignorująca SIGTERM ginie po ~10 s (domyślnie 90 s)"):
              machine.succeed("systemctl start hang")
              machine.wait_for_file("/run/hang-ready")
              d = timed_stop("systemctl stop hang")
              print(f"system: stop took {d:.1f} s")
              assert 9 <= d <= 20, d
              machine.succeed(f"{user} start hang")
              machine.wait_for_file("/run/user/1000/hang-ready")
              d = timed_stop(f"{user} stop hang")
              print(f"user: stop took {d:.1f} s")
              assert 9 <= d <= 20, d

          def sysrq_r(mask):
              machine.succeed(f"sysctl -w kernel.sysrq={mask}", "dmesg -C")
              machine.send_key("alt-sysrq-r")
              machine.wait_until_succeeds("dmesg | grep -q 'sysrq: '")
              return sh("dmesg | grep 'sysrq: '")

          with subtest("SysRq 244: Alt+SysRq+R działa (przy 16 z systemd zablokowane)"):
              off, on = sysrq_r(16), sysrq_r(want["sysctl"]["kernel.sysrq"])
              print(f"sysrq=16: {off!r}; sysrq={want['sysctl']['kernel.sysrq']}: {on!r}")
              assert "disabled" in off, off
              assert "disabled" not in on and "Keyboard mode" in on, on

          def thp_probe(max_ptes_none, scenario, props, args):
              machine.succeed(f"echo {max_ptes_none} > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none")
              settle()
              split, fault = vmstat("thp_underused_split_page"), vmstat("thp_fault_alloc")
              rc, out = machine.execute(f"systemd-run --scope --quiet {props} python3 ${thpProbe} {args}")
              r = json.loads(out.splitlines()[-1]) if rc == 0 else {"killed": rc}
              r["underused_split"] = vmstat("thp_underused_split_page") - split
              r["thp_alloc"] = vmstat("thp_fault_alloc") - fault
              print(f"THP {scenario}, max_ptes_none={max_ptes_none}: {r}")
              return r

          with subtest("THP: 511 vs 409 w trzech scenariuszach presji"):
              scenarios = {
                  # memcg 64M ze swapem: reclaim ma co wypchnąć do zRAM
                  "memcg+swap": (20, "-p MemoryMax=64M", "40"),
                  # memcg 64M bez swapu: reclaim schodzi do niskich priorytetów
                  "memcg-noswap": (20, "-p MemoryMax=64M -p MemorySwapMax=0", "40"),
                  # cała VM: 200 rzadkich, gorących THP + gęste dane ponad RAM
                  "global": (200, "", f"400 {memtotal * 12 // 10 >> 20}"),
              }
              res = {
                  name: {v: thp_probe(v, name, *cfg[1:]) for v in (511, int(want["max_ptes_none"]))}
                  for name, cfg in scenarios.items()
              }
              new = int(want["max_ptes_none"])
              for name, (n_thp, _, _) in scenarios.items():
                  r = res[name]
                  # warunek wstępny: rzadkie THP naprawdę powstały przy fault
                  assert r[511]["thp_alloc"] >= n_thp, ("THP nie powstały przy fault", name, r)
                  assert r[511]["underused_split"] == 0, (name, r)
              ns = res["memcg-noswap"]
              # 511: 20 THP po 1 bajcie (~40 MiB) + 40 MiB danych > 64M → OOM kill;
              # 409: shrinker dzieli rzadkie THP i proces się mieści
              assert "killed" in ns[511], ns
              assert "killed" not in ns[new] and ns[new]["underused_split"] >= 10, ns
              # globalna presja: 511 trzyma ~400 MiB zer w RAM i wypycha zamiast
              # nich prawdziwe dane; 409 oddaje te strony (zmierzone 400–426 MiB)
              gl = res["global"]
              assert gl[new]["underused_split"] >= 100, gl
              assert gl[511]["dense"]["Swap"] - gl[new]["dense"]["Swap"] >= 200 * 1024, gl
              # memcg ze swapem: reclaim zwykle kończy się na wysokim priorytecie,
              # a shrinker skanuje licznik >> priority — przy 409 w 8 z 12
              # przebiegów 0, w pozostałych 20/20, więc tu bez asercji dla 409
              no_global_oom("THP")

          def disk_swap_kib():
              return int(sh("awk '$1==\"/swapfile\"{print $4}' /proc/swaps"))

          def hog_disk_swap(mib):
              settle()
              before = disk_swap_kib()
              machine.succeed(f"systemd-run --unit=hog python3 ${memHog} {mib} /run/hog-ready")
              machine.wait_until_succeeds("test -e /run/hog-ready || ! systemctl -q is-active hog")
              machine.succeed("test -e /run/hog-ready")  # hog nie może zginąć po drodze
              used = disk_swap_kib() - before
              zram = sh("head /sys/block/zram*/mm_stat")
              machine.succeed("systemctl stop hog; rm -f /run/hog-ready")
              machine.wait_until_succeeds("! systemctl is-active hog")
              print(f"hog {mib} MiB: disk swap +{used} KiB, zram mm_stat {zram}")
              return used

          with subtest("zRAM: przy 100% RAM nadmiar nie trafia na swap dyskowy, przy 50% trafia"):
              assert want["zram"]["memoryPercent"] == 100
              hog = memtotal * 145 // 100 >> 20
              full = hog_disk_swap(hog)
              # Dawne 50% na osobnym zram1. zram0 trzeba zamaskować:
              # systemd-zram-setup@zram0 przy stopie resetuje zram0, a po
              # zdarzeniu udev sam go odtwarza (byłyby dwa zRAM naraz).
              machine.succeed("systemctl mask --runtime --now dev-zram0.swap systemd-zram-setup@zram0.service")
              machine.wait_until_fails("grep -q '^/dev/zram0 ' /proc/swaps")
              n = sh("cat /sys/class/zram-control/hot_add")
              machine.succeed(
                  f"echo zstd > /sys/block/zram{n}/comp_algorithm",
                  f"echo {memtotal // 2} > /sys/block/zram{n}/disksize",
                  # -d: discard jak w zram-generator (options=discard)
                  f"mkswap /dev/zram{n} && swapon -d -p 100 /dev/zram{n}",
              )
              print(sh("cat /proc/swaps"))
              half = hog_disk_swap(hog)
              print(sh("cat /proc/swaps"))
              assert full < 16 * 1024, f"100%: disk swap +{full} KiB"
              assert half > 64 * 1024, f"50%: disk swap +{half} KiB"
              no_global_oom("zRAM")

          with subtest("oomd: kill pod presją w system.slice i user@1000.service, omit honorowany, -.slice bez kill"):
              # 30 s z hosta skrócone, żeby test nie czekał; limit 80% bez zmian
              machine.succeed(
                  "mkdir -p /etc/systemd/oomd.conf.d",
                  "printf '[OOM]\\nDefaultMemoryPressureDurationSec=2s\\n' > /etc/systemd/oomd.conf.d/test.conf",
                  "systemctl restart systemd-oomd",
              )
              # po restarcie oomd PID1 musi mu ponownie przekazać monitorowane cgroup
              for cg in ("/system.slice", "/user.slice/user-1000.slice/user@1000.service"):
                  machine.wait_until_succeeds(f"oomctl | grep -qx '\\s*Path: {cg}'")
              # jak nixos/tests/systemd-oomd.nix, ale bez swapu: przy samym
              # MemoryHigh zram tanio łyka zera i presja waha się 65–85%
              # (poniżej/powyżej progu); bez swapu throttling memory.high
              # trzyma proces w stallu ~100%, a reclaim skanuje strony plikowe
              bloat = "-p MemoryHigh=5M -p MemorySwapMax=0 ${pkgs.coreutils}/bin/tail /dev/zero"
              urun = "systemd-run --user --machine=alice@"

              def oom_killed(run, unit, cmd):
                  # --wait kończy się kodem ≠ 0, gdy jednostka padła — liczy się wynik
                  _, out = machine.execute(f"timeout 180 {run} --wait --unit={unit} {cmd} 2>&1")
                  if "Finished with result: oom-kill" not in out:
                      print(machine.execute("oomctl; cat /sys/fs/cgroup/system.slice/memory.pressure; swapon --show")[1])
                  return out

              for run in ("systemd-run", urun):
                  out = oom_killed(run, "bloat", bloat)
                  assert "Finished with result: oom-kill" in out, (run, out)
              # omit w user@1000.service (ten sam właściciel cgroup): sprawca
              # presji z omit przeżywa, ginie inny kandydat (64 MiB > init.scope)
              machine.succeed(f"{urun} --unit=bloat-omit -p ManagedOOMPreference=omit {bloat}")
              out = oom_killed(urun, "victim", "${pkgs.python3}/bin/python3 ${memHog} 64 /tmp/victim-ready")
              assert "Finished with result: oom-kill" in out, out
              # po kill oomd czeka 15 s (POST_ACTION_DELAY_USEC) — sprawdzić od razu
              machine.succeed(f"{user} is-active bloat-omit", f"{user} stop bloat-omit")
              # kontrola: -.slice nie jest monitorowany (enableRootSlice = false)
              machine.succeed(f"systemd-run --slice=nomon.slice --unit=bloat-nomon {bloat}")
              time.sleep(20)
              machine.require_unit_state("bloat-nomon.service", "active")
              machine.succeed("systemctl stop bloat-nomon")
              print(sh("journalctl -u systemd-oomd -b --no-pager | grep -i 'for killing'"))
        '';
      };
    };
}
