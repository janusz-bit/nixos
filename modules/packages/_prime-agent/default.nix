{
  lib,
  pkgs,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  writableTmpDirAsHomeHook,
  versionCheckHook,
}:

let
  # Domyślna konfiguracja providerów (Ollama Cloud + lokalne Ollama).
  # apiKey to NAZWA zmiennej środowiskowej (OLLAMA_API_KEY jest już
  # eksportowana globalnie przez base-agenix), więc żaden sekret nie
  # trafia do store.
  modelsJson = ./models.json;
  settingsJson = ./settings.json;

  # Seed na pierwszy start: kopiuj domyślne pliki konfiguracyjne do
  # ~/.prime/agent/ tylko jeśli jeszcze nie istnieją (nie nadpisuj
  # zmian użytkownika). Skrypt idzie do wrapProgram --run, więc musi
  # zawsze kończyć się sukcesem (inaczej wrapper przerywa start) i nie
  # może zakładać PATH/HOME (np. installCheck w sandboxie bez HOME).
  seedConfig = pkgs.writeShellScript "prime-agent-seed-config" ''
    if [ -n "''${PRIME_AGENT_CODING_AGENT_DIR:-}" ] || [ -n "''${HOME:-}" ]; then
      agent_dir="''${PRIME_AGENT_CODING_AGENT_DIR:-$HOME/.prime/agent}"
      ${pkgs.coreutils}/bin/mkdir -p "$agent_dir" 2>/dev/null || :
      [ -f "$agent_dir/models.json" ] || ${pkgs.coreutils}/bin/install -m 0644 "${modelsJson}" "$agent_dir/models.json" 2>/dev/null || :
      [ -f "$agent_dir/settings.json" ] || ${pkgs.coreutils}/bin/install -m 0644 "${settingsJson}" "$agent_dir/settings.json" 2>/dev/null || :
    fi
    true
  '';
in
buildNpmPackage (finalAttrs: {
  pname = "prime-agent";
  version = "0.7.2";

  # Oficjalny tarball release (nie ma go w npm registry). Zawiera gotowy
  # bundle JS + prebuildy modułów natywnych, ale BEZ package-lock.json.
  src = fetchurl {
    url = "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${finalAttrs.version}/prime-agent-${finalAttrs.version}.tgz";
    hash = "sha256-vFRx8qYm1ye4ikXrdF//k7EMVUo8T8WRLyXYxkuYf14=";
  };

  sourceRoot = "package";

  # Tarball release nie zawiera lockfile'a — vendored kopia wygenerowana
  # przez `npm install --package-lock-only` z package.json release'u.
  # Aktualizacja wersji wymaga jej ponownego wygenerowania!
  postPatch = ''
    install -m 0644 ${./package-lock.json} package-lock.json
  '';

  # package.json nie ma skryptu "build" — dist/ to gotowy bundle.
  dontNpmBuild = true;

  # Moduły natywne (zeromq, koffi) mają prebuildy tylko dla ABI Node 22
  # (zeromq: build/*/glibc-127-Release). Na nowszym Node zeromq próbowałby
  # kompilacji ze źródeł (cmake + vcpkg + libzmq).
  nodejs = nodejs_22;

  npmDepsHash = "sha256-pfqkJN3uIVpSO8NG7WLnH1jUmpmW5ozMoMUK6rXCXzQ=";

  # node_modules wchodzi do wyjścia bez referencji do cache npmDeps.
  disallowedReferences = [ finalAttrs.npmDeps ];

  postInstall = ''
    wrapProgram "$out/bin/prime-agent" --run "${seedConfig}"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckProgram = "${placeholder "out"}/bin/prime-agent";
  versionCheckProgramArg = "--version";

  meta = {
    description = "Self-improving, open-source AI coding agent (RLM-based)";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    changelog = "https://github.com/PrimeIntellect-ai/prime-agent/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "prime-agent";
  };
})
