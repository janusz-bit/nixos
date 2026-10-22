# Hermes Agent (Nous Research) jako usługa konta `hermes`: model główny to
# Claude Code na subskrypcji (zapas: openai-codex, ollama-cloud), polski
# interfejs, MCP mcp-nixos, lokalna Ollama, CLI przez sudo -u hermes.
#
# Granica zaufania: agent czyta treści z sieci i komunikatorów
# (Matrix), więc prompt injection nie może dawać
# roota. Konto hermes nie ma sudo, wheel, disk, keys ani trusted-users; pliki
# z użytkownikiem nixos dzieli przez upstreamowe katalogi stanu 2770 (setgid
# hermes) + UMask 0007 + chmod g+rw przy aktywacji.
# - Aktywacja pisze w /var/lib/hermes wyłącznie jako hermes (setpriv), nigdy
#   jako root: moduł to kopia upstreamu z _hermes-agent/ (zmiany w jej
#   nagłówku, temporary-fixes.md). Wpisy HERMES_HOME należące do innych kont
#   (po dawnym CLI roota/nixos) przejmuje kopią; oryginalne katalogi zostają
#   jako .foreign-<nazwa> do usunięcia przez administratora:
#   `sudo rm -r /var/lib/hermes/.hermes/.foreign-*`.
# - CLI (hermes, hermes-acp, hermes-agent) to opakowania hermesCli: innym
#   kontom uruchamiają binarkę przez `sudo -u hermes` na HERMES_HOME usługi,
#   konto hermes wprost. Nigdy nie uruchamiać binarki pakietu jako root ani
#   nixos: HERMES_HOME (pluginy, .env, config.yaml, polecenia serwerów MCP)
#   jest zapisywalny przez agenta, więc wykonałaby jego kod z cudzymi
#   uprawnieniami. Inne moduły (claude-notify.nix) biorą to samo opakowanie
#   z services.hermes-agent.cliWrapper.
# - Kod pobierany z sieci jest przypięty: pluginy przez extraPlugins
#   z commitem i hashem; dla pluginu z katalogu pluginów hermes-agent commit
#   to `sha` z plugin-catalog/<nazwa>.yaml, nie `main`. Serwery MCP z nixpkgs,
#   nie przez uvx.
# - Pluginy spoza kategorii model-provider (mermaid-render, hermes-lang-pl)
#   włącza wyłącznie plugins.enabled niżej: aktywacja zastępuje tą listą
#   wpis w config.yaml, więc `hermes plugins enable` znika po rebuildzie.
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
      # loader pominąłby plugin (temporary-fixes.md).
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
      common = import "${inputs.hermes-agent}/nix/moduleCommon.nix" { inherit lib; };
      hermesHome = "${cfg.stateDir}/.hermes";

      # CLI hosta zawsze jako konto usługi (powód w nagłówku). Zamiast
      # addToSystemPackages (globalne HERMES_HOME + CLI wywołującego) —
      # opakowania przez sudo -u hermes. Sam agent (powłoki narzędzia
      # terminala, `sudo -u hermes -i`) ma to opakowanie w PATH logowania:
      # jako hermes uruchamia ono binarkę wprost — hermes nie ma reguł sudo
      # (i NoNewPrivileges) i nie potrzebuje.
      hermesCli =
        name:
        pkgs.writeShellScriptBin name ''
          if [ "$(${pkgs.coreutils}/bin/id -un)" = ${lib.escapeShellArg cfg.user} ]; then
            export HERMES_HOME="''${HERMES_HOME:-${hermesHome}}"
            exec ${common.effectivePackage cfg}/bin/${name} "$@"
          fi
          exec /run/wrappers/bin/sudo -u ${cfg.user} -H -- ${pkgs.coreutils}/bin/env \
            HERMES_HOME=${hermesHome} \
            PATH=${
              lib.makeBinPath (common.processPath { inherit pkgs cfg; })
            }:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin \
            ${common.effectivePackage cfg}/bin/${name} "$@"
        '';

      # Ollama dostaje z sekretów tylko OLLAMA_API_KEY (modele `:cloud` przez
      # lokalną Ollamę bez klucza zwracają 401), nie cały hermes-env.age z
      # kluczami Hermesa: pobiera i parsuje modele z sieci, więc ma widzieć
      # jak najmniej. ollama-api-key.age to surowa wartość (bez KEY=), której
      # EnvironmentFile nie czyta — podaje ją LoadCredential, a to opakowanie
      # eksportuje przed `ollama serve`.
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
        # Kopia modułu upstream bez zapisów roota w katalogach agenta
        # (opis zmian w nagłówku pliku, temporary-fixes.md).
        (import ./_hermes-agent/nixos-module.nix {
          inputs.self = inputs.hermes-agent;
        }).flake.nixosModules.default
        # CLI dla innych modułów hosta (claude-notify.nix) bez powielania
        # logiki hermesCli.
        {
          options.services.hermes-agent.cliWrapper = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            internal = true;
            description = "Opakowanie `hermes` (hermesCli): jako konto usługi uruchamia binarkę wprost, innym kontom przez sudo -u.";
          };
        }
      ];

      # Pliki env łączy w $HERMES_HOME/.env aktywacja modułu procesem z uid
      # usługi (setpriv), więc muszą należeć do hermes; wystarczy 0400.
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
            execution = {
              # Agent nie ma sudo ani grup uprzywilejowanych (nagłówek), więc
              # skutki prompt injection ogranicza konto `hermes`.
              require_approval = false;
            };
            # „Mózg": Claude Code na subskrypcji (claudeSubscriptionPlugin).
            # Logowanie w nagłówku; dane w /var/lib/hermes/.claude (0600
            # hermes). Plugin odmawia startu, gdy w środowisku usługi są ANTHROPIC_API_KEY,
            # ANTHROPIC_AUTH_TOKEN lub ANTHROPIC_BASE_URL — nie dodawać ich
            # do hermes-env.age.
            model = {
              provider = "claude-subscription-directsdk-experimental";
              # Opus 5.5 pełnym ID (= alias `opus` pluginu v0.3.0). Jest w katalogu
              # pluginu (model_catalog.py) z oknem 1M, więc `[1m]` dokleja sam.
              # Modele spoza katalogu (np. claude-sonnet-5-5) wymagają jawnego
              # `[1m]` — bez sufiksu CLI stosuje 200K.
              default = "claude-opus-5-5";
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
            # Plugin przekazuje to do CLI jako `--effort xhigh` (Opus 5.5 domyślnie
            # ma `medium`, więc ustawienie jest konieczne).
            agent.reasoning_effort = "xhigh";
            # Z polishLanguagePack; HERMES_LANGUAGE w .env miałby pierwszeństwo.
            display.language = "pl";
            web.backend = "ddgs";
            # Pluginy spoza kategorii (model-provider ładuje się sam) są opt-in.
            # Scalanie config.yaml zastępuje listy w całości, więc wpis
            # `hermes plugins enable` znika przy aktywacji — dopisywać tu.
            plugins.enabled = [
              "mermaid-render"
              "hermes-lang-pl"
            ];
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
              args = [ ];
              enabled = true;
              connect_timeout = 30;
              timeout = 60;
            };
          };
        };

        ollama.enable = true;
      };

      # hermes bez sudo, wheel, disk i keys (nagłówek); nixos w grupie hermes
      # dzieli pliki agenta przez katalogi stanu 2770.
      users.users = {
        nixos.extraGroups = [ "hermes" ];
        hermes.extraGroups = [ "systemd-journal" ];
      };

      environment.systemPackages = map hermesCli [
        "hermes"
        "hermes-acp"
        "hermes-agent"
      ];

      systemd.services = {
        # Klucz dla modeli `:cloud`: ollamaServe wyżej.
        ollama.serviceConfig = {
          LoadCredential = [ "ollama-api-key:${config.age.secrets.ollama-api-key.path}" ];
          # mkForce: zastępuje ExecStart modułu nixpkgs (`ollama serve`) tym
          # samym poleceniem w opakowaniu ustawiającym klucz.
          ExecStart = lib.mkForce (lib.getExe ollamaServe);
        };

        hermes-agent.serviceConfig = {
          # Nieaktualne pliki blokady/stanu bramki po przerwanym procesie
          # blokują start (temporary-fixes.md). Bez „+”: katalog należy do
          # hermes, więc rm działa jako użytkownik usługi niezależnie od
          # właściciela pliku. Dawny krok roota naprawiający właściciela
          # auth.json (chown przez ścieżki agenta = symlink TOCTOU do roota)
          # usunięty — CLI działa już tylko jako hermes (hermesCli).
          # Rekord hosta (gateway-locks w $XDG_STATE_HOME = $HOME/.local/state)
          # przeżywa restart systemu: po twardym resecie jego PID z czasem startu
          # liczonym od rozruchu trafia na inny proces, a bramka czeka na niego
          # bez końca.
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
