# Przeglądarki: Helium, ungoogled-chromium, Firefox, Tor Browser.
#
# Helium (pakiet lokalny modules/packages/_helium) nie ma brandingu Chrome, więc
# czyta polityki tylko z wkompilowanego /etc/chromium/policies, gdzie pisze
# programs.chromium; te same pliki czyta ungoogled-chromium. Polityki managed są
# zablokowane w helium://settings.
#
# Rozszerzenia: same ID, bo Helium kieruje Chrome Web Store przez proxy Helium
# services tylko dla domyślnego adresu aktualizacji ("ID;https://clients2…"
# ominąłby proxy); bez zgody na Helium services z onboardingu czekają w kolejce.
# Rozszerzenie zainstalowane wcześniej ręcznie przechodzi pod politykę, dane
# zostają.
#
# Sprawdzenie: helium://policy (status OK), helium://extensions (zainstalowane
# przez administratora, bez przycisku usuwania).
_: {
  flake.modules.nixos.desktop-browsers =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        helium
        ungoogled-chromium
        tor-browser
      ];

      programs.firefox.enable = true;

      programs.chromium = {
        # plasma6 ustawia enablePlasmaBrowserIntegration, ale manifest hosta w
        # /etc/chromium/native-messaging-hosts zapisuje dopiero enable (bez niego
        # "Specified native messaging host not found"). Nic nie instaluje.
        enable = true;

        extensions = [
          "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
          "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
          "cimiefiiaegbelhefglklhhakcgmhkai" # Plasma Integration
          "gebbhagfogifgggkldgodflihgfeippi" # Return YouTube Dislike
        ];

        extraOpts = {
          RestoreOnStartup = 1; # poprzednia sesja zamiast strony nowej karty
          # Hosty native messaging tylko z /etc/chromium: manifest z ~/.config ma
          # pierwszeństwo i wskazuje konkretny store path, więc po aktualizacji
          # Plasmy startuje stary host, a po GC żaden.
          NativeMessagingUserLevelHosts = false;
        };
      };
    };
}
