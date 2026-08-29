# Agenix — sekrety BEZ globalnych exportów.
#
# Dawny environment.shellInit eksportował wszystkie klucze w każdym shellu,
# a przez import-environment trafiały one do całej sesji KDE — każda
# aplikacja i każdy agent AI dziedziczył komplet tokenów. Obecna zasada:
# sekret injektujemy per-proces, w najwęższym możliwym obwodzie:
#
#   * prime-agent / opencode / gemini / cachix-push — funkcje fish z pakietu
#     wrappera (share/fish/vendor_functions.d, ładowane przez fish z
#     $NIX_PROFILES), czytające pliki age i przekazujące klucz tylko danemu
#     procesowi (set -lx + command ...),
#   * nix (access-tokens) — ~/.config/nix/nix.conf (0600) renderowany przez
#     oneshot systemd --user `nix-access-tokens`,
#   * `cachix push` — funkcja fish `cachix-push`.
#
# Odporność na zmiany ścieżek (nic nie jest hard-kodowane):
#   * ścieżki sekretów zawsze z config.age.secrets.<name>.path — zmiana
#     age.secretsDir lub nadpisana path po prostu się propaga,
#   * funkcje fish trafiają do share/fish/vendor_functions.d w profilu
#     systemowym (standard programs.fish.vendor.functions) — zero hard-
#     kodowanego /home/$user i tmpfile-symlinków; własna funkcja użytkownika
#     w ~/.config/fish/functions i tak ma pierwszeństwo w fish_function_path,
#   * URL i publiczny klucz cachix z customTop (jedno źródło prawdy).
#
# Wartości sekretów nigdy nie trafiają do /nix/store — wrappery zawierają
# wyłącznie odwołania do plików age (same ścieżki).
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
      # Ścieżka pliku z odszyfrowanym sekretem — zawsze przez opcje agenix,
      # nigdy literalnie /run/agenix.
      secretPath =
        name:
        (config.age.secrets.${name}
          or (throw "base-agenix: brak sekreta 'age.secrets.${name}' — zdefiniuj go w modules/agenix/agenix.nix")
        ).path;

      # Funkcje-wrappery: `name` = nazwa wykonywanego programu; `vars` =
      # zmienne środowiskowe podpinane pod sekrety agenix.
      fishWrappers = [
        {
          name = "prime-agent";
          description = "prime-agent z kluczem OLLAMA z agenix";
          vars = [
            {
              var = "OLLAMA_API_KEY";
              secret = "ollama-api-key";
            }
          ];
        }
        {
          name = "opencode";
          description = "opencode z kluczami API z agenix";
          vars = [
            {
              var = "OLLAMA_API_KEY";
              secret = "ollama-api-key";
            }
            {
              var = "OPENCODE_GO_API_KEY";
              secret = "opencode";
            }
            # llmgateway-api-key-shared to plik env ("KLUCZ=wartość") —
            # fish-native: bierz wszystko za pierwszym '='.
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
          vars = [
            {
              var = "GOOGLE_API_KEY";
              secret = "google-api-key";
            }
          ];
        }
        {
          name = "cachix-push";
          # zawijamy binarkę `cachix` z subkomendą `push`, nie funkcję `cachix-push`
          exec = "cachix push";
          description = "cachix push z tokenem z agenix";
          vars = [
            {
              var = "CACHIX_AUTH_TOKEN";
              secret = "cachix-authtoken";
            }
          ];
        }
      ];

      # Generyczny wrapper: zmienna env ładowana z pliku sekreta widoczna
      # TYLKO dla zawijanego procesu (set -lx). `command cat` celowo omija
      # aliasy/funkcje fish (w base-shell `cat` jest aliasem na `bat`).
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
          # zwykle = name; inaczej, gdy nazwa funkcji nie jest nazwą programu
          # (np. `cachix-push` opakowuje `cachix push`).
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

      # Część publiczna ~/.config/nix/nix.conf (substitutery); token dołączany
      # w runtime przez ExecStart — nigdy w /nix/store. URL i klucz cachix
      # z customTop, żeby konfiguracja cache nie rozjeżdżała się z flakiem
      # (flake.nix / nixConfig). Bez duplikatu cache.nixos.org.
      nixConfPublic = pkgs.writeText "nix.conf.public" ''
        substituters = https://cache.nixos.org ${customTop.cache.cachix.url}
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${customTop.cache.cachix.pubKey}
      '';

      # Katalog domowy defaultUsera — z opcji, nie literalnie /home/<user>
      # (może się zmienić np. między hostami).
      home = config.users.users.${config.customBot.defaultUser}.home;
    in
    {
      imports = [ self.modules.nixos.agenix ];

      # === per-procesowe wrappery (funkcje fish przez vendor_functions.d) ===
      # vendor.functions to warunek działania tego modułu — fish dodaje
      # <profil>/share/fish/vendor_functions.d do fish_function_path.
      programs.fish.vendor.functions.enable = true;
      environment.systemPackages = [ fishWrappersPkg ];

      # === nix: access-tokens z agenix w pliku 0600 (zamiast NIX_CONFIG w profilu) ===
      systemd.user.services.nix-access-tokens = {
        description = "Render ~/.config/nix/nix.conf z access-tokensem z agenix (0600)";
        wantedBy = [ "default.target" ];
        # oneshot z retryem: sekrety agenix są odszyfrowywane zanim sesja
        # użytkownika ruszy, ale przy pierwszym logowaniu po instalacji
        # lepiej by jednostka sprawdziła się drugi raz zamiast padnąć.
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
          {
            cat ${nixConfPublic}
            printf 'access-tokens = github.com=%s\n' "$(cat ${secretPath "github-token"})"
          } > "$tmp"
          chmod 600 "$tmp"
          mv -f "$tmp" "$conf"
        '';
      };

      # Migracja: usuń symlinki wrappera ze starego wariantu (wskazywały na
      # /etc/fish-functions, który już nie istnieje). Jednorazowa robota —
      # do skasowania, gdy wszystkie hosty zbudują się z tym wariantem.
      systemd.tmpfiles.rules = map (w: "r ${home}/.config/fish/functions/${w.name}.fish") fishWrappers;
    };
}
