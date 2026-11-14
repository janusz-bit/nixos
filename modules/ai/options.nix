# Opcje ai.*: neutralny opis skilli i modeli, które mają dostać agenci kodujący
# hosta (Prime Agent, Pi, Claude Code, Codex, opencode2). Host tylko włącza to, co
# chce (`ai.skills.obscura.enable = true;`, `ai.models.<model>.enable = true;`,
# pliki ai.nix hostów), a definicje skilli i modeli (ai-skills, ai-models) oraz
# ich przełożenie na konfigurację każdego agenta (ai-harness) są w modules/ai/.
#
# Skill to katalog z SKILL.md, paczka skilli (skillPacks) to katalog takich
# katalogów z wejścia flake'a. Provider i model opisują serwer zgodny z API
# OpenAI i jego modele; do Prime Agenta, Pi i opencode2 trafiają tylko włączone
# modele (pole agents), a provider dopiero z pierwszym takim modelem.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.nixos.config.ai.models --apply 'ms: builtins.filter (n: ms.${n}.enable) (builtins.attrNames ms)'`
# (analogicznie ai.skills i ai.skillPacks).
_: {
  flake.modules.nixos.ai-options =
    { lib, ... }:
    let
      skillAgents = [
        "prime-agent"
        "pi"
        "claude-code"
        "codex"
        "opencode"
      ];
      modelAgents = [
        "prime-agent"
        "pi"
        "opencode"
      ];

      enableOption =
        what:
        lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Czy ${what} ma trafić do agentów hosta.";
        };
    in
    {
      options.ai = {
        skills = lib.mkOption {
          default = { };
          description = "Skille (katalog z SKILL.md) znane konfiguracji; do agentów trafiają włączone.";
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }:
              {
                options = {
                  enable = enableOption "skill ${name}";
                  source = lib.mkOption {
                    type = lib.types.path;
                    description = "Katalog skilla (SKILL.md, references/, przy skillu pythonowym też src/ i pyproject.toml).";
                  };
                  agents = lib.mkOption {
                    type = lib.types.listOf (lib.types.enum skillAgents);
                    default = skillAgents;
                    description = "Agenci, którzy dostają skill; węższa lista dla skilla, który działa tylko w jednym (kernel Pythona Prime Agenta, hooki Claude Code).";
                  };
                  packages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [ ];
                    description = "Programy, bez których skill nie działa; instalowane razem z nim, żeby nie trafił na host bez swojego narzędzia.";
                  };
                  python = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Skill pythonowy: jego src/ trafia do PYTHONPATH kernela Prime Agenta (agents musi zawierać prime-agent).";
                  };
                };
              }
            )
          );
        };

        skillPacks = lib.mkOption {
          default = { };
          description = "Paczki skilli: katalog, którego podkatalogi z SKILL.md są skillami. Nazwa skilla z dwóch źródeł kończy ewaluację błędem.";
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }:
              {
                options = {
                  enable = enableOption "paczka skilli ${name}";
                  source = lib.mkOption {
                    type = lib.types.path;
                    description = "Katalog z podkatalogami skilli (wejście flake'a, nie wynik fetchera: nazwy czyta builtins.readDir).";
                  };
                };
              }
            )
          );
        };

        opencode.settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            opencode2: pozostałe pola zarządzanego opencode.json w schemacie v2
            (np. model, agents, compaction, share, update), nie v1 z `strata
            connect opencode` (provider, small_model, autoupdate). Pole
            providers buduje ai-harness z włączonych ai.models.
          '';
        };

        providers = lib.mkOption {
          default = { };
          description = "Serwery zgodne z API OpenAI, z których korzystają modele.";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                baseUrl = lib.mkOption {
                  type = lib.types.str;
                  description = "Adres API (z /v1).";
                };
                name = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Nazwa w interfejsie opencode2.";
                };
                apiKeyEnv = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    Prime Agent i Pi: nazwa zmiennej env z kluczem (wartość
                    wstrzykuje wrapper z agenix, nigdy nie trafia do /nix/store);
                    ma pierwszeństwo przed apiKey.
                  '';
                };
                apiKey = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    Prime Agent i Pi: klucz literalny dla serwera, który klucza
                    nie sprawdza. Provider z modelem jednego z nich potrzebuje
                    apiKeyEnv albo apiKey.
                  '';
                };
                compat = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                  description = "Prime Agent i Pi: flagi compat providera (schemat models.json).";
                };
                reasoningField = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "opencode2: pole odpowiedzi z tokiem myślenia (compatibility.reasoningField).";
                };
              };
            }
          );
        };

        models = lib.mkOption {
          default = { };
          description = "Modele znane konfiguracji; do agentów trafiają włączone.";
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }:
              {
                options = {
                  enable = enableOption "model ${name}";
                  provider = lib.mkOption {
                    type = lib.types.str;
                    description = "Nazwa wpisu w ai.providers.";
                  };
                  id = lib.mkOption {
                    type = lib.types.str;
                    description = "Identyfikator modelu wysyłany do API.";
                  };
                  name = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Nazwa w interfejsie agenta.";
                  };
                  agents = lib.mkOption {
                    type = lib.types.listOf (lib.types.enum modelAgents);
                    default = modelAgents;
                    description = "Agenci, którzy widzą model.";
                  };
                  input = lib.mkOption {
                    type = lib.types.listOf (
                      lib.types.enum [
                        "text"
                        "image"
                      ]
                    );
                    default = [ "text" ];
                    description = "Rodzaje wejścia; Prime Agent i Pi znają tylko text i image.";
                  };
                  context = lib.mkOption {
                    type = lib.types.nullOr lib.types.ints.positive;
                    default = null;
                    description = "Okno kontekstu w tokenach; wymagane dla opencode2.";
                  };
                  output = lib.mkOption {
                    type = lib.types.nullOr lib.types.ints.positive;
                    default = null;
                    description = "Limit tokenów wyjścia; wymagany dla opencode2.";
                  };
                  reasoning = lib.mkOption {
                    default = null;
                    description = "Model z myśleniem (null: bez).";
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          efforts = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                            description = "Poziomy effort, które serwer przyjmuje (puste: agent nie dostaje listy). Prime Agent i Pi mapują poziomy o tych nazwach na siebie, resztę wyłączają.";
                          };
                          offEffort = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Prime Agent i Pi: wartość effort, która wyłącza myślenie (razem z efforts).";
                          };
                        };
                      }
                    );
                  };
                  cost = lib.mkOption {
                    type = lib.types.nullOr (lib.types.attrsOf lib.types.number);
                    default = null;
                    description = "Prime Agent i Pi: cennik (input, output, cacheRead, cacheWrite) w USD za 1M tokenów.";
                  };
                };
              }
            )
          );
        };
      };
    };
}
