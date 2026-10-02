{
  inputs,
  customTop,
  ...
}:
{
  flake.modules.nixos.hermes =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Oficjalny plugin Nous Research: każda tura Hermesa idzie przez
      # niemodyfikowane CLI `claude` (subskrypcja Claude, bez klucza API);
      # pętla agenta, narzędzia i kompakcja zostają po stronie Hermesa.
      # Commit = wpis z katalogu pluginów hermes-agent
      # (plugin-catalog/claude-subscription-directsdk.yaml, v0.3.0) — przy
      # aktualizacji brać `sha` stamtąd, nie `main`.
      claudeSubscriptionPlugin = pkgs.fetchFromGitHub {
        # Nazwa trafia do symlinku $HERMES_HOME/plugins/nix-managed-<name>.
        name = "claude-subscription-directsdk";
        owner = "NousResearch";
        repo = "hermes-plugin-claude-subscription-directsdk";
        rev = "ef73726cfaf2fa0ee041e55572f406e2c24fed83";
        hash = "sha256-kOQJWKqfGn41V21x/yjt8+i/MyQ2suctvbhf+x8djk8=";
      };
    in
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      # Pliki env łączy w $HERMES_HOME/.env aktywacja modułu (jako root),
      # więc wystarczy 0400.
      age.secrets = {
        hermes-env = {
          file = customTop.secretsDir + "/hermes-env.age";
          owner = "hermes";
          mode = "0400";
        };
        llmgateway-api-key = {
          file = customTop.secretsDir + "/llmgateway-api-key.age";
          owner = "hermes";
          mode = "0400";
        };
        # Token ETAPI Trilium współdzielony z prime-agentem użytkownika nixos
        # (właściciel z modules/agenix/agenix.nix) — odczyt dla grupy hermes.
        trilium-etapi = {
          group = "hermes";
          mode = "0440";
        };
      };

      services = {
        hermes-agent = {
          enable = true;
          addToSystemPackages = true;
          extraDependencyGroups = [
            "all"
            "messaging"
            "matrix"
          ];
          settings = {
            execution = {
              # Agent nie ma sudo ani grup uprzywilejowanych (patrz users niżej),
              # więc skutki prompt injection ogranicza konto `hermes`.
              require_approval = false;
            };
            # „Mózg": Claude Code na subskrypcji (claudeSubscriptionPlugin).
            # Logowanie jednorazowo na RPi, na koncie usługi:
            #   sudo -u hermes -H claude auth login
            # (dane w /var/lib/hermes/.claude, 0600 hermes). Plugin odmawia
            # startu, gdy w środowisku usługi są ANTHROPIC_API_KEY,
            # ANTHROPIC_AUTH_TOKEN lub ANTHROPIC_BASE_URL — nie dodawać ich
            # do hermes-env.age.
            model = {
              provider = "claude-subscription-directsdk-experimental";
              # Aliasy pluginu: sonnet → claude-sonnet-5[1m], opus, haiku, fable.
              default = "sonnet";
              # Aktywacja scala ustawienia z config.yaml na dysku (deep merge),
              # więc samo usunięcie klucza zostawiłoby tam stary URL Codexa.
              base_url = "";
            };
            # Poprzedni mózg (Codex) jako pierwszy zapas: brak logowania
            # Claude albo wyczerpany limit subskrypcji nie zatrzymują agenta.
            fallback_providers = [
              {
                provider = "openai-codex";
                model = "gpt-6-sol";
              }
              {
                provider = "ollama-cloud";
                model = "glm-5.3-flash:cloud";
              }
            ];
            providers.ollama-cloud = {
              base_url = "https://ollama.com/v1";
              key_env = "OLLAMA_API_KEY";
            };
            agent.reasoning_effort = "xhigh";
            web.backend = "ddgs";
            auxiliary.vision = {
              provider = "ollama-cloud";
              base_url = "https://ollama.com/v1";
              model = "glm-5.3-flash:cloud"; # vision: text+image->text (GLM 5.3 Flash)
            };
          };
          environmentFiles = [
            config.age.secrets.hermes-env.path
            config.age.secrets.llmgateway-api-key.path
          ];
          restart = "always";
          restartSec = 5;

          extraPlugins = [ claudeSubscriptionPlugin ];

          extraPackages = with pkgs; [
            # `claude` na PATH usługi — wymagany przez claudeSubscriptionPlugin.
            claude-code
            codex
            uv
            nodejs_22
            ripgrep
            ffmpeg
            python311
          ];

          mcpServers = {
            trilium-notes = {
              url = "http://127.0.0.1:8081/mcp";
              enabled = true;
              connect_timeout = 30;
              timeout = 60;
              headers = {
                Authorization = "Bearer \${TRILIUM_ETAPI_TOKEN}";
              };
            };
            # Pakiet z nixpkgs zamiast `uvx mcp-nixos` (niepinowany PyPI w runtime).
            nixos = {
              command = lib.getExe pkgs.mcp-nixos;
              args = [ ];
              enabled = true;
              connect_timeout = 30;
              timeout = 60;
            };
          };
        };

        ollama.enable = true;
      };

      # Bez sudo, wheel, disk, keys i trusted-users: agent czyta treści z sieci,
      # notatek i komunikatorów, a jest wystawiony przez chat.janusz-bit.com —
      # prompt injection nie może dawać roota. Współdzielenie plików z
      # użytkownikiem nixos zapewnia upstream: katalogi stanu 2770 (setgid
      # hermes) + UMask 0007 + chmod g+rw przy aktywacji.
      users.users = {
        nixos.extraGroups = [ "hermes" ];
        hermes.extraGroups = [ "systemd-journal" ];
      };

      systemd.services = {
        ollama.serviceConfig.EnvironmentFile = config.age.secrets.hermes-env.path;

        # Clean stale lock/pid/state files before gateway start.
        # Interactive sessions (run as nixos) can create these files owned
        # by nixos:hermes with 0644 perms, which the hermes systemd service
        # cannot open in append mode (PermissionError). Removing them before
        # start lets the service recreate them with correct ownership.
        hermes-agent.serviceConfig.ExecStartPre = lib.mkBefore [
          # Hermes keeps OAuth credentials at 0600. If an interactive
          # login creates auth.json as nixos/root, the service cannot read
          # it. Repair ownership without replacing the stored tokens.
          "+${pkgs.writeShellScript "hermes-auth-ownership" ''
            set -eu
            auth_dir=/var/lib/hermes/.hermes
            if [ -d "$auth_dir" ] && [ ! -L "$auth_dir" ]; then
              ${pkgs.coreutils}/bin/chown hermes:hermes "$auth_dir"
              ${pkgs.coreutils}/bin/chmod u+rwx "$auth_dir"
              for auth_file in "$auth_dir/auth.json" "$auth_dir/auth.lock"; do
                if [ -f "$auth_file" ] && [ ! -L "$auth_file" ]; then
                  ${pkgs.coreutils}/bin/chown hermes:hermes "$auth_file"
                  ${pkgs.coreutils}/bin/chmod 0600 "$auth_file"
                fi
              done
            fi
          ''}"
          "${pkgs.coreutils}/bin/rm -f /var/lib/hermes/.hermes/gateway.lock /var/lib/hermes/.hermes/gateway.pid /var/lib/hermes/.hermes/gateway_state.json"
        ];
      };
    };
}
