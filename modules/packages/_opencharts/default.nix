{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  writeShellApplication,
  static-web-server,
  curl,
  xdg-utils,
  nix-update-script,
}:

let
  # Aplikacja to statyczny build Vite: przeglądarka nie ładuje skryptów
  # type="module" z file://, więc launcher serwuje dist na 127.0.0.1.
  # Stały port, bo rysunki, szablony i ustawienia wykresu siedzą
  # w localStorage danego originu — zmiana portu je "gubi".
  launcher = writeShellApplication {
    name = "opencharts-serve";
    runtimeInputs = [
      static-web-server
      curl
      xdg-utils
    ];
    text = ''
      port="''${OPENCHARTS_PORT:-4173}"
      url="http://127.0.0.1:$port/"

      # Kolejne uruchomienie (np. z menu) tylko otwiera kartę.
      if curl -fs -o /dev/null "$url"; then
        exec xdg-open "$url"
      fi

      static-web-server --host 127.0.0.1 --port "$port" \
        --root "$OPENCHARTS_ROOT" --log-level warn &
      server=$!
      trap 'kill "$server" 2>/dev/null || true' EXIT INT TERM

      for _ in $(seq 50); do
        curl -fs -o /dev/null "$url" && break
        sleep 0.1
      done
      echo "OpenCharts: $url (Ctrl+C kończy)"
      xdg-open "$url" || true
      wait "$server"
    '';
  };
in
buildNpmPackage (finalAttrs: {
  pname = "opencharts";
  version = "0-unstable-2026-11-10";

  # Upstream nie taguje wydań; flake-update podbija przez --version=branch.
  src = fetchFromGitHub {
    owner = "dylanpersonguy";
    repo = "OpenCharts";
    rev = "399e27538d8150796571dbdecbe920a54b771de4";
    hash = "sha256-D99PuhHzdqhbvswvRsaQCLo8em1yYxtYMCmiM43f1dk=";
  };

  npmDepsHash = "sha256-W+iD2wraSixzdNYeYsKhAZ3Ji2+6bpTH6B9fsmkKDsE=";

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  # Dane OHLC demo są w repo (src/services/demo/data), więc build nie
  # potrzebuje sieci.
  npmBuildScript = "build";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    cp -r dist $out/share/opencharts
    install -Dm444 public/icons/icon-512x512.png \
      $out/share/icons/hicolor/512x512/apps/opencharts.png
    makeWrapper ${lib.getExe launcher} $out/bin/opencharts \
      --set OPENCHARTS_ROOT $out/share/opencharts
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "opencharts";
      desktopName = "OpenCharts";
      comment = finalAttrs.meta.description;
      exec = "opencharts";
      icon = "opencharts";
      categories = [
        "Office"
        "Finance"
      ];
    })
  ];

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };

  meta = {
    description = "Browser trading terminal with charting, drawing tools and paper trading";
    homepage = "https://github.com/dylanpersonguy/OpenCharts";
    license = lib.licenses.mit;
    mainProgram = "opencharts";
    platforms = lib.platforms.linux;
  };
})
