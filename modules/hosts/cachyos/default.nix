{ inputs, self, ... }:
{
  flake.homeConfigurations."dinosaur@cachyos" = inputs.home-manager.lib.homeManagerConfiguration {
    system = "x86_64-linux";

    modules = [
      self.homeModules.base-home
      {
        # Założyłem użytkownika "dinosaur" na podstawie Twojego katalogu domowego.
        # Zmień na inną nazwę (np. "janusz-bit"), jeśli na CachyOS masz innego użytkownika.
        home.username = "dinosaur";
        home.homeDirectory = "/home/dinosaur";

        # Wersja stanu ustawiona na taką samą jak w konfiguracji WSL
        home.stateVersion = "25.05";
      }
    ];
  };
}
