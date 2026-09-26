# Temporary fix dla AVF kernel patch (nixpkgs linux 6.1.188) — patrz temporary-fixes.md.
# avf module stosuje arm64-balloon.patch z android-16.0.0_r3; ostatni hunk (usunięcie
# __virtio_clear_bit(vdev, VIRTIO_F_ACCESS_PLATFORM)) zakłada kontekst sprzed
# backportu "disable indirect descriptors" (6.1.188 wstawił blok komentarza +
# __virtio_clear_bit(VIRTIO_RING_F_INDIRECT_DESC) między F_REPORTING a ACCESS_PLATFORM),
# więc GNU patch nie znajduje kontekstu, wykrywa "Reversed (or previously applied)"
# i pomija hunk → *.rej → build kernela pada.
# Rozwiązanie: pełna lista boot.kernelPatches (mkForce) z POPRAWIONYM patchem
# (hunk przesunięty za blok indirect-desc; zweryfikowany na vanilla 6.1.188).
# Patche cpufreq/balloon są skopiowane lokalnie (bez fetchgit w ewaluacji tej opcji).
# structuredExtraConfig 1:1 z avf module (droid jest zawsze aarch64).
{
  lib,
  ...
}:
{
  boot.kernelPatches = lib.mkForce [
    {
      name = "avf-ballon";
      patch = ./arm64-balloon-6.1.188.patch;
      structuredExtraConfig = with lib.kernel; {
        SND_VIRTIO = module;
        SND = yes;
        SOUND = yes;
      };
    }
    {
      name = "avf-cpufreq";
      patch = ./virtual-cpufreq.patch;
      structuredExtraConfig = with lib.kernel; {
        CPU_FREQ = yes;
        IKCONFIG = yes;
        IKCONFIG_PROC = yes;
        ANDROID_V_CPUFREQ_VIRT = yes;
      };
    }
  ];
}
