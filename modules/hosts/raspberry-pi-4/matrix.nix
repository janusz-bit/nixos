# Serwer Matrix (continuwuity) na RPi wyłącznie dla tailnetu: kanał
# powiadomień agentów AI (bot @notify, hosts/matrix-notify.nix) czytany
# w aplikacji Matrix na telefonie i laptopie. Słucha na 127.0.0.1:6167,
# Tailscale Serve wystawia go pod https://<RPi>.<tailnet>:8448 (ten adres
# z portem wpisuje się w aplikacji jako homeserver), server_name to nazwa RPi
# w tailnecie.
#
# Granica zaufania:
# - Bez federacji, bez zaufanych serwerów kluczy i bez sprawdzania ogłoszeń:
#   serwer nie łączy się z innymi serwerami Matrix, a z tailnetu dociera tylko
#   przez Serve. Wychodzą jedynie pushe do bramki push aplikacji (pusher
#   rejestruje sama aplikacja). Lokalnie bez reguły owner (users = null), bo
#   Matrix uwierzytelnia każde żądanie tokenem dostępu.
# - Rejestracja tylko z tokenem. Na pustym serwerze działa wyłącznie
#   jednorazowy token pierwszego konta z journala, a to konto zostaje
#   administratorem; dlatego bot zakłada się dopiero po koncie właściciela.
#   Kolejne konta: token z continuwuity-registration-token.age
#   (LoadCredential).
#
# Jednorazowo: token pierwszego konta z `journalctl -u continuwuity -b | grep
# "registration token"` i w aplikacji Matrix (Element, FluffyChat) założyć na
# https://<RPi>.<tailnet>:8448 konto o nazwie customTop.users.laptop. Token
# dla kolejnych kont: `sudo agenix -d continuwuity-registration-token.age -i
# /root/.ssh/id_ed25519` w modules/_secrets/ na laptopie.
# Administracja: pokój #admins na serwerze (`!admin --help`).
#
# Sprawdzenie: `systemctl status continuwuity`, `curl -s
# http://127.0.0.1:6167/_matrix/client/versions`, z urządzenia w tailnecie
# https://<RPi>.<tailnet>:8448/_matrix/client/versions.
_: {
  flake.modules.nixos.rpi-matrix =
    { config, ... }:
    let
      port = 6167;
      servePort = 8448;
      credential = "registration-token";
    in
    {
      age.secrets.continuwuity-registration-token.file =
        config.customTop.secretsDir + "/continuwuity-registration-token.age";

      services.matrix-continuwuity = {
        enable = true;
        settings.global = {
          server_name = "${config.networking.hostName}.${config.customTop.tailnet.domain}";
          address = [ "127.0.0.1" ];
          port = [ port ];
          allow_registration = true;
          # Plik czyta sam serwer przy starcie, z katalogu poświadczeń
          # jednostki (DynamicUser nie czyta plików agenix roota).
          registration_token_file = "/run/credentials/continuwuity.service/${credential}";
          allow_federation = false;
          trusted_servers = [ ];
          allow_announcements_check = false;
          # Domyślny sufiks dopisuje znak flagi do nazwy każdego nowego konta.
          new_user_displayname_suffix = "";
        };
      };

      systemd.services.continuwuity.serviceConfig.LoadCredential = [
        "${credential}:${config.age.secrets.continuwuity-registration-token.path}"
      ];

      customBot = {
        tailscaleServe.${toString servePort}.port = port;
        lockdownServices = [ "continuwuity" ];
      };
    };
}
