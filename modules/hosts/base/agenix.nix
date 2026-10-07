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
#     w ~/.config/fish/functions i tak ma pierwszeństwo w fish_function_path.
#
# Wartości sekretów nigdy nie trafiają do /nix/store — wrappery zawierają
# wyłącznie odwołania do plików age (same ścieżki).
#
# Wrapper i jednostka nix-access-tokens powstają tylko dla sekretów, które
# host odszyfrowuje (customBot.userSecrets, modules/agenix/agenix.nix);
# wrapper bez żadnego dostępnego sekretu nie powstaje wcale.
#
# Granica ochrony: wrappery chronią przed PRZYPADKOWYM wyciekiem przez env
# (logi, procesy potomne, cała sesja KDE). Pliki sekretów należą do
# customBot.defaultUser (0400, modules/agenix/agenix.nix), więc proces
# działający jako ten użytkownik nadal może je przeczytać wprost.
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
      # Ścieżka pliku z odszyfrowanym sekretem — zawsze przez opcje agenix,
      # nigdy literalnie /run/agenix.
      secretPath =
        name:
        (config.age.secrets.${name}
          or (throw "base-agenix: brak sekreta 'age.secrets.${name}' — dodaj go do customBot.userSecrets hosta")
        ).path;
      hasSecret = name: lib.elem name config.customBot.userSecrets;

      # Funkcje-wrappery: `name` = nazwa wykonywanego programu; `vars` =
      # zmienne środowiskowe podpinane pod sekrety agenix.
      fishWrappers = [
        {
          name = "prime-agent";
          description = "prime-agent z kluczami OLLAMA/OPENROUTER z agenix";
          vars = [
            {
              var = "OLLAMA_API_KEY";
              secret = "ollama-api-key";
            }
            {
              var = "OPENROUTER_API_KEY";
              secret = "openrouter-api-key";
            }
            {
              var = "TRILIUM_ETAPI_TOKEN";
              secret = "trilium-etapi";
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

      # Tylko zmienne z sekretami obecnymi na hoście; wrapper bez nich znika.
      activeWrappers = lib.filter (w: w.vars != [ ]) (
        map (w: w // { vars = lib.filter (v: hasSecret v.secret) w.vars; }) fishWrappers
      );

      fishWrappersPkg = pkgs.symlinkJoin {
        name = "fish-secret-wrappers";
        paths = map (
          w: pkgs.writeTextDir "share/fish/vendor_functions.d/${w.name}.fish" (mkSecretWrapper w)
        ) activeWrappers;
      };

    in
    {
      imports = [ self.modules.nixos.agenix ];

      # === per-procesowe wrappery (funkcje fish przez vendor_functions.d) ===
      # vendor.functions to warunek działania tego modułu — fish dodaje
      # <profil>/share/fish/vendor_functions.d do fish_function_path.
      programs.fish.vendor.functions.enable = true;
      environment.systemPackages = [ fishWrappersPkg ];

      # === nix: access-tokens z agenix w pliku 0600 (zamiast NIX_CONFIG w profilu) ===
      systemd.user.services.nix-access-tokens = lib.mkIf (hasSecret "github-token") {
        description = "Render ~/.config/nix/nix.conf z access-tokensem z agenix (0600)";
        wantedBy = [ "default.target" ];
        unitConfig = {
          # Jednostka --user startuje w KAŻDYM menedżerze użytkownika (root,
          # hermes, greeter). Sekret należy do defaultUsera; inni zapisywali
          # sobie nix.conf z pustym tokenem, a GitHub odpowiadał wtedy 401.
          # root też: `sudo nixos-rebuild … --flake github:…` (aliasy update)
          # czyta /root/.config/nix/nix.conf, a root czyta sekret mimo 0400.
          # „|” = warunek wyzwalający: wystarczy jeden z dwóch.
          ConditionUser = [
            "|${config.customBot.defaultUser}"
            "|root"
          ];
          # Brak pliku (świeża instalacja przed post-install) = pominięcie,
          # nie pętla restartów.
          ConditionPathExists = secretPath "github-token";
        };
        # Sekrety agenix są gotowe przed startem sesji, więc nie ma czego
        # ponawiać — błąd ma być widoczny, a nie zapętlony.
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        # Substitutery są w systemowym nix.conf (base-configuration) — tu
        # wyłącznie token, który nie może trafić do /nix/store.
        script = ''
          set -euo pipefail
          # jawny PATH — jednostka --user nie musi nic odziedziczać
          PATH="${pkgs.coreutils}/bin:$PATH"
          # Zwykłe przypisanie: błąd odczytu przerywa skrypt (set -e), czego
          # podstawienie w argumencie printf nie robiło — zapisywał się pusty
          # token, a jednostka zgłaszała sukces.
          token="$(cat ${lib.escapeShellArg (secretPath "github-token")})"
          if [ -z "$token" ]; then
            echo "nix-access-tokens: pusty sekret github-token" >&2
            exit 1
          fi
          conf_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/nix"
          conf="$conf_dir/nix.conf"
          mkdir -p "$conf_dir"
          chmod 700 "$conf_dir"
          # render atomowo (tmp + chmod + mv), żeby nix nigdy nie przeczytał
          # połówki pliku i żeby token nie lądował w pliku z luźnym trybem
          tmp="$(mktemp "$conf_dir/.nix.conf.XXXXXX")"
          trap 'rm -f "$tmp"' EXIT
          printf 'access-tokens = github.com=%s\n' "$token" > "$tmp"
          chmod 600 "$tmp"
          mv -f "$tmp" "$conf"
        '';
      };
    };
}
