# Zewnętrzne paczki skilli (SKILL.md) z wejść flake'a dla Claude Code, Codexa,
# opencode i Prime Agenta; obecnie Qt Development Skills (wejście
# qt-agent-skills: Qt 6 C++/QML, CMake, testy Qt Quick, profilowanie QML,
# design tokeny z Figmy) i tstack (wejście tstack: prowadzenie PR przez
# review i CI do merge'a, przez gh). Moduł jest jedynym właścicielem zarządzanego
# /etc/opencode/opencode.json, więc dopisuje tam też lokalne modele: Ternary
# Bonsai 2 27B (fork llama.cpp od PrismML) i, przy NVIDIA, Qwen3.8-Flash-Next
# Coder z serwera Strata (provider strata). Z serwera Bonsai korzysta też
# Prime Agent (provider llamacpp); uruchamiają go aliasy bonsai-serve
# i bonsai-serve-mtp, a llama-prism daje pozostałe polecenia forka.
#
# Każdy podkatalog paczki z SKILL.md to jeden skill w customBot.agentSkills;
# ai-skills (modules/skills/default.nix) linkuje go do katalogów skilli
# systemowych każdego agenta. Ta sama nazwa z dwóch paczek albo z paczki
# i z ai-skills kończy ewaluację błędem „conflicting definition values”.
#
# Tylko laptop (import w hosts/nixos): skille Qt i lokalny model na GPU są
# narzędziami stacji roboczej. Skrypty skilli Qt i pr-wait z babysit-pr wołają
# python3 (desktop-ai), skille tstack także gh (base-git); council i sol-loop
# potrzebują subagentów na modelach innych dostawców.
# qmllint, qmlprofiler i qmltestrunner pochodzą z Qt projektu (nix develop,
# devenv), nie z systemu.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.nixos.config.environment.etc --apply 'e: builtins.filter (n: builtins.match "codex/.*" n != null) (builtins.attrNames e)'`;
# po aktywacji `/skills` w Claude Code i w Codexie, `opencode2 models |
# grep -E 'llamacpp/|strata/'` (modele są na liście także bez działającego
# serwera).
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
      # tylko przez aliasy, nie w PATH.
      llamaCppPrism = pkgs.llama-cpp-prism.override { cudaSupport = config.hardware.nvidia.enabled; };

      skillPacks = [
        "${inputs.qt-agent-skills}/skills"
        "${inputs.tstack}/skills"
      ];

      skillsIn =
        pack:
        lib.mapAttrs (name: _: "${pack}/${name}") (
          lib.filterAttrs (
            name: type: type == "directory" && builtins.pathExists "${pack}/${name}/SKILL.md"
          ) (builtins.readDir pack)
        );

      # Wspólne dla aliasów serwera i providerów opencode2 i Prime Agenta, więc
      # -c/-n serwera nie rozjadą się z limitami modelu. Port jawnie: fork
      # zapowiada zmianę domyślnego 8080 na 9931. Klucz wariantu to nazwa
      # modelu w opencode2, `alias` to alias, który uruchamia jego serwer.
      bonsai = {
        mmproj = "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf";
        port = 8080;
        # -n serwera to tylko domyślny limit żądań bez max_tokens (większe
        # max_tokens przechodzi); opencode2 i Prime wysyłają ten. opencode2
        # liczy próg kompakcji z context minus bufor, nie minus output, więc
        # ta wartość nie zmniejsza kontekstu na wejście (także w wariancie MTP).
        output = 32768;
        # Serwer startuje z --mmproj (projekcja wizyjna), więc model rozumie obrazy.
        input = [
          "text"
          "image"
        ];
        variants = {
          ternary-bonsai-2-27b = {
            alias = "bonsai-serve";
            model = "Ternary-Bonsai-2-27B-PTQ1_0.gguf";
            name = "Ternary Bonsai 2 27B PTQ1_0 (local)";
            context = 98304;
            serverFlags = [ ];
          };
          # Ten sam trzon z głowicą MTP Qwen 3.8 (plik lean z HF
          # sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF): szybciej, ale głowica
          # i kontekst draftu zabierają VRAM na kontekst (pomiary przy bonsaiServe).
          ternary-bonsai-2-27b-mtp = {
            alias = "bonsai-serve-mtp";
            model = "Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf";
            name = "Ternary Bonsai 2 27B PTQ1_0 MTP (local)";
            context = 49152;
            serverFlags = [ "--spec-type draft-mtp --spec-draft-n-max 1" ];
          };
        };
      };
      baseUrl = "http://127.0.0.1:${toString bonsai.port}/v1";

      # Pomiary na tym laptopie (RTX 5060 Laptop, 8 GB VRAM; 2026-10-21/22,
      # b10787, llama serve):
      # - Natywne kernele FlashAttention mają tylko pary q4_0/q4_0, q8_0/q8_0
      #   i f16; inne typy KV (także q8_0/q4_0, q4_1, q5_x) konwertują KV do
      #   f16 i przy 32K kontekstu generują o 40-48% wolniej. q4_0/q4_0 mieści
      #   ponad 96K kontekstu, q8_0/q8_0 (prawie bezstratne, KLD ok. 0,0002) do 45K.
      # - Bez GGML_CUDA_ENABLE_UNIFIED_MEMORY: ukrywa brak VRAM, nadmiar
      #   stronicuje się przez PCIe (przy 40K 21 zamiast 37 t/s). Bez niej brak
      #   VRAM wywraca serwer, także cuBLAS przy pierwszym żądaniu (ok. 120 MiB
      #   ponad stan po starcie).
      # - -ub 256 daje ten sam prefill co 512 i ok. 100 MiB VRAM mniej.
      # - Projektor na CPU: obraz 1024x1024 w 13,5 s zamiast 0,6 s, ale na GPU
      #   zajmuje ok. 830 MiB, ponad połowę kontekstu.
      # - Największe -c: `llama serve` z tymi flagami bez -c i z -fitt 256 (log
      #   „n_ctx_slot”); samodzielne llama-fit-params rezerwuje logity całego
      #   ubatcha (ok. 485 MiB) i zaniża wynik. -c 98304 z tymi flagami
      #   sprawdzone (2026-10-26): szczyt 7668 MiB z 8151 przy 96K zajętego
      #   kontekstu; każde 8K kontekstu to ok. 148 MiB, więc 106496 zostawiłoby
      #   ok. 335 MiB zapasu na inne procesy na dGPU.
      # - MTP, 1 token draftu, prawdziwe wagi: nowy kod +66%, edycje +84%,
      #   myślenie +42%, kod przy 26K kontekstu +58% (41 -> 68 t/s na świeżo).
      #   2-3 tokeny pomagają tylko edycjom, a mieszczą 28K/15K kontekstu.
      #   -c 49152 sprawdzone (szczyt 7540 MiB przy 48K zajętego), 57344
      #   zostawia ok. 75 MiB zapasu, 65536 pada przy pierwszym żądaniu.
      #
      # Pozostałe flagi:
      # - --reasoning-effort-allow xhigh,medium,low: szablon czatu przyjmuje
      #   tylko te (inny effort daje HTTP 500);
      # - --reasoning-effort medium: przy xhigh model potrafi zużyć cały limit
      #   wyjścia na myślenie (pomiary sudoingX na RTX 3060, repo
      #   local-ai-on-your-gaming-gpu, kernel/reasoning_effort.md);
      # - --cors-origins localhost: domyślne CORS `*` z credentials wpuszcza
      #   każdą stronę otwartą w przeglądarce;
      # - --presence-penalty 1.0 przeciw pętlom w myśleniu (ternarne wagi
      #   zapętlają się łatwiej). Karta modelu zaleca 0 z myśleniem i 1.5 bez,
      #   Qwen 0-2 na niekończące się powtórzenia (wyższe grozi mieszaniem
      #   języków). llama.cpp liczy karę tylko w oknie --repeat-last-n (64
      #   tokeny), więc powtarzane identyfikatory w kodzie prawie jej nie
      #   odczuwają; żądanie z presence_penalty ją nadpisuje;
      # - pozostały sampling z GGUF (temp 1.0, top-k 20, top-p 0.95; min-p 0.05
      #   to domyślne llama.cpp i zalecenie karty), --jinja domyślne.
      # Grupy flag (także serverFlags) dzieli się na spacjach, więc wartości
      # (nazwy plików .gguf) nie mogą zawierać spacji.
      bonsaiServe =
        variant:
        lib.escapeShellArgs (
          [ (lib.getExe llamaCppPrism) ]
          ++ lib.concatMap (lib.splitString " ") (
            [
              "serve -m ${variant.model} --mmproj ${bonsai.mmproj} --no-mmproj-offload"
              "--port ${toString bonsai.port} -c ${toString variant.context} -n ${toString bonsai.output}"
              "-np 1 -ngl 99 -ctk q4_0 -ctv q4_0 -ub 256 --presence-penalty 1.0"
              "--reasoning-effort medium --reasoning-effort-allow xhigh,medium,low --cors-origins localhost"
            ]
            ++ variant.serverFlags
          )
        );

      opencodeConfig = {
        providers = {
          llamacpp = {
            name = "llama.cpp (local)";
            package = "@opencode/ai/providers/openai-compatible";
            settings.baseURL = baseUrl;
            models = lib.mapAttrs (_: variant: {
              modelID = variant.model;
              inherit (variant) name;
              # llama-server oddaje tok myślenia w reasoning_content.
              compatibility.reasoningField = "reasoning_content";
              capabilities = {
                tools = true;
                inherit (bonsai) input;
                output = [ "text" ];
                reasoning = {
                  supported = true;
                  # Domyślny effort modelu to xhigh (szablon czatu); bez low, bo wg
                  # karty modelu zachowuje się prawie jak xhigh.
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
        }
        // lib.optionalAttrs config.hardware.nvidia.enabled {
          # Serwer `strata launch --family coder --model IQ1_M --context 128k
          # --kv q4_0 --no-api-key` (desktop-ai), ten sam port co bonsai-serve.
          # Nie przez `strata connect opencode --write`: pisze format opencode
          # v1 (provider/npm) i zastąpiłby symlink na ten plik zwykłym plikiem.
          # Przy 128K domyślne KV int8 (1931 MiB) nie zostawia w 8 GB VRAM
          # miejsca na cache ekspertów ani bufory prefillu; q4_0 mieści się na
          # styk (2026-10-26: 131 MiB wolnego po starcie, 55 MiB w trakcie
          # odpowiedzi, 26,7 tok/s). Bez klucza serwer i tak odrzuca strony
          # z przeglądarki (sprawdza Host i Origin).
          strata = {
            name = "Strata (local)";
            package = "@opencode/ai/providers/openai-compatible";
            settings.baseURL = baseUrl;
            models.qwen3-8-flash-next-coder-iq1_m = {
              modelID = "qwen3.8-flash-next-coder-iq1_m";
              name = "Qwen3.8-Flash-Next Coder IQ1_M (local)";
              compatibility.reasoningField = "reasoning_content";
              capabilities = {
                tools = true;
                # Obrazy czyta strata-vision na CPU (domyślne --vision przy <24 GB).
                input = [
                  "text"
                  "image"
                ];
                output = [ "text" ];
                reasoning = {
                  supported = true;
                  # Poziomy, które serwer rozumie (serve/server.py, EFFORT_TEXT).
                  effort = [
                    "low"
                    "medium"
                    "high"
                    "xhigh"
                  ];
                };
              };
              limit = {
                context = 131072;
                # Limit wyjścia, z którym Strata testuje swoje konfiguracje
                # (OUTPUT_CAP w strata_cli/launch/harness.py).
                output = 4096;
              };
            };
          };
        };
      };
    in
    {
      # Każda paczka to osobna definicja opcji, więc ta sama nazwa w dwóch
      # paczkach jest błędem, a nie cichym nadpisaniem.
      customBot.agentSkills = lib.mkMerge (map skillsIn skillPacks);

      # Ten sam serwer dla Prime Agenta. Poziomy myślenia Prime mapują się na
      # off/medium/xhigh jak effort w opencode wyżej; "none" wyłącza myślenie
      # (tools/server/server-common.cpp forka), a null wyłącza poziom (Prime
      # dobiera najbliższy). Domyślne compat wystarcza: llama.cpp zamienia
      # rolę developer na system i przyjmuje max_completion_tokens.
      customBot.primeAgentProviders.llamacpp = {
        inherit baseUrl;
        api = "openai-completions";
        # Schemat Prime wymaga klucza; serwer bez --api-key go ignoruje.
        apiKey = "llamacpp";
        models = lib.mapAttrsToList (_: variant: {
          id = variant.model;
          inherit (variant) name;
          inherit (bonsai) input;
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
          contextWindow = variant.context;
          maxTokens = bonsai.output;
        }) bonsai.variants;
      };

      # llama-prism <polecenie>: wielofunkcyjny `llama` forka (serve, cli,
      # bench, fit-params, quantize, perplexity); `llama` w PATH to stockowy.
      # bonsai-serve i bonsai-serve-mtp uruchamiać w katalogu z plikami .gguf.
      environment.shellAliases = {
        llama-prism = lib.getExe llamaCppPrism;
      }
      // lib.mapAttrs' (
        _: variant: lib.nameValuePair variant.alias (bonsaiServe variant)
      ) bonsai.variants;

      environment.etc."opencode/opencode.json".text = builtins.toJSON opencodeConfig;
    };
}
