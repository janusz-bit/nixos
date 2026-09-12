# Dynamiczne VFIO — przekazanie NVIDIA dGPU (0000:01:00) do VM bez restartu systemu.
# Inspiracja: gist SpiderUnderUrBed (qemu hook + display-manager) i CRTified (vfio.nix).
#
# Zasada działania:
#   - GPU NIE jest statycznie związana z vfio-pci: host używa jej normalnie
#     (PRIME offload dla gier, CUDA/Ollama). Dopiero start VM "win11" wywołuje
#     hook qemu, który: zatrzymuje sesję graficzną (SDDM/Plasma) i ollamę,
#     wyładowuje moduły NVIDIA, podpina 0000:01:00.0 (karta) i 0000:01:00.1
#     (HDMI audio) pod vfio-pci, po czym wznawia sesję — Plasma wstaje na iGPU.
#   - Po zamknięciu VM hook robi odwrotnie (reattach + modprobe + restart sesji).
#   - Sesja użytkownika jest pinowana do iGPU przez symlink bez dwukropków
#     (/dev/dri/igpu-card, KWin dzieli KWIN_DRM_DEVICES po ":"); greeter i boot
#     pozostają domyślne. Funkcja audio dGPU zostaje na vfio-pci między cyklami.
#   - Monitor na wyjściu HDMI dGPU pokazuje obraz dopiero po zwrocie GPU do hosta.
#   - Definicja przykładowej VM: modules/hosts/nixos/win11-vm.xml (virsh define).
_: {
  flake.modules.nixos.nixos-vfio =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # Nazwa VM, dla której działa dynamiczny przekaz GPU
      vmName = "win11";
      cfgUser = config.customBot.defaultUser;
      # szablon VM w /nix/store — nietykalny dla obcinania plików w repo przy boot
      vfioVmXml = pkgs.writeText "win11-vm.xml" (builtins.readFile ./win11-vm.xml);

      qemuHook = pkgs.writeShellApplication {
        name = "vfio-qemu-hook";
        runtimeInputs = with pkgs; [
          libvirt
          systemd
          kmod
          lsof
          coreutils
          util-linux # logger
        ];
        text = ''
          GUEST_NAME="''${1:-}"
          OPERATION="''${2:-}"

          VGA_SLOT="0000:01:00.0"        # karta
          AUDIO_SLOT="0000:01:00.1"      # HDMI audio
          VGA_NODE="pci_0000_01_00_0"
          AUDIO_NODE="pci_0000_01_00_1"
          DGPU_CARD="/dev/dri/by-path/pci-0000:01:00.0-card"
          DGPU_RENDER="/dev/dri/by-path/pci-0000:01:00.0-render"

          log() {
            logger -t vfio-hook "$*" 2>/dev/null || true
            echo "[vfio-hook] $*" >&2
          }

          fail() {
            log "BŁĄD: $*"
            # spróbuj przywrócić sesję graficzną, żeby nie zostać bez pulpitu
            systemctl start display-manager.service 2>/dev/null || true
            exit 1
          }

          driver_of() {
            readlink "/sys/bus/pci/devices/$1/driver" 2>/dev/null || true
          }

          # PID-y procesów trzymających urządzenia dGPU (karta/audio/dri)
          gpu_users() {
            {
              lsof -t /dev/nvidia* 2>/dev/null || true
              if [ -e "$DGPU_CARD" ]; then lsof -t "$DGPU_CARD" 2>/dev/null || true; fi
              if [ -e "$DGPU_RENDER" ]; then lsof -t "$DGPU_RENDER" 2>/dev/null || true; fi
            } | sort -u || true
          }

          wait_gpu_free() {
            waited=0
            while [ -n "$(gpu_users)" ]; do
              if [ "$waited" -ge "$1" ]; then
                log "GPU nadal zajęta przez PID-y: $(gpu_users | tr '\n' ' ')"
                return 1
              fi
              sleep 1
              waited=$((waited + 1))
            done
            return 0
          }

          kill_gpu_holders() {
            pids="$(gpu_users)"
            if [ -z "$pids" ]; then
              return 0
            fi
            log "SIGTERM dla procesów trzymających GPU: $(echo "$pids" | tr '\n' ' ')"
            # shellcheck disable=SC2086
            kill -TERM $pids 2>/dev/null || true
            sleep 3
            pids="$(gpu_users)"
            if [ -n "$pids" ]; then
              log "SIGKILL dla: $(echo "$pids" | tr '\n' ' ')"
              # shellcheck disable=SC2086
              kill -KILL $pids 2>/dev/null || true
              sleep 1
            fi
            return 0
          }

          # podpięcie obu funkcji dGPU pod vfio-pci; true gdy oba na vfio-pci
          detach_gfx() {
            virsh --connect qemu:///system nodedev-detach "$VGA_NODE" >/dev/null 2>&1 || true
            virsh --connect qemu:///system nodedev-detach "$AUDIO_NODE" >/dev/null 2>&1 || true
            if driver_of "$VGA_SLOT" | grep -q vfio-pci && driver_of "$AUDIO_SLOT" | grep -q vfio-pci; then
              return 0
            fi
            return 1
          }

          # wyładowanie modułów NVIDIA; w razie zblokowania najpierw detach
          unload_nvidia() {
            try=0
            while true; do
              if modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null; then
                log "Moduły NVIDIA wyładowane"
                return 0
              fi
              detach_gfx || true
              try=$((try + 1))
              if [ "$try" -ge 10 ]; then
                return 1
              fi
              sleep 2
            done
          }

          # Hook obsługuje wyłącznie VM z przekazywaną GPU
          if [ "$GUEST_NAME" != "win11" ]; then
            exit 0
          fi

          if [ "$OPERATION" = "prepare" ]; then
            log "prepare: oddaję dGPU pod VM $GUEST_NAME"

            # 1. Zatrzymaj wszystko, co może trzymać dGPU (sesja graficzna, CUDA/ollama)
            systemctl stop ollama.service 2>/dev/null || true
            systemctl stop display-manager.service || fail "nie mogę zatrzymać display-manager"
            sleep 2

            # 2. Upewnij się, że nic nie trzyma GPU (ubij zbłąkane procesy)
            kill_gpu_holders
            wait_gpu_free 30 || fail "GPU nadal zajęta"

            # 3. Wyładuj moduły NVIDIA i podpięj urządzenia pod vfio-pci
            unload_nvidia || fail "nie udało się wyładować sterowników NVIDIA"
            if ! detach_gfx; then
              fail "nie udało się podpiąć GPU pod vfio-pci"
            fi

            # 4. Zabezpiecz moduły wirtualizacji i sieć NAT
            modprobe kvm_intel 2>/dev/null || true
            modprobe vfio_pci 2>/dev/null || true
            virsh --connect qemu:///system net-start default >/dev/null 2>&1 || true

            # 5. Sesja graficzna wraca — teraz na iGPU
            systemctl start display-manager.service || log "UWAGA: display-manager nie wystartował"
            log "dGPU przekazana VM $GUEST_NAME; sesja graficzna działa na iGPU"
            exit 0
          fi

          if [ "$OPERATION" = "release" ]; then
            log "release: zwracam dGPU hostowi"

            # Restart sesji, żeby KWin na świeżo wykrył powracającą GPU
            systemctl stop display-manager.service 2>/dev/null || true

            # Reset dGPU zanim wróci pod nvidia: Windows z aktywnym sterownikiem
            # zostawia kartę w stanie, który potrafi wywrócić inicjalizację
            # ACPI/SBIOS po rebindzie (hard freeze obserwowany 2026-09-12 13:04).
            if ! echo 1 > "/sys/bus/pci/devices/$VGA_SLOT/reset" 2>/dev/null; then
              log "UWAGA: reset dGPU nie powiódł się, kontynuuję"
            fi
            sleep 2

            # Reattach TYLKO VGA. Funkcja audio zostaje na vfio-pci:
            # jej powrót pod snd_hda_intel sprawiał, że PipeWire nowej sesji
            # otwierał PCM karty NVIDIA (kernel: „Enabling HDA controller”
            # w momencie logowania) — a to pchnięcie poprzedzało oba
            # zamrożenia (2026-09-12 13:03 i 13:18). Monitor jest na iGPU,
            # więc host nie potrzebuje HDMI audio dGPU.
            virsh --connect qemu:///system nodedev-reattach "$VGA_NODE" >/dev/null 2>&1 || true

            try=0
            while true; do
              if ! driver_of "$VGA_SLOT" | grep -q vfio-pci; then
                break
              fi
              echo "$VGA_SLOT" > /sys/bus/pci/drivers_probe 2>/dev/null || true
              try=$((try + 1))
              if [ "$try" -ge 10 ]; then
                log "UWAGA: slot VGA nadal na vfio-pci po reattach"
                break
              fi
              sleep 2
            done

            # Usuń nieświeże węzły /dev/nvidia* — mają STALE numery major
            # (nvidia-uvm dostaje major dynamicznie), a udev nie nadpisze ich
            # (mknod kończy się błędem, gdy plik istnieje). Proces otwierający
            # taki węzeł trafia na złe urządzenie — realny wektor zamrożenia.
            rm -f /dev/nvidia* 2>/dev/null || true

            # doładuj sterowniki NVIDIA
            modprobe nvidia 2>/dev/null || true
            modprobe nvidia_modeset 2>/dev/null || true
            modprobe nvidia_drm 2>/dev/null || true
            modprobe nvidia_uvm 2>/dev/null || true

            # Gwarancja świeżych węzłów z POPRAWNYMI majorami — udev bywa w tym
            # w wyścigu (mknod EEXIST przy równoległych zdarzeniach), a CUDA
            # wymaga zgodności (nvidia-uvm dostaje major dynamiczny per modprobe).
            while read -r minor; do
              [ -n "$minor" ] || continue
              [ -e "/dev/nvidia$minor" ] || mknod -m 666 "/dev/nvidia$minor" c 195 "$minor"
            done < <(cat /proc/driver/nvidia/gpus/*/information | grep Minor | cut -d ' ' -f 4)
            [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c 195 255
            [ -e /dev/nvidia-modeset ] || mknod -m 666 /dev/nvidia-modeset c 195 254
            uvm_major="$(grep nvidia-uvm /proc/devices | cut -d ' ' -f 1)"
            rm -f /dev/nvidia-uvm /dev/nvidia-uvm-tools
            mknod -m 666 /dev/nvidia-uvm c "$uvm_major" 0
            mknod -m 666 /dev/nvidia-uvm-tools c "$uvm_major" 1

            # Awaryjne odtworzenie symlinka bez dwukropków (KWin rozbija
            # KWIN_DRM_DEVICES po ":"). Podstawą jest reguła udev + tmpfiles.
            mkdir -p /dev/dri
            ln -sfn /dev/dri/by-path/pci-0000:00:02.0-card /dev/dri/igpu-card

            # chwila na ustabilizowanie nvidia-drm (sondy ACPI/backlight)
            sleep 3
            systemctl start display-manager.service

            # CUDA dopiero po ożywieniu sesji — mniejsze ryzyko wyścigu z KWin
            sleep 5
            systemctl start ollama.service 2>/dev/null || true
            log "dGPU zwrócona hostowi (PRIME offload/CUDA znów dostępne)"
            exit 0
          fi

          exit 0
        '';
      };
    in
    {
      # --- IOMMU / KVM ---
      # DMAR jest obecny w ACPI (VT-d aktywny w BIOS); iommu=pt ogranicza
      # narzut IOMMU dla urządzeń hosta.
      boot.kernelParams = [
        "intel_iommu=on"
        "iommu=pt"
        "kvm.ignore_msrs=1"
        "kvm.report_ignored_msrs=0"
      ];
      boot.kernelModules = [
        "kvm_intel"
        "vfio"
        "vfio_pci"
      ];

      # /dev/vfio/<grupa-IOMMU> dla qemu działającego bez roota
      # + stabilny symlink /dev/dri/igpu-card na kartę iGPU. KWin rozbija
      # KWIN_DRM_DEVICES po dwukropkach (by-path zawiera adres PCI), więc
      # musimy dać mu ścieżkę bez ":". DEVPATH jest niezależny od kolejności
      # reguł (nie zależy od ENV{ID_PATH} ustawianego w 60-drm.rules).
      services.udev.extraRules = ''
        SUBSYSTEM=="vfio", OWNER="root", GROUP="kvm", MODE="0660"
        SUBSYSTEM=="drm", KERNEL=="card[0-9]*", DEVPATH=="*/0000:00:02.0/drm/*", SYMLINK+="dri/igpu-card"
      '';

      virtualisation.libvirtd = {
        enable = true;
        qemu = {
          runAsRoot = false;
          # emulowany TPM 2.0 (swtpm) — wymagany przez Windows 11
          swtpm.enable = true;
        };
        # QEMU hook: wykonywany przy prepare/release domeny — serce dynamicznego VFIO
        hooks.qemu."vfio-nvidia" = lib.getExe qemuHook;
      };

      # Wymóg modułu libvirtd (assert) + polityki dostępu dla użytkownika
      security.polkit.enable = true;

      users.users.${cfgUser}.extraGroups = [ "libvirtd" ];
      users.users.qemu-libvirtd.extraGroups = [ "kvm" ];

      programs.virt-manager.enable = true;

      environment = {
        systemPackages = with pkgs; [
          virt-viewer
          looking-glass-client
          pciutils
        ];

        # -c qemu:///system jest konieczne: jako nie-root virsh domyślnie łączy się
        # z qemu:///session (pusta, osobna instancja) i nie widzi systemowych domen
        shellAliases = {
          vm-start = "virsh -c qemu:///system start ${vmName}";
          vm-stop = "virsh -c qemu:///system shutdown ${vmName}";
          vm-status = "virsh -c qemu:///system list --all";
          vm-console = "virt-viewer -c qemu:///system ${vmName}";
        };
      };

      systemd = {
        # bufor współdzielony looking-glass (używany, gdy VM ma urządzenie shmem)
        tmpfiles.rules = [
          "f /dev/shm/looking-glass 0660 ${cfgUser} qemu-libvirtd -"

          # Kopia zapasowa symlinka dla KWin (podstawą jest reguła udev).
          # Cel może być przejściowo "wiszący" — do zakończenia coldplug udev.
          "L+ /dev/dri/igpu-card - - - - /dev/dri/by-path/pci-0000:00:02.0-card"

          # Pinning sesji użytkownika do iGPU (greeter celowo zostaje domyślny —
          # boot wygląda identycznie jak dziś). Plasma 6 źródłuje
          # ~/.config/plasma-workspace/env/*.sh na starcie sesji, więc zmienna
          # trafia tylko do KWin zalogowanego użytkownika.
          "d /home/${cfgUser}/.config/plasma-workspace/env 0755 ${cfgUser} users - -"
          "f+ /home/${cfgUser}/.config/plasma-workspace/env/igpu-kwin.sh 0644 ${cfgUser} users - export KWIN_DRM_DEVICES=/dev/dri/igpu-card"
        ];

        # Deklaratywne zdefiniowanie VM z szablonu w /nix/store.
        # Powód: plik win11-vm.xml w repo bywał obcinany do 0 bajtów przy reboot
        # (obserwowane 2x na BTRFS, mtime w minuty po starcie systemu) — kopia w
        # store jest nietykalna. Unit jest idempotentny: definiuje tylko wtedy,
        # gdy domena jeszcze nie istnieje (ręczne zmiany przez virt-manager
        # zostają nietknięte).
        services.vfio-define-vm = {
          description = "Idempotentne zdefiniowanie domeny ${vmName} z szablonu w /nix/store";
          after = [ "libvirtd.service" ];
          wants = [ "libvirtd.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            if ! ${pkgs.libvirt}/bin/virsh -c qemu:///system dominfo ${vmName} >/dev/null 2>&1; then
              echo "vfio-define-vm: domena ${vmName} nie istnieje, definiuję z ${vfioVmXml}"
              ${pkgs.libvirt}/bin/virsh -c qemu:///system define ${vfioVmXml}
            else
              echo "vfio-define-vm: domena ${vmName} już istnieje - pomijam"
            fi
          '';
        };
      };
    };
}
