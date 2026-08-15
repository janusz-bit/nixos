#!/usr/bin/env bash
# gpu — zarządzanie dGPU NVIDIA RTX 5060 Laptop (01:00.0 VGA + 01:00.1 audio)
# Wiki: https://wiki.nixos.org/wiki/PCI_passthrough
set -euo pipefail

VGA=0000:01:00.0
AUDIO=0000:01:00.1
SHORT_VGA=01:00.0
SHORT_AUDIO=01:00.1

XML_VGA="<hostdev mode='subsystem' type='pci' managed='yes'><source><address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/></source></hostdev>"
XML_AUDIO="<hostdev mode='subsystem' type='pci' managed='yes'><source><address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/></source></hostdev>"

current_driver() {
  local dev=$1
  if [[ -L /sys/bus/pci/devices/$dev/driver ]]; then
    basename "$(readlink /sys/bus/pci/devices/$dev/driver)"
  else
    echo "(brak)"
  fi
}

status() {
  echo "=== $SHORT_VGA (VGA) ==="
  lspci -nnk -s $SHORT_VGA
  echo "=== $SHORT_AUDIO (audio) ==="
  lspci -nnk -s $SHORT_AUDIO
  echo
  echo "Sterownik VGA:   $(current_driver $VGA)"
  echo "Sterownik audio: $(current_driver $AUDIO)"
  if grep -q "vfio-pci.ids=" /proc/cmdline; then
    echo "Tryb boot: vfio-pci.ids w cmdline (GPU przypisana do vfio-pci)"
  else
    echo "Tryb boot: domyślny (GPU dostępna dla sterownika nvidia)"
  fi
}

to_vfio() {
  local dev drv
  echo "[1/4] Odpinanie urządzeń od sterownika hosta..."
  for dev in $VGA $AUDIO; do
    drv=$(current_driver $dev)
    if [[ $drv != "(brak)" && $drv != "vfio-pci" ]]; then
      echo "  $dev: odłączam od $drv"
      echo $dev | sudo tee /sys/bus/pci/drivers/$drv/unbind > /dev/null
    fi
  done
  echo "[2/4] Wymuszanie sterownika vfio-pci..."
  sudo modprobe vfio_pci
  for dev in $VGA $AUDIO; do
    echo vfio-pci | sudo tee /sys/bus/pci/devices/$dev/driver_override > /dev/null
    echo $dev | sudo tee /sys/bus/pci/drivers_probe > /dev/null
  done
  echo "[3/4] Usuwanie modułów nvidia z pamięci..."
  sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2> /dev/null \
    || echo "  Uwaga: część modułów nvidia nadal w użyciu"
  echo "[4/4] Wynik:"
  status
  echo
  echo "Gotowe. Dodaj urządzenia do VM: gpu attach <nazwa-vm> albo virt-manager (Add Hardware -> PCI Host Device)."
}

to_host() {
  local dev drv
  echo "[1/4] Odpinanie od vfio-pci..."
  for dev in $VGA $AUDIO; do
    drv=$(current_driver $dev)
    if [[ $drv == "vfio-pci" ]]; then
      echo $dev | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind > /dev/null || {
        echo "BŁĄD: $dev jest zajęty. Działa VM z tą kartą? Sprawdź: sudo virsh list, wyłącz: sudo virsh destroy <nazwa>"
        exit 1
      }
    fi
    echo -n "" | sudo tee /sys/bus/pci/devices/$dev/driver_override > /dev/null
  done
  echo "[2/4] Ładowanie sterownika nvidia..."
  sudo modprobe nvidia
  echo "[3/4] Ponowne sondowanie urządzeń..."
  for dev in $VGA $AUDIO; do
    echo $dev | sudo tee /sys/bus/pci/drivers_probe > /dev/null
  done
  echo "[4/4] Wynik:"
  status
  echo
  echo "Jeśli GPU nie wróciła do nvidia, potrzebny reboot do domyślnego wpisu Limine (alias: update)."
}

attach() {
  local vm=$1
  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf $tmp" EXIT
  printf "%s" "$XML_VGA" > $tmp/vga.xml
  printf "%s" "$XML_AUDIO" > $tmp/audio.xml
  sudo virsh attach-device $vm $tmp/vga.xml --live
  sudo virsh attach-device $vm $tmp/audio.xml --live
  echo "Podłączono GPU (VGA + audio) do VM $vm."
}

detach() {
  local vm=$1
  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf $tmp" EXIT
  printf "%s" "$XML_VGA" > $tmp/vga.xml
  printf "%s" "$XML_AUDIO" > $tmp/audio.xml
  sudo virsh detach-device $vm $tmp/vga.xml --live
  sudo virsh detach-device $vm $tmp/audio.xml --live
  echo "Odłączono GPU (VGA + audio) od VM $vm."
}

usage() {
  cat <<EOF
gpu — zarządzanie NVIDIA RTX 5060 Laptop GPU (passthrough/VFIO)

Użycie: gpu <komenda> [nazwa-vm]

  status          sterowniki GPU + tryb boot
  vfio            runtime: przełącz GPU na vfio-pci (przygotowanie do passthrough)
  host            runtime: oddaj GPU sterownikowi nvidia
  attach <vm>     hotplug: podłącz GPU + audio do działającej VM
  detach <vm>     hotplug: odłącz GPU + audio od działającej VM
  help            ten tekst
EOF
}

cmd=status
if [[ $# -ge 1 ]]; then
  cmd=$1
fi

case $cmd in
  status) status ;;
  vfio) to_vfio ;;
  host) to_host ;;
  attach)
    if [[ $# -lt 2 ]]; then echo "Użycie: gpu attach <nazwa-vm>"; exit 1; fi
    attach $2
    ;;
  detach)
    if [[ $# -lt 2 ]]; then echo "Użycie: gpu detach <nazwa-vm>"; exit 1; fi
    detach $2
    ;;
  help | -h | --help) usage ;;
  *)
    echo "Nieznana komenda: $cmd"
    usage
    exit 1
    ;;
esac
