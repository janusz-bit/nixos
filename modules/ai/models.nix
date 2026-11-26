# Katalog modeli agentów AI: serwery (ai.providers) i modele (ai.models), które
# repozytorium zna, bez włączania ich: host wybiera je w swoim ai.nix, a ai-harness
# zapisuje wybrane w konfiguracji Prime Agenta, Pi i opencode2. Zdalne: lokalna
# Ollama (także modele chmurowe przez nią), Ollama Cloud i OpenRouter. Lokalne
# na GPU: Qwen3.8-Flash-Next (Coder IQ1_M i Gyro-M) i Inkling-2-Mini z serwera
# Strata (tylko NVIDIA) oraz Ternary Bonsai 2.5 27B PTQ1_0 z forka llama.cpp (llama-prism).
#
# Klucze API wstrzykują wrappery fish z agenix (base/agenix.nix); tu są tylko
# nazwy zmiennych env.
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.nixos.config.environment.etc.\"opencode/opencode.json\".text`
# i `nix eval --raw .#nixosConfigurations.nixos.config.environment.etc.\"prime-agent/models.json\".text`;
# po aktywacji `opencode2 models | grep -E 'strata/|llamacpp/'` (modele są na
# liście także bez działającego serwera).
_: {
  flake.modules.nixos.ai-models =
    {
      config,
      lib,
      ...
    }:
    let
      # Model z myśleniem i obrazem na wejściu (u modeli Ollamy sprawdź
      # w `ollama show <model>`, sekcja Capabilities). Schemat models.json Prime
      # Agenta i Pi zna tylko input "text" i "image" — "video" odrzuca walidator.
      # Model serwera Strata (desktop-ai); oba modele obsługuje ten sam serwer
      # (serve/), więc różnią się tylko id i nazwą.
      strataModel = id: name: {
        provider = "strata";
        inherit id name;
        # Obrazy czyta strata-vision na CPU (domyślne --vision przy <24 GB).
        input = [
          "text"
          "image"
        ];
        context = 131072;
        # Ponad OUTPUT_CAP = 4096, z którym Strata testuje swoje konfiguracje
        # agentów; 1/8 okna jak output_cap w strata_cli/launch/harness.py.
        output = 16384;
        # Poziomy, które serwer przyjmuje (EFFORT w serve/frontend.py; high
        # działa jak xhigh); "none" wyłącza myślenie.
        reasoning = {
          efforts = [
            "low"
            "medium"
            "high"
            "xhigh"
          ];
          offEffort = "none";
        };
      };

      visionReasoningModel = provider: id: {
        inherit provider id;
        agents = [
          "prime-agent"
          "pi"
        ];
        reasoning = { };
        input = [
          "text"
          "image"
        ];
      };
    in
    {
      ai.providers = {
        ollama = {
          baseUrl = "http://localhost:11434/v1";
          # Lokalny Ollama ignoruje klucz, ale schemat go wymaga.
          apiKey = "ollama";
          compat = {
            supportsDeveloperRole = false;
            supportsReasoningEffort = false;
          };
        };
        ollama-cloud = {
          baseUrl = "https://ollama.com/v1";
          apiKeyEnv = "OLLAMA_API_KEY";
        };
        openrouter = {
          baseUrl = "https://openrouter.ai/api/v1";
          apiKeyEnv = "OPENROUTER_API_KEY";
        };
        # Serwer `strata launch --family coder --model IQ1_M --context 128k
        # --kv q4_0 --no-api-key` albo `--family gyro` (desktop-ai) na domyślnym
        # porcie 8080. Prime Agent i Pi wymagają klucza; Strata z --no-api-key go
        # ignoruje. Tok myślenia oddaje w reasoning_content.
        # Nie przez `strata connect opencode --write`: pisze format opencode
        # v1 (provider/npm) i zastąpiłby symlink na ten plik zwykłym plikiem.
        strata = {
          name = "Strata (local)";
          apiKey = "strata";
          baseUrl = "http://127.0.0.1:8080/v1";
          reasoningField = "reasoning_content";
        };
        # Serwer forka PrismML (`llama-prism serve`, parametry w wpisie modelu)
        # na 8080 — tym samym porcie co Strata, więc działa tylko jeden
        # z tych serwerów naraz. Serwer bez --api-key, więc klucz jest formalny;
        # tok myślenia oddaje w reasoning_content.
        llamacpp = {
          name = "llama.cpp (local)";
          apiKey = "llamacpp";
          baseUrl = "http://127.0.0.1:8080/v1";
          reasoningField = "reasoning_content";
        };
      };

      ai.models = {
        ollama-ornith-35b = {
          provider = "ollama";
          id = "ornith:35b";
          agents = [
            "prime-agent"
            "pi"
          ];
        };
        ollama-kimi-k3-cloud = visionReasoningModel "ollama" "kimi-k3:cloud";
        ollama-cloud-deepseek-v4-1-flash = visionReasoningModel "ollama-cloud" "deepseek-v4.1-flash:cloud";
        ollama-cloud-glm-5-3-flash = visionReasoningModel "ollama-cloud" "glm-5.3-flash:cloud";
        openrouter-deepseek-v4-1-flash =
          visionReasoningModel "openrouter" "deepseek/deepseek-v4.1-flash"
          // {
            name = "DeepSeek V4.1 Flash (OpenRouter)";
            context = 1048576;
            output = 384000;
            # USD za 1M tokenów (cennik OpenRouter).
            cost = {
              input = 0.15;
              output = 0.6;
              cacheRead = 0.003;
              cacheWrite = 0;
            };
          };

        # Przy 128K domyślne KV int8 (1931 MiB) nie zostawia w 8 GB VRAM
        # miejsca na cache ekspertów ani bufory prefillu; q4_0 mieści się na
        # styk (2026-10-26: 131 MiB wolnego po starcie, 55 MiB w trakcie
        # odpowiedzi, 26,7 tok/s). Bez klucza serwer i tak odrzuca strony
        # z przeglądarki (sprawdza Host i Origin).
        qwen3-8-flash-next-coder-iq1_m = strataModel "qwen3.8-flash-next-coder-iq1_m" "Qwen3.8-Flash-Next Coder IQ1_M (local)";
        # Gyro-M TQ2_0: jeden plik GGUF z tablicą n-gramów (pack gyro-gyro-m).
        qwen3-8-flash-next-gyro-gyro-m = strataModel "qwen3.8-flash-next-gyro-gyro-m" "Qwen3.8-Flash-Next Gyro-M TQ2_0 (local)";
        # Gołe `strata launch --context 128k --no-api-key` (silnik inkling2,
        # _strata). Bez myślenia i bez obrazów, więc flagi compat, które
        # podaje Strata (supportsDeveloperRole, supportsReasoningEffort), Pi
        # i tak stosuje tylko do modeli z reasoning.
        inkling-2-mini-sq-20 = {
          provider = "strata";
          id = "inkling-2-mini-sq-20";
          name = "Inkling-2-Mini (Strata, local)";
          context = 131072;
          output = 16384;
        };

        # Uruchomić w katalogu z plikami .gguf:
        # llama-prism serve -m Ternary-Bonsai-2.5-27B-PTQ1_0.gguf
        #   --mmproj Ternary-Bonsai-2.5-27B-mmproj-BF16.gguf --no-mmproj-offload
        #   --port 8080 -c 100000 -n 16384 -np 1 -ngl 99 -fa on -ctk q4_0 -ctv q4_0
        #   -ub 128 --reasoning-effort medium
        #   --reasoning-effort-allow xhigh,medium,low --cors-origins localhost
        # Szablon czatu przyjmuje tylko podane poziomy effort, inny daje HTTP 500.
        # KV: szybki kernel flash attention CUDA mają tylko pary q8_0/q8_0
        # i q4_0/q4_0; mieszane (q8_0/q4_0), q5_*, q4_1 i pq2_0m generują
        # o ~25-30% wolniej, iq4_nl liczy się na CPU. q4_0 względem f16: PPL
        # +0,1%, pq2_0m +6,8%. -ub 128 zamiast 256 zwalnia prefill o ~4%
        # i zostawia miejsce na 100K w 8 GB VRAM; 128K mieści się tylko z częścią
        # warstw na CPU (-ngl 57, ~15 tok/s). 2026-11-26: prompt 96K tokenów
        # przeszedł, ~440 MiB VRAM wolnego, prefill 387 tok/s, generowanie
        # 30 tok/s (41 tok/s przy pustym kontekście).
        ternary-bonsai-2-5-27b = {
          provider = "llamacpp";
          id = "Ternary-Bonsai-2.5-27B-PTQ1_0.gguf";
          name = "Ternary Bonsai 2.5 27B PTQ1_0 (local)";
          input = [
            "text"
            "image"
          ];
          context = 100000;
          output = 16384;
          reasoning = {
            efforts = [
              "xhigh"
              "medium"
              "low"
            ];
            offEffort = "none";
          };
        };
      };

      assertions = lib.mapAttrsToList (name: model: {
        assertion = !(model.enable && model.provider == "strata") || config.hardware.nvidia.enabled;
        message = "ai.models.${name}: Strata ma tylko silnik CUDA, a host nie ma sterownika NVIDIA.";
      }) config.ai.models;
    };
}
