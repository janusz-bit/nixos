{ inputs, self, ... }:
{
  flake.homeConfigurations."dinosaur@cachyos" = inputs.home-manager.lib.homeManagerConfiguration {
    # Założyłem, że używasz x86_64-linux
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # Przekazujemy inputs i self do wszystkich modułów
    extraSpecialArgs = { inherit inputs self; };

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
