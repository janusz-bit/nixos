_: {
  flake.modules.nixos.nixos-plasma-browser-integration =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      # Plasma Browser Integration — rozszerzenie "Plasma Integration"
      # (plasma-browser-integration@kde.org, zainstalowane w Helium) łączy się
      # z hostem przez native messaging. Moduł plasma6 w nixpkgs wystawia
      # manifest hosta w /etc/chromium i /etc/opt/chrome tylko pod
      # programs.chromium.enable (tutaj wyłączone: Helium z .deb +
      # ungoogled-chromium z systemPackages), więc przeglądarki go nie
      # znajdują — błąd "Specified native messaging host not found."
      # Stałe ścieżek są w binarce Helium; z /etc/chromium korzysta też
      # ungoogled-chromium. Sam pakiet (host + manifesty) jest w systemie
      # z modułu plasma6; Firefox obsługuje ten sam moduł przez
      # programs.firefox.nativeMessagingHosts.packages.
      environment.etc = lib.mkIf (!config.programs.chromium.enable) {
        "chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json".source =
          "${pkgs.kdePackages.plasma-browser-integration}/etc/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json";
        "opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json".source =
          "${pkgs.kdePackages.plasma-browser-integration}/etc/opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json";
      };
    };
}
