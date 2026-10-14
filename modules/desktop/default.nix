# Stacja robocza: wszystkie moduły desktop-* naraz (sesja Plasma 6, dźwięk,
# łączność, polski układ, druk, kernel CachyOS ze strojeniem, aplikacje,
# przeglądarki, narzędzia programistyczne i AI). Moduły zależne od GPU
# (OBS, Ollama, Zed) dopasowują się do hardware.nvidia z modułu sprzętu.
# Host bez części z nich importuje pojedyncze desktop-* zamiast agregatu.
{ self, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [
      self.modules.nixos.desktop-plasma
      self.modules.nixos.desktop-audio
      self.modules.nixos.desktop-connectivity
      self.modules.nixos.desktop-locale
      self.modules.nixos.desktop-printing
      self.modules.nixos.desktop-kernel
      self.modules.nixos.desktop-tuning
      self.modules.nixos.desktop-apps
      self.modules.nixos.desktop-obs
      self.modules.nixos.desktop-browsers
      self.modules.nixos.desktop-autostart
      self.modules.nixos.desktop-dev
      self.modules.nixos.desktop-devenv
      self.modules.nixos.desktop-podman
      self.modules.nixos.desktop-ai
    ];
  };
}
