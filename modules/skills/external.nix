# Zewnętrzne paczki skilli (format SKILL.md) z wejść flake'a dla agentów
# kodujących stacji roboczej: Claude Code, Codex, opencode i Prime Agent,
# oraz zarządzany /etc/opencode/opencode.json z lokalnym providerem llama.cpp
# (model Bonsai 2 27B PTQ1_0).
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
# skilli wpisuje też lokalny model: serwer `llama serve` z forka PrismML
# (modules/packages/_llama-cpp-prism) na 127.0.0.1:8080, uruchamiany ręcznie
# w katalogu z plikami .gguf (RTX 5060 Laptop, 8 GB VRAM):
#   llama serve -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -c 65536 -np 1 \
#     -n 16384 -ctk q4_0 -ctv q4_0 \
#     --mmproj Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf --no-mmproj-offload \
#     --reasoning-effort-allow xhigh,medium,low --cors-origins localhost
# -c i -n to limit.context i limit.output niżej. K i V w jednym typie: build
# ma kernele FlashAttention tylko dla par jednakowych, para q8_0/q4_0
# konwertuje cały KV do f16 przy każdym tokenie (w logu „converting K and V
# to f16”). Bez GGML_CUDA_ENABLE_UNIFIED_MEMORY: brak VRAM ma wywrócić
# ładowanie, a nie po cichu stronicować przez PCIe. Projektor wizyjny
# (600 MiB) liczy na CPU, bo wagi i KV 64K prawie wypełniają VRAM; największe
# -c, które się mieści, wypisuje `llama-fit-params -m … -ngl 99 -np 1 -ctk
# q4_0 -ctv q4_0` (bez -c; projektora nie liczy). Szablon czatu przyjmuje
# tylko effort xhigh/medium/low (inny daje HTTP 500), a domyślne CORS `*`
# z credentials wpuszcza każdą stronę otwartą w przeglądarce. Sampling
# (temp 1.0, top-k 20, top-p 0.95) pochodzi z GGUF, --jinja jest domyślne.
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

      # Model lokalny dla opencode2. Serwer uruchamia się ręcznie (llama
      # serve w katalogu z plikiem .gguf); opencode2 pokazuje modele z tej
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
          settings.baseURL = "http://127.0.0.1:8080/v1";
          models."ternary-bonsai-2-27b" = {
            modelID = "Ternary-Bonsai-2-27B-PTQ1_0.gguf";
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
              context = 65536;
              output = 16384;
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
