# Skille agentów AI na RPi: skille własne bez paczek i bez lokalnych modeli na
# GPU. Tylko wybór; definicje są w modules/ai/.
_: {
  flake.modules.nixos.rpi-ai = _: {
    ai.skills = {
      nixos-system.enable = true;
      obscura.enable = true;
    };
  };
}
