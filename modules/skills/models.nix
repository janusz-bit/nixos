# Lokalne modele laptopa dla agentów kodujących, zadeklarowane
# w customBot.modelProviders: Ternary Bonsai 2 27B na forku llama.cpp od
# PrismML (provider llamacpp, serwer z aliasów bonsai-serve
# i bonsai-serve-mtp) i, przy NVIDIA, Qwen3.8-Flash-Next Coder z serwera
# Strata (provider strata). Do opencode2 i Prime Agenta wpina je ai-harness
# (harness.nix); alias llama-prism daje pozostałe polecenia forka.
#
# Nowy model to wpis w customBot.modelProviders niżej (pola opisuje
# modules/hosts/base/options.nix); oba agenty dostają go bez zmian
# w harness.nix. Oba serwery słuchają na 127.0.0.1:8080, więc działa jeden
# naraz.
#
# Tylko laptop (import w hosts/nixos): modele potrzebują GPU stacji roboczej.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.nixos.config.customBot.modelProviders`
# i `nix eval --raw .#nixosConfigurations.nixos.config.environment.shellAliases.bonsai-serve`.
_: {
  flake.modules.nixos.ai-models =
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

      # Port jawnie: fork zapowiada zmianę domyślnego 8080 na 9931. Strata
      # domyślnie słucha na tym samym.
      port = 8080;
      baseUrl = "http://127.0.0.1:${toString port}/v1";

      # Wspólne dla aliasów serwera i wpisów modeli, więc -c/-n serwera nie
      # rozjadą się z limitami w agentach. Klucz wariantu to nazwa modelu
      # w opencode2, `alias` to alias, który uruchamia jego serwer.
      bonsai = {
        mmproj = "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf";
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
              "--port ${toString port} -c ${toString variant.context} -n ${toString bonsai.output}"
              "-np 1 -ngl 99 -ctk q4_0 -ctv q4_0 -ub 256 --presence-penalty 1.0"
              "--reasoning-effort medium --reasoning-effort-allow xhigh,medium,low --cors-origins localhost"
            ]
            ++ variant.serverFlags
          )
        );
    in
    {
      customBot.modelProviders = {
        llamacpp = {
          name = "llama.cpp (local)";
          inherit baseUrl;
          models = lib.mapAttrs (_: variant: {
            id = variant.model;
            inherit (variant) name context;
            inherit (bonsai) input output;
            # Domyślny effort modelu to xhigh (szablon czatu); bez low, bo wg
            # karty modelu zachowuje się prawie jak xhigh.
            reasoningEfforts = [
              "medium"
              "xhigh"
            ];
          }) bonsai.variants;
        };

        # Serwer `strata launch --family coder --model IQ1_M --context 128k
        # --kv q4_0 --no-api-key` (desktop-ai). Nie przez `strata connect
        # opencode --write`: pisze format opencode v1 (provider/npm)
        # i zastąpiłby symlink na zarządzany opencode.json zwykłym plikiem.
        # Przy 128K domyślne KV int8 (1931 MiB) nie zostawia w 8 GB VRAM
        # miejsca na cache ekspertów ani bufory prefillu; q4_0 mieści się na
        # styk (2026-10-26: 131 MiB wolnego po starcie, 55 MiB w trakcie
        # odpowiedzi, 26,7 tok/s). Bez klucza serwer i tak odrzuca strony
        # z przeglądarki (sprawdza Host i Origin).
        strata = lib.mkIf config.hardware.nvidia.enabled {
          name = "Strata (local)";
          inherit baseUrl;
          models.qwen3-8-flash-next-coder-iq1_m = {
            id = "qwen3.8-flash-next-coder-iq1_m";
            name = "Qwen3.8-Flash-Next Coder IQ1_M (local)";
            # Obrazy czyta strata-vision na CPU (domyślne --vision przy <24 GB).
            input = [
              "text"
              "image"
            ];
            context = 131072;
            # Ponad OUTPUT_CAP = 4096, z którym Strata testuje swoje
            # konfiguracje agentów (strata_cli/launch/harness.py).
            output = 16384;
            # Poziomy, które serwer przyjmuje (EFFORT w serve/frontend.py;
            # high działa jak xhigh).
            reasoningEfforts = [
              "low"
              "medium"
              "high"
              "xhigh"
            ];
          };
        };
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
    };
}
