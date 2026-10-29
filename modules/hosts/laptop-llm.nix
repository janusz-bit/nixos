# LLM laptopa dla Hermesa: Hermes Agent na raspberry-pi-4 dostaje dostawcę
# strata-laptop, czyli Stratę (Qwen3.8-Flash-Next Coder IQ1_M) na laptopie,
# uruchamianą przy pierwszym żądaniu i zatrzymywaną po 15 min bez żądań.
# Domyślnym modelem zostaje Claude; w Matrixie
# `/model qwen3.8-flash-next-coder-iq1_m --provider strata-laptop`.
#
# Droga żądania:
# - RPi: Hermes łączy się z 127.0.0.1:8090; gniazdo laptop-llm (Accept=yes) dla
#   każdego połączenia uruchamia `ssh -W 127.0.0.1:8090` na konto hermes-llm
#   laptopa. Przy wyłączonym laptopie albo poza domem połączenie kończy się po
#   ConnectTimeout i Hermes zgłasza błąd modelu.
# - Laptop: gniazdo strata-hermes-proxy (127.0.0.1:8090) uruchamia
#   systemd-socket-proxyd, który przez Wants= podnosi strata-hermes (`strata
#   serve` na 127.0.0.1:8095) i czeka, aż ta odpowie na /health — Strata otwiera
#   port dopiero po załadowaniu modelu, więc pierwsze żądanie czeka na
#   załadowanie. Proxy kończy się po 15 min bez połączeń, a strata-hermes
#   (StopWhenUnneeded) razem z nim, co oddaje VRAM i RAM.
# - Przed startem strata-hermes sprawdza dGPU: Strata wypełnia VRAM cache'em
#   ekspertów (prawie całe 8 GB), więc przy grze, bonsai-serve albo ręcznej
#   Stracie odmawia. Wants=, nie Requires=: nieudany start Straty przy Requires= zostawiłby
#   połączenie w kolejce gniazda, systemd ponawiałby start w pętli aż do
#   trigger-limit-hit i gniazdo przestałoby przyjmować żądania. Tu proxy rusza
#   mimo to, zamyka czekające połączenia (backend nie słucha) i kończy się po
#   sekundzie, więc następne żądanie znowu sprawdza GPU.
#
# Granica zaufania (RPi jest mniej zaufane niż laptop):
# - hermes-llm: konto systemowe bez powłoki (nologin) i bez grup; klucz z
#   from=<LAN>,restrict,port-forwarding, a blok Match w sshd zostawia tylko
#   lokalne przekierowanie do 127.0.0.1:8090. Bez -R, którym RPi zajęłoby port
#   lokalnego LLM i podsuwało odpowiedzi opencode i Prime Agentowi; bez gniazd Unix.
# - Strata dla Hermesa to osobna instancja na koncie systemowym strata (dane
#   w /var/lib/strata, bez dostępu do /home), z --offline (bez pobierania obrazów
#   z URL-i i bez narzędzi MCP), bez wizji (Strata bez klucza API czyta lokalne
#   ścieżki wysłane jako obraz) i z siecią tylko do localhost.
# - Na RPi z gniazda korzysta tylko konto hermes (reguła iptables owner), więc
#   usługi wystawione do internetu (Nextcloud, Gitea, Matrix) nie dostają tej
#   drogi. Klucz prywatny (hermes-llm-key.age) czyta tylko root; połączenie
#   (DynamicUser) dostaje go przez LoadCredential.
# Ryzyko resztkowe: każde konto laptopa (także claude-remote) może przez
# 127.0.0.1:8090 uruchomić Stratę; kontrola dGPU chroni przed tym gry.
#
# Jednorazowo (Strata nie pobiera niczego w jednostce): `strata-hermes-setup`
# na laptopie pobiera model do /var/lib/strata (ok. 90 GB) i zapisuje run
# config. Pliki ręcznej Straty można skopiować bez zajmowania miejsca (btrfs):
# przed pierwszym startem `sudo -u strata mkdir -p /var/lib/strata/.local/share/strata`,
# `sudo cp -a --reflink=always ~/.local/share/strata/Strata-data /var/lib/strata/.local/share/strata/`,
# `sudo chown -R strata:strata /var/lib/strata/.local`, potem `strata-hermes-setup`.
# Run config wskazuje ścieżki store pakietu strata; gdy GC je usunie, wrapper
# kasuje config, a ExecStartPre pisze go od nowa z plików, które już są.
#
# lockdown: tunel idzie przez sshd laptopa, który zostaje z założenia; przy CVE
# w Stracie `sudo systemctl stop strata-hermes-proxy.socket` na laptopie.
#
# Sprawdzenie: test VM `nix build -L .#checks.<system>.laptop-llm` (kvm). Po
# wdrożeniu na RPi `sudo -u hermes curl -s http://127.0.0.1:8090/v1/models`
# (pierwszy raz czeka na załadowanie), na laptopie `systemctl status
# strata-hermes`, `journalctl -u strata-hermes -u strata-hermes-proxy -b`
# i `sudo sshd -T -C user=hermes-llm,host=rpi,addr=<IP RPi> | grep -E 'allowtcpforwarding|permitopen|allowstreamlocal'`.
_:
let
  user = "hermes-llm";
  # Port tunelu, ten sam po obu stronach; inny niż 8080 ręcznej Straty
  # i bonsai-serve.
  port = 8090;
  target = "127.0.0.1:${toString port}";
