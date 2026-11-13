# REA (morluto/rea, pakiet npm rea-agents): CLI `rea` i serwer MCP (`rea mcp`)
# do reverse engineeringu binarek natywnych, aplikacji JavaScript/Electron,
# .NET, APK, firmware'u i stron WWW, plus skill reverse-engineer-anything dla
# agentów. W nixpkgs go nie ma.
#
# Źródłem jest tarball z rejestru npm, nie tag z GitHuba: zawiera gotowe dist/
# i skills/, a build ze źródeł idzie przez turbo i artefakty innych platform.
# Od 6.9.0 tarball zawiera npm-shrinkwrap.json, z którego buildNpmPackage
# (fetchNpmDeps i npmConfigHook) bierze zależności — te same wersje, które
# dostaje `npx rea-agents`.
#
# Node 26: package.json wymaga ^22.23.4 || ^24.22.1 || >=26.12.1, nodejs (24)
# z nixpkgs jest starszy, a analiza baz SQLite potrzebuje 24.15+ albo 26.
# Skrypty instalacyjne są wyłączone: jedyny to opcjonalne frida (pobiera
# binarkę z sieci, której w sandboxie nie ma), więc instrumentacja Fridą nie
# działa; node-pty przychodzi jako gotowy pakiet platformy. `ps` z procps,
# którym REA na Linuksie sprawdza właściciela procesów przed uruchomieniem
# Ghidry, JADX czy analizy JavaScriptu, jest w systemowym PATH każdego hosta
# NixOS. Silniki natywne (Ghidra przez GHIDRA_INSTALL_DIR, IDA, JADX) REA
# bierze z zewnątrz; `rea doctor` zgłasza NixOS jako unsupported_host, bo
# szuka apt/dnf/pacman, ale to sprawdzenie dotyczy tylko auto-instalacji
# Hoppera.
#
# Sprawdzenie: `nix build .#rea-agents` (installCheck uruchamia `rea
# --version`), potem `rea doctor --json` i `rea setup --client claude_code
# --dry-run --json` (Command: /run/current-system/sw/bin/rea "mcp").
{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_26,
  nix-update-script,
  versionCheckHook,
}:

buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.9.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${finalAttrs.version}.tgz";
    hash = "sha256-MiM4oVBeJVdwKhYBLn1Gq9tXKWQdmJOGYnYt+/t5Jio=";
  };

  npmDepsHash = "sha256-6hRmFRsPY6U5O0tpwA3mAUZIic5cO+M/kAs326Q3lNI=";

  nodejs = nodejs_26;

  dontNpmBuild = true;
  npmRebuildFlags = [ "--ignore-scripts" ];
  # npm pack (wybór plików do $out) uruchomiłby prepack upstreamu, który
  # buduje paczkę od nowa.
  npmPackFlags = [ "--ignore-scripts" ];

  # Symlink zamiast wrappera npmInstallHook: `rea setup` zapisuje
  # w konfiguracji agenta alias `rea` z PATH (/run/current-system/sw/bin/rea)
  # tylko wtedy, gdy wskazuje on ten sam plik co uruchomiony rea.mjs;
  # z wrapperem zapisałby ścieżkę /nix/store, którą usuwa GC po aktualizacji.
  postInstall = ''
    for name in rea rea-agents; do
      ln -sf ../lib/node_modules/rea-agents/scripts/rea.mjs "$out/bin/$name"
    done
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://rea.tools";
    changelog = "https://github.com/morluto/rea/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = lib.platforms.linux;
  };
})
