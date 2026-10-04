{ inputs, ... }:
let
  # claude-code-bundle: `claude` z nixpkgs opakowany razem z pluginami i
  # narzędziami, których te pluginy potrzebują — jedna paczka zamiast
  # ręcznego `/plugin install` na każdej maszynie (ten sam wzorzec co
  # opencode.nix; repo nie używa Home Managera). Pluginy ładuje flaga
  # `--plugin-dir <folder pluginów>` (sesyjne, read-only ze store, nie
  # dotykają ~/.claude/plugins). Działa też poza NixOS:
  #   nix run github:janusz-bit/nixos#claude-code-bundle
  #
  # Celowo NIE nadpisuje `claude-code`: Hermes na RPi używa czystego
  # `claude` jako „mózgu” i hooki SessionStart (learning-output-style,
  # superpowers) zmieniłyby jego zachowanie.
  mkClaudeCodeBundle =
    pkgs:
    let
      inherit (pkgs) lib;

      # Pluginy przypięte do commitów (jak pluginy opencode/Hermesa): kod
      # pluginów (hooki, skrypty) wykonuje się lokalnie, więc bez „latest”.
      # Bump: sha z marketplace.json oficjalnego katalogu
      # (anthropics/claude-plugins-official, pola source.sha), hash przez
      # `nix flake prefetch github:<owner>/<repo>/<rev>`.
      official = pkgs.fetchFromGitHub {
        owner = "anthropics";
        repo = "claude-plugins-official";
        rev = "d182ca456ca09d31d139f7d3818d1d333b103cce";
        hash = "sha256-LQ78jO8fzutmPJSsc3XeA+KqEP8wOrhH8AQaDCr/Pd8=";
      };
      superpowers = pkgs.fetchFromGitHub {
        owner = "obra";
        repo = "superpowers";
        rev = "5bf4e78011075bcfc0dc295f0724994cd123ee71"; # v6.4.1
        hash = "sha256-rgeJhjQyABYlhlyFRmgyhbZmmmIPPNkch4CXyTkGEyM=";
      };
      duckdbSkills = pkgs.fetchFromGitHub {
        owner = "duckdb";
        repo = "duckdb-skills";
        rev = "7feda8e01e22bc0886c86123f3884947e36d8c69"; # v0.2.4
        hash = "sha256-OmsODyirf2MzmoDMRx+c8xbkJWq2qOlMhXjKDV7PUv4=";
      };

      # pyright-lsp/clangd-lsp w katalogu mają tylko README — konfiguracja
      # LSP żyje w marketplace.json („strict”: false), którego --plugin-dir
      # nie czyta. Generujemy plugin.json sami, z absolutnymi ścieżkami do
      # serwerów ze store (nie zależą od PATH ani devShella projektu).
      lspPlugin =
        name: description: lspServers:
        pkgs.writeTextFile {
          inherit name;
          destination = "/.claude-plugin/plugin.json";
          text = builtins.toJSON {
            inherit name description lspServers;
            version = "1.0.0";
          };
        };

      pluginDir = pkgs.linkFarm "claude-code-plugins" [
        {
          # Tryb nauki: w kluczowych miejscach prosi o napisanie kodu samemu.
          name = "learning-output-style";
          path = "${official}/plugins/learning-output-style";
        }
        {
          name = "skill-creator";
          path = "${official}/plugins/skill-creator";
        }
        {
          name = "superpowers";
          path = superpowers;
        }
        {
          # SQL na CSV/Parquet/Excel; wymaga `duckdb` na PATH (niżej).
          name = "duckdb-skills";
          path = duckdbSkills;
        }
        {
          name = "pyright-lsp";
          path = lspPlugin "pyright-lsp" "Python language server (Pyright)" {
            pyright = {
              command = "${pkgs.pyright}/bin/pyright-langserver";
              args = [ "--stdio" ];
              extensionToLanguage = {
                ".py" = "python";
                ".pyi" = "python";
              };
            };
          };
        }
        {
          name = "clangd-lsp";
          path = lspPlugin "clangd-lsp" "C/C++ language server (clangd)" {
            clangd = {
              command = "${pkgs.clang-tools}/bin/clangd";
              args = [ "--background-index" ];
              extensionToLanguage = {
                ".c" = "c";
                ".h" = "c";
                ".cpp" = "cpp";
                ".cc" = "cpp";
                ".cxx" = "cpp";
                ".hpp" = "cpp";
                ".hxx" = "cpp";
                ".C" = "cpp";
                ".H" = "cpp";
              };
            };
          };
        }
      ];

      # document-skills (xlsx/docx/pptx/pdf z anthropics/skills) ma licencję
      # zabraniającą kopiowania i dystrybucji poza usługami Anthropic — nie
      # trafia do store (a stąd do publicznego cachixa). Wrapper instaluje go
      # raz przez sam Claude Code, jeśli nie ma go w ~/.claude; aktualizuje go
      # potem auto-update Claude Code (wyjątek od reguły przypinania).
      documentSkillsBootstrap = pkgs.writeShellApplication {
        name = "claude-document-skills-bootstrap";
        runtimeInputs = [
          pkgs.gnugrep
          pkgs.git
        ];
        text = ''
          cfg="''${CLAUDE_CONFIG_DIR:-''${HOME:-}/.claude}"
          id="document-skills@anthropic-agent-skills"
          if ! grep -qs "\"$id\"" "$cfg/plugins/installed_plugins.json"; then
            echo "claude-code-bundle: jednorazowa instalacja $id..." >&2
            claude=${pkgs.claude-code}/bin/claude
            "$claude" plugin marketplace add anthropics/skills >/dev/null 2>&1 || true
            "$claude" plugin install "$id" --scope user >/dev/null 2>&1 \
              || echo "claude-code-bundle: instalacja $id nieudana (offline?), ponowię przy następnym starcie" >&2
          fi
        '';
      };

      # Narzędzia dla skilli. --suffix: wersje z devShella projektu wygrywają.
      tools = with pkgs; [
        duckdb
        pandoc
        qpdf
        poppler-utils
      ];
    in
    pkgs.symlinkJoin {
      name = "claude-code-bundle-${pkgs.claude-code.version}";
      paths = [ pkgs.claude-code ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/claude \
          --run ${lib.getExe documentSkillsBootstrap} \
          --add-flags "--plugin-dir ${pluginDir}" \
          --suffix PATH : ${lib.makeBinPath tools}
      '';
      passthru = { inherit pluginDir; };
      meta = {
        inherit (pkgs.claude-code.meta) license platforms;
        description = "Claude Code with pinned plugins and their tools";
        mainProgram = "claude";
      };
    };
in
{
  flake.overlays.claude-code-bundle = final: _prev: {
    claude-code-bundle = mkClaudeCodeBundle final;
  };

  # `nix run .#claude-code-bundle` — osobny import nixpkgs, bo claude-code
  # jest unfree, a pkgs z perSystem nie ma allowUnfree.
  perSystem =
    { system, ... }:
    {
      packages.claude-code-bundle = mkClaudeCodeBundle (
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );
    };
}
