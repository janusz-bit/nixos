# Agenix — sekrety użytkownika (base-secrets) BEZ globalnych exportów,
# wstrzykiwane per proces, plus alias push. Opcjonalny: importują go nixos
# i raspberry-pi-4; WSL nie jest odbiorcą agenix.
#
# Export w environment.shellInit trafiłby przez import-environment do całej
# sesji KDE, czyli do każdej aplikacji i każdego agenta AI. Dlatego klucz
# dostaje tylko zawijany proces: funkcje fish z vendor_functions.d robią
# `set -lx` + `command …`, a token nix renderuje do ~/.config/nix/nix.conf
# (0600) jednostka --user nix-access-tokens. W store są tylko ścieżki plików.
#
# Granica: to chroni przed PRZYPADKOWYM wyciekiem przez env (logi, procesy
# potomne). Pliki należą do customBot.defaultUser (0400), więc proces tego
# użytkownika nadal może je przeczytać wprost.
{ self, customTop, ... }:
{
  flake.modules.nixos.base-agenix =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      secretPath =
        name:
        (config.age.secrets.${name}
          or (throw "base-agenix: brak sekreta 'age.secrets.${name}' — zdefiniuj go w modules/hosts/base/secrets.nix")
        ).path;

      # Zmienna env czytana z sekretu agenix (nazwa z base-secrets).
      secretEnv = var: secret: { inherit var secret; };

      # name: nazwa funkcji fish; exec: zawijane polecenie (domyślnie name).
      fishWrappers = [
        {
          name = "prime-agent";
          description = "prime-agent z kluczami OLLAMA/OPENROUTER i tokenem Trilium z agenix";
          # Tych nazw zmiennych używają models.json i settings.json (base-prime-agent).
          vars = [
            (secretEnv "OLLAMA_API_KEY" "ollama-api-key")
            (secretEnv "OPENROUTER_API_KEY" "openrouter-api-key")
            (secretEnv "TRILIUM_ETAPI_TOKEN" "trilium-etapi")
          ];
        }
        {
          name = "opencode";
          description = "opencode z kluczami API z agenix";
          vars = [
            (secretEnv "OLLAMA_API_KEY" "ollama-api-key")
            (secretEnv "OPENCODE_GO_API_KEY" "opencode")
            # Plik env ("KLUCZ=wartość"): wartość to wszystko za pierwszym '='.
            {
              var = "LLMGATEWAY_API_KEY";
              secret = "llmgateway-api-key-shared";
              valueFilter = "string split -m1 -f2 '='";
            }
          ];
        }
        {
          name = "gemini";
          description = "gemini CLI z kluczem GOOGLE z agenix";
          vars = [ (secretEnv "GOOGLE_API_KEY" "google-api-key") ];
        }
        {
          name = "cachix-push";
          exec = "cachix push";
          description = "cachix push z tokenem z agenix";
          vars = [ (secretEnv "CACHIX_AUTH_TOKEN" "cachix-authtoken") ];
        }
      ];

      # `command cat` omija alias cat → bat z base-shell.
      loadVarLines =
        name:
        {
          var,
          secret,
          valueFilter ? null,
        }:
        let
          path = secretPath secret;
          read = "command cat \"$__sec\"" + lib.optionalString (valueFilter != null) " | ${valueFilter}";
        in
        [
          "  set -l __sec \"${path}\""
          "  if not test -r \"$__sec\""
          "    echo \"${name}: nie mogę odczytać sekreta: $__sec\" >&2"
          "    return 1"
          "  end"
          "  set -lx ${var} (${read})"
        ];

      mkSecretWrapper =
        {
          name,
          description,
          vars,
          exec ? name,
        }:
        lib.concatStringsSep "\n" (
          [
            "# Wygenerowane automatycznie (modules/hosts/base/agenix.nix) — NIE edytuj."
            "function ${name} --description ${lib.escapeShellArg description}"
          ]
          ++ lib.concatMap (loadVarLines name) vars
          ++ [
            "  command ${exec} $argv"
            "end"
            ""
          ]
        );

      fishWrappersPkg = pkgs.symlinkJoin {
        name = "fish-secret-wrappers";
        paths = map (
          w: pkgs.writeTextDir "share/fish/vendor_functions.d/${w.name}.fish" (mkSecretWrapper w)
        ) fishWrappers;
      };
    in
    {
      imports = [ self.modules.nixos.base-secrets ];

      programs.fish = {
        # Bez tego fish nie szuka funkcji w <profil>/share/fish/vendor_functions.d.
        # Funkcja o tej samej nazwie w ~/.config/fish/functions wygrywa z wrapperem.
        vendor.functions.enable = true;
        shellAliases.push = "nix build ${customTop.repository.flake}#nixosConfigurations.${config.customBot.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | cachix-push ${customTop.cachix.name}";
      };
      environment.systemPackages = [ fishWrappersPkg ];

      systemd.user.services.nix-access-tokens = {
        description = "Render ~/.config/nix/nix.conf z access-tokensem z agenix (0600)";
        wantedBy = [ "default.target" ];
        # Retry zamiast porażki przy pierwszym logowaniu po instalacji.
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        script = ''
          set -euo pipefail
          # jawny PATH — jednostka --user nie musi nic odziedziczać
          PATH="${pkgs.coreutils}/bin:$PATH"
          conf_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/nix"
          conf="$conf_dir/nix.conf"
          mkdir -p "$conf_dir"
          chmod 700 "$conf_dir"
          # render atomowo (tmp + chmod + mv), żeby nix nigdy nie przeczytał
          # połówki pliku i żeby token nie lądował w pliku z luźnym trybem
          tmp="$(mktemp "$conf_dir/.nix.conf.XXXXXX")"
          trap 'rm -f "$tmp"' EXIT
          printf 'access-tokens = github.com=%s\n' "$(cat ${secretPath "github-token"})" > "$tmp"
          chmod 600 "$tmp"
          mv -f "$tmp" "$conf"
        '';
      };
    };
}
