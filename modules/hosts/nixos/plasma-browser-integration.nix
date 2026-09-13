_: {
  flake.modules.nixos.nixos-plasma-browser-integration = {
    # Plasma Browser Integration — rozszerzenie "Plasma Integration"
    # (plasma-browser-integration@kde.org, zainstalowane w Helium) łączy się
    # z hostem przez native messaging. Moduł plasma6 w nixpkgs ustawia już
    # enablePlasmaBrowserIntegration + pakiet, ale manifesty hosta w
    # /etc/chromium i /etc/opt/chrome wystawia dopiero programs.chromium.
    # enable — ta opcja NICZEGO nie instaluje (pisze tylko polityki i
    # manifesty do /etc). Bez tego Helium (paczka .deb) i ungoogled-chromium
    # pokazują błąd "Specified native messaging host not found." Firefox
    # obsługuje ten sam moduł przez programs.firefox.nativeMessagingHosts.
    programs.chromium.enable = true;
  };
}
