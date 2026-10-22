# Stacja robocza: wszystkie moduły desktop-* naraz. Moduły zależne od GPU (OBS,
# Ollama, llama.cpp, Zed) idą za hardware.nvidia z modułu sprzętu; host bez
# części funkcji importuje pojedyncze desktop-* zamiast agregatu.
{ self, ... }:
{
  flake.modules.nixos.desktop = _: {
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
      self.modules.nixos.desktop-brulion
      self.modules.nixos.desktop-dev
      self.modules.nixos.desktop-devenv
      self.modules.nixos.desktop-podman
      self.modules.nixos.desktop-ai
    ];
  };
}