in
{
  flake.modules.nixos.nixos-laptop-llm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.customTop) keys lan;
      model = config.ai.models.qwen3-8-flash-next-coder-iq1_m;
      strataUser = "strata";
      stateDir = "/var/lib/strata";
      # Domyślny port serwera Straty (serve/server.py).
      backendPort = 8095;
      # Rozmiar z katalogu Straty; nazwa run configu to strata-<tag rodziny><rozmiar>.json (setup.py).
      size = "IQ1_M";
      runConfig = "${stateDir}/.local/share/strata/install/strata-coder-${lib.toLower size}.json";
      strata = lib.getExe pkgs.strata;
      # Jak `strata launch --family coder --model IQ1_M --context 128k --kv int8
      # --set kv-resident=20480`: KV int8 leży w RAM, a w VRAM tylko okno 20480
      # tokenów. Setup sam włącza to strumieniowanie dopiero, gdy RAM mieści
      # model i KV (32 GB to za mało dla IQ1_M), więc jak launch dopisuje
      # --kv-resident do args run configu.
      kv = "int8";
      kvResident = 20480;

      # Instaluje model i pisze run config z kontekstem modelu z ai.models.
      setup = pkgs.writeShellApplication {
        name = "strata-hermes-setup";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [ "$(id -un)" != ${lib.escapeShellArg strataUser} ]; then
            exec /run/wrappers/bin/sudo -u ${lib.escapeShellArg strataUser} -H -- "$0" "$@"
          fi
          # Argumenty setup.py dopiero po `--` (inaczej parsuje je samo `strata`).
          exec ${strata} install -- --family coder --model ${size} --context ${toString model.context} \
            --kv ${kv} --vision no --no-start --yes "$@"
        '';
      };

      # Wywołanie wrappera strata usuwa run config ze ścieżkami store, których
      # nie ma. Setup pisze go od nowa (kroki, które są zrobione, pomija), gdy
      # go nie ma albo jego KV lub kontekst różni się od ustawień tutaj.
      ensureConfig = pkgs.writeShellApplication {
        name = "strata-hermes-config";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          config=${lib.escapeShellArg runConfig}
          ${strata} --version >/dev/null
          if [ ! -e "$config" ] || ! jq -e --arg kv ${kv} --arg context ${toString model.context} '
            .args as $a | ($a | index("--kv")) as $k | ($a | index("--max-context")) as $c
            | $k != null and $c != null and $a[$k + 1] == $kv and $a[$c + 1] == $context
          ' "$config" >/dev/null; then
            ${lib.getExe setup}
          fi
          jq --arg n ${toString kvResident} '
            .args |= (index("--kv-resident") as $i
              | if $i == null then . + ["--kv-resident", $n] else .[$i + 1] = $n end)
          ' "$config" > "$config.tmp"
          mv "$config.tmp" "$config"
        '';
      };

      # Bez innych procesów dGPU zajmuje 44 MiB (kwin, PRIME offload;
      # 2026-10-29); gra albo inny LLM zajmuje gigabajty.
      gpuIdle = pkgs.writeShellApplication {
        name = "strata-hermes-gpu-idle";
        runtimeInputs = [
          pkgs.coreutils
          config.hardware.nvidia.package.bin
        ];
        text = ''
          used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -n 1)
          if ((used > 512)); then
            echo "dGPU zajęte (''${used} MiB VRAM), Strata dla Hermesa nie startuje" >&2
            exit 1
          fi
        '';
      };

      waitReady = pkgs.writeShellApplication {
        name = "strata-hermes-wait";
        runtimeInputs = [ pkgs.curl ];
        text = ''
          until curl -sf --max-time 2 -o /dev/null http://127.0.0.1:${toString backendPort}/health; do
            sleep 1
          done
        '';
      };

      # Gdy strata-hermes nie wystartowała, proxy kończy się po sekundzie
      # (powód w nagłówku).
      proxy = pkgs.writeShellApplication {
        name = "strata-hermes-proxy";
        runtimeInputs = [ config.systemd.package ];
        text = ''
          idle=$STRATA_HERMES_IDLE
          systemctl is-active --quiet strata-hermes.service || idle=1s
          exec ${config.systemd.package}/lib/systemd/systemd-socket-proxyd \
            --exit-idle-time="$idle" 127.0.0.1:${toString backendPort}
        '';
      };
    in
    {
      users = {
        users = {
          ${user} = {
            isSystemUser = true;
            group = user;
            description = "Tunel Hermesa z raspberry-pi-4 do lokalnego LLM";
            openssh.authorizedKeys.keys = [
              ''from="${lan.subnet}",restrict,port-forwarding ${keys.users.hermes-llm}''
            ];
          };
          ${strataUser} = {
            isSystemUser = true;
            group = strataUser;
            home = stateDir;
            description = "Strata dla Hermesa";
          };
        };
        groups = {
          ${user} = { };
          ${strataUser} = { };
        };
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

      environment.systemPackages = [ setup ];

      systemd = {
        # Przed pierwszym startem usługi, bo setup działa wcześniej.
        tmpfiles.rules = [ "d ${stateDir} 0700 ${strataUser} ${strataUser} - -" ];

        sockets.strata-hermes-proxy = {
          description = "Strata dla Hermesa (start na żądanie)";
          wantedBy = [ "sockets.target" ];
          listenStreams = [ target ];
        };

        services = {
          strata-hermes-proxy = {
            description = "Proxy do Straty dla Hermesa";
            wants = [ "strata-hermes.service" ];
            after = [ "strata-hermes.service" ];
            environment.STRATA_HERMES_IDLE = "15min";
            serviceConfig = {
              ExecStart = lib.getExe proxy;
              DynamicUser = true;
              ProtectHome = true;
              PrivateDevices = true;
              RestrictAddressFamilies = [
                "AF_UNIX"
                "AF_INET"
                "AF_INET6"
              ];
            };
          };

          strata-hermes = {
            description = "Strata dla Hermesa";
            unitConfig.StopWhenUnneeded = true;
            serviceConfig = {
              User = strataUser;
              Group = strataUser;
              ExecStartPre = [
                (lib.getExe gpuIdle)
                (lib.getExe ensureConfig)
              ];
              ExecStart = lib.escapeShellArgs [
                strata
                "serve"
                "--config"
                runConfig
                "--host"
                "127.0.0.1"
                "--port"
                (toString backendPort)
                "--offline"
              ];
              ExecStartPost = lib.getExe waitReady;
              # Zapas na odtworzenie run configu i załadowanie ok. 90 GB modelu
              # (czas ładowania niezmierzony).
              TimeoutStartSec = "10min";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              ReadWritePaths = [ stateDir ];
              # Tylko proxy na localhost; setup w ExecStartPre niczego nie pobierze.
              IPAddressDeny = "any";
              IPAddressAllow = "localhost";
            };
          };
        };
      };
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
        base_url = "http://${target}/v1";
        default_model = model.id;
        models.${model.id}.context_length = model.context;
      };
    };
}
