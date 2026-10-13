# Helium Browser (fork ungoogled-chromium): pakiet lokalny
# modules/packages/_helium (overlay local-packages; tam opis, czemu nie
# github:ominit/helium-browser-flake) i jego konfiguracja jako polityki
# Chromium. Sandbox Chromium działa na user namespaces (domyślnie włączone).
#
# Helium nie ma brandingu Chrome, więc czyta polityki tylko z wkompilowanego
# /etc/chromium/policies (w profilu użytkownika nie ma loadera polityk), czyli
# tam, gdzie pisze moduł programs.chromium. Polityki managed są zablokowane w
# helium://settings. Te same pliki czyta ungoogled-chromium z packages.nix.
#
# Rozszerzenia: ExtensionInstallForcelist z samymi ID. Helium kieruje
# pobieranie z Chrome Web Store przez proxy Helium services (patch
# proxy-extension-downloads) tylko dla domyślnego adresu aktualizacji; wpis
# "ID;https://clients2.google.com/service/update2/crx" ominąłby proxy. Bez
# zgody na Helium services z onboardingu (helium.services.user_consented)
# rozszerzenia czekają w kolejce. Rozszerzenie zainstalowane wcześniej ręcznie
# Chromium tylko przepina na lokalizację polityki
# (ExternalProviderManager::OnExternalExtensionUpdateUrlFound), dane zostają.
#
# Sprawdzenie: helium://policy (polityki ze statusem OK), helium://extensions
# (rozszerzenia zainstalowane przez administratora, bez przycisku usuwania).
_: {
  flake.modules.nixos.desktop-browsers =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.helium ];

      programs.chromium = {
        # Moduł plasma6 ustawia już enablePlasmaBrowserIntegration, ale
        # manifest hosta w /etc/chromium/native-messaging-hosts (i polityki)
        # zapisuje dopiero enable; bez niego "Plasma Integration" zgłasza
        # "Specified native messaging host not found". Nic nie instaluje.
        enable = true;

        extensions = [
          "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
          "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
          "cimiefiiaegbelhefglklhhakcgmhkai" # Plasma Integration
          "gebbhagfogifgggkldgodflihgfeippi" # Return YouTube Dislike
        ];

        extraOpts = {
          # Przywracanie poprzedniej sesji (domyślnie: strona nowej karty).
          RestoreOnStartup = 1;
          # Hosty native messaging tylko z /etc/chromium (Nix). Manifest w
          # ~/.config/<przeglądarka>/NativeMessagingHosts ma pierwszeństwo
          # (LaunchContext::FindManifest) i wskazuje konkretną ścieżkę w
          # store: po aktualizacji Plasmy przeglądarka uruchamia stary host,
          # a po GC żaden.
          NativeMessagingUserLevelHosts = false;
        };
      };
    };
}
