# Agenix — sekrety BEZ globalnych exportów.
#
# Dawny environment.shellInit eksportował wszystkie klucze w każdym shellu,
# a przez import-environment trafiały one do całej sesji KDE — każda
# aplikacja i każdy agent AI dziedziczył komplet tokenów. Obecna zasada:
# sekret injektujemy per-proces, w najwęższym możliwym obwodzie:
#
#   * prime-agent / opencode / gemini — funkcje fish czytające /run/agenix/*
#     i przekazujące klucz tylko do danego procesu (set -lx + command ...),
#   * nix (access-tokens) — ~/.config/nix/nix.conf (0600) renderowany przez
#     oneshot systemd --user `nix-access-tokens`,
#   * `cachix push` — funkcja fish `cachix-push`.
#
# Wartości sekretów nigdy nie trafiają do /nix/store — pliki w /etc/fish-functions
# zawierają wyłącznie odwołania do /run/agenix (same nazwy ścieżek).
{ self, ... }:
{
  flake.modules.nixos.base-agenix =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      user = config.customBot.defaultUser;

      fishFunctions = {
        "prime-agent.fish" = ''
          function prime-agent --description "prime-agent z kluczem OLLAMA z agenix"
              set -lx OLLAMA_API_KEY (cat /run/agenix/ollama-api-key)
              command prime-agent $argv
          end
        '';
        "opencode.fish" = ''
          function opencode --description "opencode z kluczami API z agenix"
              set -lx OLLAMA_API_KEY (cat /run/agenix/ollama-api-key)
              set -lx OPENCODE_GO_API_KEY (cat /run/agenix/opencode)
              # llmgateway-api-key-shared to plik env ("KLUCZ=wartość")
              set -lx LLMGATEWAY_API_KEY (cat /run/agenix/llmgateway-api-key-shared | sed 's/^[^=]*=//')
              command opencode $argv
          end
        '';
        "gemini.fish" = ''
          function gemini --description "gemini CLI z kluczem GOOGLE z agenix"
              set -lx GOOGLE_API_KEY (cat /run/agenix/google-api-key)
              command gemini $argv
          end
        '';
        "cachix-push.fish" = ''
          function cachix-push --description "cachix push z tokenem z agenix"
              set -lx CACHIX_AUTH_TOKEN (cat /run/agenix/cachix-authtoken)
              command cachix push $argv
          end
        '';
      };

      # Część publiczna ~/.config/nix/nix.conf (substitutery); token dołączany
      # w runtime przez ExecStart — nigdy w /nix/store.
      nixConfBase = pkgs.writeText "nix.conf.base" ''
        substituters = https://cache.nixos.org https://janusz-bit.cachix.org https://cache.nixos.org/
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=
      '';
    in
    {
      imports = [ self.modules.nixos.agenix ];

      # === per-procesowe wrappery (funkcje fish) ===
      environment.etc = builtins.listToAttrs (
        lib.mapAttrsToList (
          name: text: lib.nameValuePair "fish-functions/${name}" { inherit text; }
        ) fishFunctions
      );

      systemd.tmpfiles.rules = [
        "d /home/${user}/.config/fish/functions 0750 ${user} users - -"
      ]
      ++ map (
        name: "L+ /home/${user}/.config/fish/functions/${name} - - - - /etc/fish-functions/${name}"
      ) (builtins.attrNames fishFunctions);

      # === nix: access-tokens z agenix w pliku 0600 (zamiast NIX_CONFIG w profilu) ===
      systemd.user.services.nix-access-tokens = {
        enable = true;
        description = "Render ~/.config/nix/nix.conf z access-tokens z agenix (0600)";
        script = ''
          set -euo pipefail
          umask 0077
          mkdir -p "$HOME/.config/nix"
          cp ${nixConfBase} "$HOME/.config/nix/nix.conf"
          chmod 600 "$HOME/.config/nix/nix.conf"
          printf 'access-tokens = github.com=%s\n' "$(cat ${config.age.secrets.github-token.path})" \
            >> "$HOME/.config/nix/nix.conf"
        '';
        wantedBy = [ "default.target" ];
      };
    };
}
