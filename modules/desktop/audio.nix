# Dźwięk: PipeWire z warstwami ALSA (także 32-bit dla gier) i PulseAudio;
# rtkit daje PipeWire priorytet czasu rzeczywistego.
# Sprawdzenie: `pactl info | grep 'Server Name'` → PulseAudio (on PipeWire).
_: {
  flake.modules.nixos.desktop-audio = _: {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    security.rtkit.enable = true;
  };
}
