# Zewnętrzne paczki skilli (format SKILL.md) z wejść flake'a dla agentów
# kodujących stacji roboczej: Claude Code, Codex, opencode i Prime Agent,
# oraz zarządzany /etc/opencode/opencode.json z lokalnym providerem llama.cpp
# (model Bonsai 2 27B PTQ1_0), ten sam provider dla Prime Agenta oraz aliasy
# llama-prism (fork llama.cpp od PrismML), bonsai-serve i bonsai-serve-mtp,
# które uruchamiają serwer modelu (bez i z dekodowaniem spekulatywnym MTP).
# Obecnie Qt Development Skills od The Qt Company (wejście qt-agent-skills):
# pisanie i przegląd kodu Qt 6 C++/QML, CMake, testy Qt Quick, profilowanie
# QML, dokumentacja, design tokeny z Figmy.
#
# Każdy podkatalog paczki z SKILL.md to jeden skill. Trafia tam, gdzie agent
# szuka skilli systemowych bez konfiguracji użytkownika:
# - Claude Code: /etc/claude-code/.claude/skills/<nazwa> (skille zarządzane,
#   jak claudeSkills w ai-skills),
# - Codex: /etc/codex/skills/<nazwa> (scope ADMIN; Codex wchodzi w symlinki
#   katalogów),
# - Prime Agent: /etc/ai-skills/<nazwa> (lista skills w base/prime-agent.nix),
# - opencode: skills.paths i provider llama.cpp w zarządzanym
#   /etc/opencode/opencode.json. Ten plik ma najwyższy priorytet, a opencode
#   zastępuje (nie skleja) tablice, więc własne skille opencode trzymać
#   w ~/.config/opencode/skills/.
#
# Ta sama nazwa z dwóch paczek albo z paczki i z ai-skills kończy ewaluację
# błędem „conflicting definition values” dla environment.etc.
#
# Ten moduł jest jedynym właścicielem /etc/opencode/opencode.json, więc obok
# skilli wpisuje też lokalny model Ternary Bonsai 2 27B: serwer `llama serve`
# z forka PrismML (modules/packages/_llama-cpp-prism) na 127.0.0.1:8080
# uruchamia alias `bonsai-serve` (81920 kontekstu) albo `bonsai-serve-mtp`
# (plik z głowicą MTP, 49152 kontekstu, szybsze generowanie) w katalogu
# z plikami .gguf (RTX 5060 Laptop, 8 GB VRAM); w opencode2 i w Prime
# Agencie każdy wariant to osobny model. Prime Agent dostaje modele przez
# customBot.primeAgentProviders (models.json składa base/prime-agent.nix).
# Flagi aliasu i limity modelu w opencode i w Prime Agencie biorą się
# z jednego zestawu wartości (`bonsai` niżej); pomiary, które uzasadniają
# flagi, są przy aliasie.
#
# Tylko laptop (import w hosts/nixos): na RPi `claude` jest też modelem
# Hermesa (claudeSubscriptionPlugin), a skille zarządzane dostaje każde konto.
# Skrypty skilli Qt wołają python3 (z desktop-ai); qmllint, qmlprofiler
# i qmltestrunner pochodzą z Qt projektu (nix develop, devenv), nie z systemu.
#
# Nowa paczka: wejście z `flake = false` we flake.nix + `nix flake lock`,
# potem jej katalog ze skillami w skillPacks niżej. Aktualizacja razem z
# resztą wejść (`flake-update`) albo osobno: `nix flake update <wejście>`.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.nixos.config.environment.etc --apply 'e: builtins.filter (n: builtins.match "codex/.*" n != null) (builtins.attrNames e)'`;
# po aktywacji `/skills` w Claude Code i w Codexie, `opencode2 models |
# grep llamacpp/` (model jest na liście także bez działającego serwera).
{ inputs, ... }:
{
  flake.modules.nixos.ai-skills-external =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Fork PrismML: formaty Bonsai (PTQ1_0), których stockowy llama.cpp
      # z desktop-ai nie wczytuje. Te same nazwy binarek co stockowy, więc
      # tylko przez alias llama-prism i bonsai-serve, nie w PATH.
      llamaCppPrism = pkgs.llama-cpp-prism.override { cudaSupport = config.hardware.nvidia.enabled; };

      skillPacks = [
        "${inputs.qt-agent-skills}/skills"
      ];

      skillsIn =
        pack:
        lib.mapAttrsToList
          (name: _: {
            inherit name;
            source = "${pack}/${name}";
          })
          (
            lib.filterAttrs (
              name: type: type == "directory" && builtins.pathExists "${pack}/${name}/SKILL.md"
            ) (builtins.readDir pack)
          );

      skills = lib.concatMap skillsIn skillPacks;

      # Wspólne dla aliasów serwera i providerów opencode2 i Prime Agenta, więc
      # -c/-n serwera nie rozjadą się z limitami modelu. Port jawnie: fork
      # zapowiada zmianę domyślnego 8080 na 9931. Klucz wariantu to nazwa
      # modelu w opencode2, `alias` to alias, który uruchamia jego serwer.
      bonsai = {
        mmproj = "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf";
        port = 8080;
        output = 16384;
        variants = {
          ternary-bonsai-2-27b = {
            alias = "bonsai-serve";
            model = "Ternary-Bonsai-2-27B-PTQ1_0.gguf";
            name = "Ternary Bonsai 2 27B PTQ1_0 (local)";
            context = 81920;
            serverFlags = [ ];
          };
          # Ten sam trzon z głowicą MTP Qwen 3.8 (plik lean z HF
          # sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF): szybciej, ale głowica
          # i kontekst draftu zabierają VRAM na kontekst (pomiary przy aliasach).
          ternary-bonsai-2-27b-mtp = {
            alias = "bonsai-serve-mtp";
            model = "Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf";
            name = "Ternary Bonsai 2 27B PTQ1_0 MTP (local)";
            context = 49152;
            serverFlags = [
              "--spec-type"
              "draft-mtp"
              "--spec-draft-n-max"
              "1"
            ];
          };
        };
      };

      bonsaiServe =
        variant:
        lib.escapeShellArgs (
          [
            (lib.getExe llamaCppPrism)
            "serve"
            "-m"
            variant.model
            "--mmproj"
            bonsai.mmproj
            "--no-mmproj-offload"
            "--port"
            (toString bonsai.port)
            "-c"
            (toString variant.context)
            "-n"
            (toString bonsai.output)
            "-np"
            "1"
            "-ngl"
            "99"
            "-ctk"
            "q4_0"
            "-ctv"
            "q4_0"
            "-ub"
            "256"
            "--reasoning-effort"
            "medium"
            "--reasoning-effort-allow"
            "xhigh,medium,low"
            "--cors-origins"
            "localhost"
          ]
          ++ variant.serverFlags
        );

      # Model lokalny dla opencode2. Serwer uruchamia się ręcznie
      # (bonsai-serve albo bonsai-serve-mtp); opencode2 pokazuje modele z tej
      # listy także wtedy, gdy serwer nie działa. Serwer startuje z --mmproj
      # (projekcja wizyjna), więc model rozumie obrazy: input [text, image].
      # reasoningField: llama-server oddaje tok myślenia w
      # reasoning_content. Domyślny effort modelu to xhigh
      # (szablon czatu), medium jest jedynym sensownym skrótem — low wg karty
      # modelu zachowuje się prawie jak xhigh, więc go nie oferujemy.
      opencodeConfig = {
        skills.paths = skillPacks;
        providers.llamacpp = {
          name = "llama.cpp (local)";
          package = "@opencode/ai/providers/openai-compatible";
          settings.baseURL = "http://127.0.0.1:${toString bonsai.port}/v1";
          models = lib.mapAttrs (_: variant: {
            modelID = variant.model;
            inherit (variant) name;
            compatibility.reasoningField = "reasoning_content";
            capabilities = {
              tools = true;
              input = [
                "text"
                "image"
              ];
              output = [ "text" ];
              reasoning = {
                supported = true;
                effort = [
                  "medium"
                  "xhigh"
                ];
              };
            };
            limit = {
              inherit (variant) context;
              inherit (bonsai) output;
            };
          }) bonsai.variants;
        };
      };

      agentSkillDirs = [
        "claude-code/.claude/skills"
        "codex/skills"
        "ai-skills"
      ];
    in
    {
      # Ten sam serwer dla Prime Agenta. Poziomy myślenia Prime mapują się na
      # off/medium/xhigh jak effort w opencode wyżej; "none" wyłącza myślenie
      # (tools/server/server-common.cpp forka), a null wyłącza poziom (Prime
      # dobiera najbliższy). Domyślne compat wystarcza: llama.cpp zamienia
      # rolę developer na system i przyjmuje max_completion_tokens.
      customBot.primeAgentProviders.llamacpp = {
        baseUrl = "http://127.0.0.1:${toString bonsai.port}/v1";
        api = "openai-completions";
        # Schemat Prime wymaga klucza; serwer bez --api-key go ignoruje.
        apiKey = "llamacpp";
        models = lib.mapAttrsToList (_: variant: {
          id = variant.model;
          inherit (variant) name;
          reasoning = true;
          thinkingLevelMap = {
            off = "none";
            minimal = null;
            low = null;
            medium = "medium";
            high = null;
            xhigh = "xhigh";
            max = null;
          };
          input = [
            "text"
            "image"
          ];
          contextWindow = variant.context;
          maxTokens = bonsai.output;
        }) bonsai.variants;
      };

      # llama-prism <polecenie>: wielofunkcyjny `llama` forka (serve, cli,
      # bench, fit-params, quantize, perplexity); `llama` w PATH to stockowy.
      # bonsai-serve i bonsai-serve-mtp uruchamiać w katalogu z plikami .gguf;
      # argumenty z linii poleceń trafiają na koniec. Pomiary na tym laptopie
      # (2026-10-21/22, b10787, llama serve):
      # - Natywne kernele FlashAttention mają tylko pary q4_0/q4_0, q8_0/q8_0
      #   i f16; inne typy KV (także q8_0/q4_0, q4_1, q5_x) konwertują KV do
      #   f16 i przy 32K kontekstu generują o 40-48% wolniej. q4_0/q4_0 mieści
      #   do 84K kontekstu, q8_0/q8_0 (prawie bezstratne, KLD ok. 0,0002) do 45K.
      # - Bez GGML_CUDA_ENABLE_UNIFIED_MEMORY: ukrywa brak VRAM, nadmiar
      #   stronicuje się przez PCIe (przy 40K 21 zamiast 37 t/s). Bez niej brak
      #   VRAM wywraca serwer, także cuBLAS przy pierwszym żądaniu (ok. 120 MiB
      #   ponad stan po starcie).
      # - -ub 256 daje ten sam prefill co 512 i ok. 100 MiB VRAM mniej.
      # - Projektor na CPU: obraz 1024x1024 w 13,5 s zamiast 0,6 s, ale na GPU
      #   zajmuje ok. 830 MiB, ponad połowę kontekstu.
      # - Największe -c: `llama serve` z tymi flagami bez -c i z -fitt 256 (log
      #   „n_ctx_slot”); samodzielne llama-fit-params rezerwuje logity całego
      #   ubatcha (ok. 485 MiB) i zaniża wynik. -c 81920 z tymi flagami
      #   sprawdzone: szczyt 7372 MiB z 8151 przy 64K zajętego kontekstu.
      # - MTP, 1 token draftu, prawdziwe wagi: nowy kod +66%, edycje +84%,
      #   myślenie +42%, kod przy 26K kontekstu +58% (41 -> 68 t/s na świeżo).
      #   2-3 tokeny pomagają tylko edycjom, a mieszczą 28K/15K kontekstu.
      #   -c 49152 sprawdzone (szczyt 7540 MiB przy 48K zajętego), 57344
      #   zostawia ok. 75 MiB zapasu, 65536 pada przy pierwszym żądaniu.
      # Szablon czatu przyjmuje tylko effort xhigh/medium/low (inny daje HTTP
      # 500), a domyślne CORS `*` z credentials wpuszcza każdą stronę otwartą
      # w przeglądarce. Domyślny effort medium: przy xhigh model potrafi zużyć
      # cały limit wyjścia na myślenie (pomiary sudoingX na RTX 3060, repo
      # local-ai-on-your-gaming-gpu, kernel/reasoning_effort.md). Sampling
      # (temp 1.0, top-k 20, top-p 0.95) pochodzi z GGUF, --jinja jest domyślne.
      environment.shellAliases = {
        llama-prism = lib.getExe llamaCppPrism;
      }
      // lib.mapAttrs' (
        _: variant: lib.nameValuePair variant.alias (bonsaiServe variant)
      ) bonsai.variants;

      # mkMerge zamiast `//`: ta sama nazwa to dwie definicje jednej opcji,
      # więc kolizja jest błędem, a nie cichym nadpisaniem.
      environment.etc = lib.mkMerge (
        lib.concatMap (
          dir: map (skill: { "${dir}/${skill.name}".source = skill.source; }) skills
        ) agentSkillDirs
        ++ [
          { "opencode/opencode.json".text = builtins.toJSON opencodeConfig; }
        ]
      );
    };
}
