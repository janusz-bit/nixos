# Zewnętrzne paczki skilli (format SKILL.md) z wejść flake'a dla agentów
# kodujących stacji roboczej: Claude Code, Codex, opencode i Prime Agent,
# oraz zarządzany /etc/opencode/opencode.json z lokalnym providerem llama.cpp
# (model Bonsai 2 27B PTQ1_0) i alias bonsai-serve, który uruchamia jego
# serwer.
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
# uruchamia alias `bonsai-serve` w katalogu z plikami .gguf (RTX 5060
# Laptop, 8 GB VRAM). Flagi aliasu i limity modelu w opencode biorą się
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
    { lib, ... }:
    let
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

      # Wspólne dla aliasu bonsai-serve i providera opencode2, więc -c/-n
      # serwera nie rozjadą się z limit.context/limit.output. Port jawnie:
      # fork zapowiada zmianę domyślnego 8080 na 9931.
      bonsai = {
        model = "Ternary-Bonsai-2-27B-PTQ1_0.gguf";
        mmproj = "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf";
        port = 8080;
        context = 65536;
        output = 16384;
      };

      # Model lokalny dla opencode2. Serwer uruchamia się ręcznie
      # (bonsai-serve); opencode2 pokazuje modele z tej listy także wtedy,
      # gdy serwer nie działa. Serwer startuje z --mmproj
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
          models."ternary-bonsai-2-27b" = {
            modelID = bonsai.model;
            name = "Ternary Bonsai 2 27B PTQ1_0 (local)";
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
              inherit (bonsai) context output;
            };
          };
        };
      };

      agentSkillDirs = [
        "claude-code/.claude/skills"
        "codex/skills"
        "ai-skills"
      ];
    in
    {
      # bonsai-serve uruchamiać w katalogu z plikami .gguf; argumenty z linii
      # poleceń trafiają na koniec. `llama` instaluje desktop-ai. Pomiary na
      # tym laptopie (2026-10-21, b10787, llama serve):
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
      #   ubatcha (ok. 485 MiB) i zaniża wynik. Sprawdzone także 81920 (szczyt
      #   7372 MiB przy 64K zajętego kontekstu).
      # Szablon czatu przyjmuje tylko effort xhigh/medium/low (inny daje HTTP
      # 500), a domyślne CORS `*` z credentials wpuszcza każdą stronę otwartą
      # w przeglądarce. Sampling (temp 1.0, top-k 20, top-p 0.95) pochodzi
      # z GGUF, --jinja jest domyślne.
      environment.shellAliases.bonsai-serve = lib.escapeShellArgs [
        "llama"
        "serve"
        "-m"
        bonsai.model
        "--mmproj"
        bonsai.mmproj
        "--no-mmproj-offload"
        "--port"
        (toString bonsai.port)
        "-c"
        (toString bonsai.context)
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
        "--reasoning-effort-allow"
        "xhigh,medium,low"
        "--cors-origins"
        "localhost"
      ];

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
