# Hermes Agent (Nous Research) jako usługa konta `hermes`: model główny to
# Claude Code na subskrypcji (zapas: openai-codex, ollama-cloud), polski
# interfejs, MCP mcp-nixos, lokalna Ollama, CLI przez sudo -u hermes.
#
# Granica zaufania: agent czyta treści z sieci i Matrixa, więc prompt
# injection nie może dawać roota. Konto hermes nie ma sudo, wheel, disk, keys
# ani trusted-users; pliki z użytkownikiem nixos dzieli przez upstreamowe
# katalogi stanu 2770 (setgid hermes) + UMask 0007 + chmod g+rw przy aktywacji.
# - Aktywacja pisze w /var/lib/hermes wyłącznie jako hermes (setpriv), nigdy
#   jako root: moduł to kopia upstreamu z _hermes-agent/ (zmiany w jej
#   nagłówku, temporary-fixes.md nr 2). Wpisy HERMES_HOME innych kont przejmuje
#   kopią, oryginały zostają jako .foreign-<nazwa> do usunięcia:
#   `sudo rm -r /var/lib/hermes/.hermes/.foreign-*`.
# - CLI (hermes, hermes-acp, hermes-agent) to opakowania hermesCli przez
#   `sudo -u hermes`: HERMES_HOME (pluginy, .env, config.yaml, polecenia
#   serwerów MCP) jest zapisywalny przez agenta, więc binarka uruchomiona jako
#   root lub nixos wykonałaby jego kod. claude-notify.nix bierze opakowanie
#   z services.hermes-agent.cliWrapper.
#
# Logowanie Claude jednorazowo, na koncie usługi:
# `sudo -u hermes -H claude auth login`.
#
# Sprawdzenie: `systemctl status hermes-agent`, `journalctl -u hermes-agent -b`,
# `hermes plugins list`; aktywacja:
# `nix build -L .#checks.aarch64-linux.hermes-activation` (kvm).
{
  inputs,
  customTop,
  ...
}:
{
  flake.modules.nixos.rpi-hermes =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Oficjalny plugin Nous Research: tury Hermesa idą przez niemodyfikowane
      # CLI `claude` (subskrypcja, bez klucza API); pętla agenta i narzędzia
      # zostają w Hermesie. Commit = `sha` z katalogu pluginów hermes-agent
      # (plugin-catalog/claude-subscription-directsdk.yaml, v0.3.0), nie `main`.
      claudeSubscriptionPlugin = pkgs.fetchFromGitHub {
        # Nazwa trafia do symlinku $HERMES_HOME/plugins/nix-managed-<name>.
        name = "claude-subscription-directsdk";
        owner = "NousResearch";
        repo = "hermes-plugin-claude-subscription-directsdk";
        rev = "ef73726cfaf2fa0ee041e55572f406e2c24fed83";
        hash = "sha256-kOQJWKqfGn41V21x/yjt8+i/MyQ2suctvbhf+x8djk8=";
      };

      # Własny plugin: bloki ```mermaid odpowiedzi na Matrixie → PNG (mmdc).
      # Opis w nagłówku _hermes-plugins/mermaid-render/__init__.py.
      mermaidRenderPlugin = pkgs.linkFarm "mermaid-render" {
        "plugin.yaml" = ./_hermes-plugins/mermaid-render/plugin.yaml;
        "__init__.py" = pkgs.replaceVars ./_hermes-plugins/mermaid-render/__init__.py {
          mmdc = lib.getExe pkgs.mermaid-cli;
        };
      };

      # Polski pakiet językowy (provides_locales: sam YAML, bez kodu Pythona)
      # dla statycznych tekstów CLI, bramki i TUI; odpowiedzi modelu bez zmian.
      # Commit = v0.2.0 z plugin.yaml — upstream nie otagował tej wersji.
      # Bez `requires_hermes`: pakiet Nix Hermesa stempluje wersję 0.0.0, więc
      # loader pominąłby plugin (temporary-fixes.md nr 5).
      polishLanguagePack = pkgs.applyPatches {
        name = "hermes-lang-pl";
        src = pkgs.fetchFromGitHub {
          owner = "teknium1";
          repo = "hermes-lang-pl";
          rev = "3072a5f8adb065d3322de9c95130c3e67e50288c";
          hash = "sha256-ARb7yyXz0ILwiO6kXwx6R7dgn9nEb5ZLVBdzHFmiaIs=";
        };
        postPatch = ''
          substituteInPlace plugin.yaml --replace-fail 'requires_hermes: ">=0.22"' ""
        '';
      };

      cfg = config.services.hermes-agent;
      hermesCommon = import "${inputs.hermes-agent}/nix/moduleCommon.nix" { inherit lib; };
      hermesHome = "${cfg.stateDir}/.hermes";

      # Pliki env łączy w $HERMES_HOME/.env aktywacja modułu procesem z uid
      # usługi (setpriv), więc muszą należeć do hermes; wystarczy 0400.
      hermesSecret = name: {
        file = customTop.secretsDir + "/${name}.age";
        owner = cfg.user;
        mode = "0400";
      };

      # Inne konta idą przez `sudo -u hermes` (powód w nagłówku); samo konto
      # hermes (powłoki narzędzia terminala agenta) uruchamia binarkę wprost,
      # bo nie ma reguł sudo (i działa z NoNewPrivileges).
      hermesCli =
        name:
        pkgs.writeShellScriptBin name ''
          if [ "$(${pkgs.coreutils}/bin/id -un)" = ${lib.escapeShellArg cfg.user} ]; then
            export HERMES_HOME="''${HERMES_HOME:-${hermesHome}}"
            exec ${hermesCommon.effectivePackage cfg}/bin/${name} "$@"
          fi
          exec /run/wrappers/bin/sudo -u ${cfg.user} -H -- ${pkgs.coreutils}/bin/env \
            HERMES_HOME=${hermesHome} \
            PATH=${
              lib.makeBinPath (hermesCommon.processPath { inherit pkgs cfg; })
            }:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin \
            ${hermesCommon.effectivePackage cfg}/bin/${name} "$@"
        '';

      # Ollama dostaje tylko OLLAMA_API_KEY (modele `:cloud` bez klucza: 401),
      # nie cały hermes-env.age: pobiera i parsuje modele z sieci, więc ma
      # widzieć jak najmniej. ollama-api-key.age to surowa wartość (bez KEY=),
      # której EnvironmentFile nie czyta — stąd LoadCredential i export tutaj.
      ollamaServe = pkgs.writeShellApplication {
        name = "ollama-serve";
        text = ''
          OLLAMA_API_KEY="$(<"$CREDENTIALS_DIRECTORY/ollama-api-key")"
          export OLLAMA_API_KEY
          exec ${lib.getExe config.services.ollama.package} serve
        '';
      };
    in
    {
      imports = [
        # Kopia modułu upstream (_hermes-agent/, temporary-fixes.md nr 2).
        (import ./_hermes-agent/nixos-module.nix {
          inputs.self = inputs.hermes-agent;
        }).flake.nixosModules.default
        {
          options.services.hermes-agent.cliWrapper = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            internal = true;
            description = "Opakowanie `hermes` (hermesCli): jako konto usługi uruchamia binarkę wprost, innym kontom przez sudo -u.";
          };
        }
      ];

      age.secrets = {
        hermes-env = hermesSecret "hermes-env";
        llmgateway-api-key = hermesSecret "llmgateway-api-key";
      };

      services = {
        hermes-agent = {
          enable = true;
          # CLI przez opakowania hermesCli (niżej), nie globalne HERMES_HOME.
          addToSystemPackages = false;
          cliWrapper = hermesCli "hermes";
          extraDependencyGroups = [
            "all"
            "messaging"
            "matrix"
          ];
          settings = {
            # Bez zgód: skutki prompt injection ogranicza konto hermes (nagłówek).
            execution.require_approval = false;
            # „Mózg”: Claude Code na subskrypcji (claudeSubscriptionPlugin); dane
            # w /var/lib/hermes/.claude (0600 hermes). Plugin nie startuje, gdy
            # w środowisku usługi są ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN lub
            # ANTHROPIC_BASE_URL — nie dodawać ich do hermes-env.age.
            model = {
              provider = "claude-subscription-directsdk-experimental";
              # Pełne ID aliasu `opus` pluginu v0.3.0. Modele z katalogu pluginu
              # (model_catalog.py) dostają `[1m]` same; spoza niego (np.
              # claude-sonnet-5-5) wymagają jawnego `[1m]`, inaczej CLI daje 200K.
              default = "claude-opus-5-5";
              # Aktywacja scala ustawienia z config.yaml na dysku (deep merge),
              # więc samo usunięcie klucza zostawiłoby tam stary URL Codexa.
              base_url = "";
            };
            # Brak logowania Claude albo wyczerpany limit subskrypcji nie
            # zatrzymują agenta.
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
            # Plugin przekazuje to do CLI jako `--effort xhigh` (domyślnie
            # Opus 5.5 ma `medium`).
            agent.reasoning_effort = "xhigh";
            # Z polishLanguagePack; HERMES_LANGUAGE w .env miałby pierwszeństwo.
            display.language = "pl";
            web.backend = "ddgs";
            # Pluginy spoza kategorii model-provider są opt-in. Aktywacja
            # zastępuje tą listą wpis w config.yaml, więc `hermes plugins
            # enable` znika po rebuildzie — dopisywać tu.
            plugins.enabled = [
              "mermaid-render"
              "hermes-lang-pl"
            ];
            auxiliary.vision = {
              provider = "ollama-cloud";
              base_url = "https://ollama.com/v1";
              model = "glm-5.3-flash:cloud";
            };
          };
          environmentFiles = [
            config.age.secrets.hermes-env.path
            config.age.secrets.llmgateway-api-key.path
          ];
          restart = "always";
          restartSec = 5;

          extraPlugins = [
            claudeSubscriptionPlugin
            mermaidRenderPlugin
            polishLanguagePack
          ];

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
            # Pakiet z nixpkgs zamiast `uvx mcp-nixos` (niepinowany PyPI w runtime).
            nixos = {
              command = lib.getExe pkgs.mcp-nixos;
              connect_timeout = 30;
              timeout = 60;
            };
          };
        };

        ollama.enable = true;
      };

      # Użytkownik w grupie hermes dzieli pliki agenta (katalogi stanu 2770).
      users.users = {
        ${config.customBot.defaultUser}.extraGroups = [ cfg.group ];
        ${cfg.user}.extraGroups = [ "systemd-journal" ];
      };

      # Agent sam łączy się z internetem (API modeli, narzędzia WWW), więc
      # lockdown (base-lockdown) zatrzymuje go razem z Matrixem.
      customBot.lockdownServices = [ "hermes-agent" ];

      environment.systemPackages = map hermesCli [
        "hermes"
        "hermes-acp"
        "hermes-agent"
      ];

      systemd.services = {
        ollama.serviceConfig = {
          LoadCredential = [ "ollama-api-key:${config.age.secrets.ollama-api-key.path}" ];
          # mkForce: zastępuje ExecStart modułu nixpkgs (`ollama serve`) tym
          # samym poleceniem w opakowaniu ustawiającym klucz.
          ExecStart = lib.mkForce (lib.getExe ollamaServe);
        };

        hermes-agent.serviceConfig = {
          # Nieaktualne pliki blokady/stanu bramki po przerwanym procesie
          # blokują start (temporary-fixes.md nr 3). Rekord hosta (gateway-locks
          # w $XDG_STATE_HOME) przeżywa też twardy reset: jego PID trafia potem
          # na inny proces, a bramka czeka na niego bez końca. Bez „+”: katalog
          # należy do hermes, więc rm działa jako użytkownik usługi niezależnie
          # od właściciela pliku.
          ExecStartPre =
            let
              hostLocks = "${cfg.stateDir}/.local/state/hermes/gateway-locks";
            in
            lib.mkBefore [
              "${pkgs.coreutils}/bin/rm -f ${hermesHome}/gateway.lock ${hermesHome}/gateway.pid ${hermesHome}/gateway_state.json ${hostLocks}/host-gateway.json ${hostLocks}/host-gateway.token"
            ];
        };
      };
    };
}
