# Import skilli i modeli do agentów kodujących: z wybranych w ai.skills,
# ai.skillPacks i ai.models (opcje: ai-options, definicje: ai-skills
# i ai-models, wybór: ai.nix hosta) buduje konfigurację Prime Agenta (models.json),
# opencode2 (zarządzany /etc/opencode/opencode.json) oraz katalogi skilli
# systemowych każdego agenta, dla każdego użytkownika hosta, bez Home Managera
# i bez plików w $HOME. Host niczego tu nie ustawia.
#
# Katalogi skilli (względem /etc), w których agent szuka skilli systemowych bez
# konfiguracji użytkownika; wpis <katalog>/<nazwa> to symlink do katalogu skilla:
# - Prime Agent: /etc/ai-skills (lista skills w base/prime-agent.nix),
# - Claude Code: /etc/claude-code/.claude/skills, skille zarządzane
#   (`claude --debug`: „Loading skills from: managed=…”); wyłączenie per
#   proces: CLAUDE_CODE_DISABLE_POLICY_SKILLS=1. `claude -p` Hermesa na RPi
#   (claudeSubscriptionPlugin) skilli nie użyje: plugin uruchamia go
#   z `--tools ''` i `--disable-slash-commands`,
# - Codex: /etc/codex/skills (scope ADMIN; Codex wchodzi w symlinki
#   katalogów),
# - opencode2: skanuje skills/ każdego katalogu konfiguracji, także
#   systemowego /etc/opencode (ten sam kod co ~/.config/opencode/skills),
#   więc nie potrzebuje opencode.json i działa też na RPi. Tablica
#   skills.paths w zarządzanym opencode.json zastępowałaby (nie
#   sklejała) skills.paths użytkownika.
# Antigravity (agy) nie ma katalogu skilli systemowych (tylko
# ~/.gemini/config/skills), więc skille do niego nie trafiają.
#
# Runtime drop-in: /etc/ai to katalog na skille dodawane BEZ rebuilda (ręcznie
# lub przez samego Prime Agenta), widoczne przy następnym starcie agenta.
# Czyta go tylko Prime Agent. Przy kolizji nazw wygrywa wcześniejszy wpis
# listy `skills` w settings.json (modules/hosts/base/prime-agent.nix), więc
# skille deklaratywne (/etc/ai-skills) mają pierwszeństwo przed /etc/ai: nix
# pozostaje źródłem prawdy.
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.<host>.config.environment.etc.\"prime-agent/models.json\".text`
# (na laptopie też \"opencode/opencode.json\") i wyniki ze skills.nix.
{ inputs, ... }:
{
  flake.modules.nixos.ai-harness =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.ai;
      user = config.customBot.defaultUser;

      skillDirs = {
        prime-agent = "ai-skills";
        claude-code = "claude-code/.claude/skills";
        codex = "codex/skills";
        opencode = "opencode/skills";
      };

      # Skille z paczek mają pola wpisu z ai.skills, żeby oba źródła
      # przetwarzać tak samo. unionOfDisjoint zamiast `//`: ta sama nazwa
      # w dwóch źródłach kończy ewaluację, zamiast po cichu zastąpić skill.
      skillsIn =
        pack:
        let
          isSkill = name: type: type == "directory" && builtins.pathExists "${pack.source}/${name}/SKILL.md";
        in
        lib.mapAttrs (name: _: {
          source = "${pack.source}/${name}";
          agents = lib.attrNames skillDirs;
          packages = [ ];
          python = false;
        }) (lib.filterAttrs isSkill (builtins.readDir pack.source));

      skills =
        lib.foldl' lib.attrsets.unionOfDisjoint (lib.filterAttrs (_: skill: skill.enable) cfg.skills)
          (map skillsIn (lib.attrValues (lib.filterAttrs (_: pack: pack.enable) cfg.skillPacks)));

      # Cały katalog skilla (read-only, zarządzany przez nix).
      skillLinks = lib.concatMapAttrs (
        agent: dir:
        lib.mapAttrs' (name: skill: lib.nameValuePair "${dir}/${name}" { inherit (skill) source; }) (
          lib.filterAttrs (_: skill: lib.elem agent skill.agents) skills
        )
      ) skillDirs;

      # Kernel Prime Agenta działa na PRIME_AGENT_KERNEL_PYTHON (read-only env
      # z flake llm-agents), więc bootstrap NIE zrobi `uv pip install
      # --editable` — tylko sprawdza `import <skill>` i wyłącza skill
      # z warningiem, gdy import się nie uda. Dlatego src/ skilli pythonowych
      # trafia do PYTHONPATH wrappera prime-agenta (-> kernel) i skill jest
      # importowalny out-of-the-box.
      pythonSkillSrcs = lib.mapAttrsToList (_: skill: skill.source + "/src") (
        lib.filterAttrs (_: skill: skill.python && lib.elem "prime-agent" skill.agents) skills
      );

      # PYTHONPATH tylko dla prime-agenta — globalna zmienna sesji trafiałaby
      # do każdego procesu Pythona (venvy, uv, nix-shell) i mogła przesłaniać
      # moduły. hiPrio: wygrywa z niezawiniętym prime-agentem z base.
      primeAgentWithSkills = pkgs.symlinkJoin {
        name = "prime-agent-with-skills";
        paths = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/prime-agent \
            --prefix PYTHONPATH : ${lib.escapeShellArg (lib.concatStringsSep ":" pythonSkillSrcs)}
        '';
      };

      enabledModels = lib.filterAttrs (_: model: model.enable) cfg.models;
      modelsOf = agent: lib.filterAttrs (_: model: lib.elem agent model.agents) enabledModels;

      # Asercja nie zdąży: brakujący provider wywraca ewaluację wcześniej.
      providerNamed =
        name: cfg.providers.${name} or (throw "ai.models: nieznany provider ${name} (ai.providers)");

      # Providerzy z co najmniej jednym modelem agenta, każdy z jego modelami.
      providersOf =
        toProvider: models:
        lib.genAttrs (lib.unique (lib.mapAttrsToList (_: model: model.provider) models)) (
          name: toProvider (providerNamed name) (lib.filterAttrs (_: model: model.provider == name) models)
        );

      # Poziomy myślenia Prime Agenta; poziom, którego serwer nie przyjmuje,
      # dostaje null (Prime dobiera najbliższy).
      primeLevels = [
        "minimal"
        "low"
        "medium"
        "high"
        "xhigh"
        "max"
      ];

      primeModel =
        model:
        lib.filterAttrs (_: value: value != null) {
          inherit (model) id name cost;
          contextWindow = model.context;
          maxTokens = model.output;
        }
        // lib.optionalAttrs (model.input != [ "text" ]) { inherit (model) input; }
        // lib.optionalAttrs (model.reasoning != null) (
          {
            reasoning = true;
          }
          // lib.optionalAttrs (model.reasoning.efforts != [ ]) {
            thinkingLevelMap =
              lib.optionalAttrs (model.reasoning.offEffort != null) { off = model.reasoning.offEffort; }
              // lib.genAttrs primeLevels (level: if lib.elem level model.reasoning.efforts then level else null);
          }
        );

      primeProvider =
        provider: models:
        {
          inherit (provider) baseUrl apiKey;
          api = "openai-completions";
          models = lib.mapAttrsToList (_: primeModel) models;
        }
        // lib.optionalAttrs (provider.compat != { }) { inherit (provider) compat; };

      opencodeModel =
        provider: model:
        {
          modelID = model.id;
          capabilities = {
            tools = true;
            inherit (model) input;
            output = [ "text" ];
            reasoning = {
              supported = model.reasoning != null;
            }
            // lib.optionalAttrs (model.reasoning != null && model.reasoning.efforts != [ ]) {
              effort = model.reasoning.efforts;
            };
          };
          limit = { inherit (model) context output; };
        }
        // lib.optionalAttrs (model.name != null) { inherit (model) name; }
        // lib.optionalAttrs (provider.reasoningField != null) {
          compatibility.reasoningField = provider.reasoningField;
        };

      opencodeProvider =
        provider: models:
        {
          package = "@opencode/ai/providers/openai-compatible";
          settings.baseURL = provider.baseUrl;
          models = lib.mapAttrs (_: opencodeModel provider) models;
        }
        // lib.optionalAttrs (provider.name != null) { inherit (provider) name; };

      opencodeProviders = providersOf opencodeProvider (modelsOf "opencode");

      modelsWhere = agent: predicate: lib.attrNames (lib.filterAttrs (_: predicate) (modelsOf agent));
      opencodeWithoutLimits = modelsWhere "opencode" (
        model: model.context == null || model.output == null
      );
      primeWithoutApiKey = modelsWhere "prime-agent" (
        model: (providerNamed model.provider).apiKey == null
      );
    in
    {
      assertions = [
        {
          assertion = opencodeWithoutLimits == [ ];
          message = "ai.models: opencode2 wymaga context i output, brakuje ich w: ${lib.concatStringsSep ", " opencodeWithoutLimits}.";
        }
        {
          assertion = primeWithoutApiKey == [ ];
          message = "ai.providers: Prime Agent wymaga apiKey providera, brakuje go dla modeli: ${lib.concatStringsSep ", " primeWithoutApiKey}.";
        }
      ];

      environment = {
        etc = skillLinks // {
          "prime-agent/models.json".text =
            builtins.toJSON { providers = providersOf primeProvider (modelsOf "prime-agent"); } + "\n";

          "opencode/opencode.json" = lib.mkIf (opencodeProviders != { }) {
            text = builtins.toJSON { providers = opencodeProviders; };
          };
        };

        systemPackages =
          lib.concatMap (skill: skill.packages) (lib.attrValues skills)
          ++ lib.optional (pythonSkillSrcs != [ ]) (lib.hiPrio primeAgentWithSkills);
      };

      # Drop-in na skille runtime — zapisywalny tylko przez defaultUsera
      # (on i jego Prime Agent dodają skille bez sudo). Wcześniej 0775
      # root:users: na RPi agent hermes (grupa users) mógł podrzucić skill
      # ładowany automatycznie przez prime-agenta użytkownika nixos.
      systemd.tmpfiles.rules = lib.optional (skills != { }) "d /etc/ai 0755 ${user} root - -";
    };
}
