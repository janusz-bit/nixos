# LLM laptopa dla Hermesa: Hermes Agent na raspberry-pi-4 dostaje dostawcę
# strata-laptop, czyli serwer modelu uruchomiony ręcznie na laptopie (Strata,
# także bonsai-serve: ten sam port). Domyślnym modelem zostaje Claude; w Matrixie
# `/model qwen3.8-flash-next-coder-iq1_m --provider strata-laptop`.
#
# Droga: Hermes łączy się z 127.0.0.1:8080 na RPi, a gniazdo laptop-llm
# (Accept=yes) dla każdego połączenia uruchamia `ssh -W 127.0.0.1:8080` na konto
# hermes-llm laptopa. Nie ma stałego połączenia: przy wyłączonym laptopie albo
# poza domem połączenie kończy się po ConnectTimeout, a Hermes zgłasza błąd
# modelu. Strata dalej słucha tylko na localhost i nie ma portu w firewallu (RPi
# bierze adres z DHCP, więc reguły „tylko z RPi” i tak nie da się napisać).
#
# Granica zaufania (RPi jest mniej zaufane niż laptop):
# - hermes-llm na laptopie: konto systemowe bez powłoki (nologin) i bez grup;
#   klucz z from=<LAN>,restrict,port-forwarding, a blok Match w sshd zostawia
#   tylko lokalne przekierowanie do 127.0.0.1:8080. Bez -R, którym RPi zajęłoby
#   ten port pod nieobecność Straty i podsuwało odpowiedzi opencode i Prime
#   Agentowi; bez gniazd Unix.
# - Na RPi z gniazda korzysta tylko konto hermes (reguła iptables owner). Strata
#   bez klucza API pozwala klientowi spoza przeglądarki wczytać plik laptopa jako
#   obraz (z prawami konta, które ją uruchomiło), pobrać URL z laptopa
#   i wyładować model, więc usługi RPi wystawione do internetu (Nextcloud, Gitea,
#   Matrix) nie dostają tej drogi.
# - Klucz prywatny (hermes-llm-key.age) czyta tylko root; połączenie (DynamicUser)
#   dostaje go przez LoadCredential.
# Ryzyko resztkowe: Hermes po prompt injection może to samo co każdy klient
# Straty. Odczyt plików zamyka uruchomienie Straty z `--vision off` (obrazy Hermes
# czyta przez auxiliary.vision z Ollama Cloud).
#
# lockdown: z tunelu korzysta tylko hermes-agent, którego `lockdown on`
# zatrzymuje; sshd laptopa zostaje z założenia.
#
# Sprawdzenie: test VM `nix build -L .#checks.<system>.laptop-llm` (kvm). Po
# wdrożeniu, przy działającej Stracie, na RPi `sudo -u hermes curl -s
# http://127.0.0.1:8080/v1/models` i `journalctl -u 'laptop-llm@*'`; na laptopie
# `sudo sshd -T -C user=hermes-llm,host=rpi,addr=<IP RPi> | grep -E 'allowtcpforwarding|permitopen|allowstreamlocal'`.
_:
let
  user = "hermes-llm";
  # Domyślny port `strata launch` i bonsai-serve (ai/models.nix), ten sam po
  # obu stronach tunelu, więc URL dostawcy z katalogu ai.providers działa na RPi.
  port = 8080;
  target = "127.0.0.1:${toString port}";
in
{
  flake.modules.nixos.nixos-laptop-llm =
    { config, lib, ... }:
    let
      inherit (config.customTop) keys lan;
    in
    {
      users = {
        users.${user} = {
          isSystemUser = true;
          group = user;
          description = "Tunel Hermesa z raspberry-pi-4 do lokalnego LLM";
          openssh.authorizedKeys.keys = [
            ''from="${lan.subnet}",restrict,port-forwarding ${keys.users.hermes-llm}''
          ];
        };
        groups.${user} = { };
      };

      # mkAfter: wszystko po Match należy do bloku, a extraConfig idzie za
      # settings, więc blok musi zamykać sshd_config. `restrict` w kluczu nie
      # zawęża celu ani kierunku przekierowania — robi to dopiero ten blok.
      services.openssh.extraConfig = lib.mkAfter ''
        Match User ${user}
          AllowTcpForwarding local
          AllowStreamLocalForwarding no
          PermitOpen ${target}
      '';
    };

  flake.modules.nixos.rpi-laptop-llm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.customTop) keys lan;
      strata = config.ai.providers.strata.baseUrl;
      model = config.ai.models.qwen3-8-flash-next-coder-iq1_m;
      knownHosts = pkgs.writeText "laptop-llm-known-hosts" "${lan.laptop} ${keys.sshHostKeys.nixos}\n";
      # Firewall przy reloadzie czyści tylko własne łańcuchy, nie OUTPUT, więc
      # przed dodaniem reguła jest usuwana, żeby się nie mnożyła.
      ownerRule = "OUTPUT -o lo -p tcp -d 127.0.0.1 --dport ${toString port} -m owner ! --uid-owner ${config.services.hermes-agent.user} -j REJECT";
    in
    {
      age.secrets.hermes-llm-key.file = config.customTop.secretsDir + "/hermes-llm-key.age";

      systemd = {
        sockets.laptop-llm = {
          description = "Tunel Hermesa do LLM laptopa";
          wantedBy = [ "sockets.target" ];
          listenStreams = [ target ];
          socketConfig.Accept = true;
        };

        # -W: stdin/stdout (połączenie z gniazda) idą prosto do celu po stronie
        # laptopa. Klucz hosta laptopa przypięty, ssh_config pominięty.
        services."laptop-llm@" = {
          description = "Połączenie z LLM laptopa przez ssh";
          serviceConfig = {
            ExecStart = lib.escapeShellArgs [
              (lib.getExe config.programs.ssh.package)
              "-F"
              "/dev/null"
              "-i"
              "%d/key"
              "-o"
              "IdentitiesOnly=yes"
              "-o"
              "BatchMode=yes"
              "-o"
              "ConnectTimeout=5"
              "-o"
              "StrictHostKeyChecking=yes"
              "-o"
              "UserKnownHostsFile=${knownHosts}"
              "-W"
              target
              "${user}@${lan.laptop}"
            ];
            StandardInput = "socket";
            StandardError = "journal";
            DynamicUser = true;
            LoadCredential = "key:${config.age.secrets.hermes-llm-key.path}";
            ProtectHome = true;
            PrivateDevices = true;
            # AF_UNIX: nss-systemd (userdb przez varlink) dla użytkownika dynamicznego.
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };
      };

      networking.firewall = {
        extraCommands = ''
          iptables -D ${ownerRule} 2>/dev/null || true
          iptables -A ${ownerRule}
        '';
        extraStopCommands = ''
          iptables -D ${ownerRule} 2>/dev/null || true
        '';
      };

      # Model z katalogu ai.models bez enable: tu tylko jego id i kontekst
      # (asercja NVIDII dotyczy włączenia).
      services.hermes-agent.settings.providers.strata-laptop = {
        name = "Strata (laptop)";
        base_url = strata;
        default_model = model.id;
        models.${model.id}.context_length = model.context;
      };

      assertions = [
        {
          assertion = strata == "http://${target}/v1";
          message = "rpi-laptop-llm: ai.providers.strata.baseUrl (${strata}) nie wskazuje celu tunelu (${target}); zmień `port` w modules/hosts/laptop-llm.nix.";
        }
      ];
    };
}
