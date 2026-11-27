# Strata (Niko1221/Strata): silnik inferencji dużych modeli MoE na zwykłym
# GPU — eksperci, którzy nie mieszczą się w VRAM, siedzą w RAM albo na SSD.
# Uruchamia m.in. Qwen3.8-Flash-Next w kwantyzacjach GSQ-RCO od
# ISTA-DASLab (`strata launch --family coder --model IQ1_M`), z API
# OpenAI/Anthropic na 127.0.0.1:8080. W nixpkgs go nie ma.
#
# Terminal (strata_cli, strata_control, serve, setup.py, tools) jest
# w Pythonie i pochodzi z terminal/ źródeł tagu; pliki to te z
# tools/packaging/package_terminal.py, a VERSION (wersja Control, z którą
# silnik porównuje min_runtime) ten sam projekt CMake (engine/CMakeLists.txt)
# co w archiwum upstreamu.
# Silnik to gotowy pakiet CUDA 13 z tego samego wydania (sm_75/86/89/120,
# z dołączonymi cudart i cuBLAS); obok niego leży osobny silnik
# strata-inkling (components/shapes/inkling2), bo Inkling-2-Mini (domyślny
# model gołego `strata launch`) nie biegnie na silniku Qwen, a Control
# pobrałby go do katalogu komponentów w store: upstream buduje go CUDA 13.0, bo 13.2
# źle kompiluje sm_120, a build ze źródeł to lokalna kompilacja CUDA.
# autoPatchelf zmienia binarki, a Control sprawdza przy każdym starcie
# sha256 i rozmiar każdego pliku z engine-component.json oraz podpis
# ed25519 manifestu, więc manifest dostaje nowe sumy i signature = null
# (oba silniki figurują jako unsigned). Autentyczność zapewnia hash fetchurl,
# zgodny z SHA256SUMS.txt wydania. libcuda.so.1 (sterownik) ładuje się przez
# LD_LIBRARY_PATH z wrappera, bo dlopen robią też sondy GPU w Pythonie.
#
# Wrapper (writeShellApplication) jest wkładany do $out/bin w installPhase,
# bo tylko tam znana jest ścieżka aplikacji leżącej w tym samym $out
# (podstawiana za @app@). Wrapper odcina samoaktualizację: STRATA_UPDATE_FEED
# wskazuje nieistniejącą ścieżkę, więc `strata update` i zapasowe pobieranie
# silnika w `launch` kończą się błędem bez sieci; STRATA_CONTROL_INSTALL=1
# trzyma setup.py w trybie aplikacji (bez pip i kompilatora, zapisy tylko do
# STRATA_INSTALL_DIR). Modele dalej pobiera z Hugging Face (domyślnie do
# ~/.local/share/strata/Strata-data, inny katalog: --data-dir). gguf-py
# i konwerter HF z llama.cpp upstream dołącza od 0.2.15
# (engine/third_party/strata-gguf-py), więc setup nic nie pobiera; leżą
# w $app/third_party, bo tam szukają ich setup.py (engine_src()) i
# tools/_paths.py, gdy obok aplikacji nie ma katalogu engine/.
#
# Aktualizacja: `nix-update --commit -F strata` (flake-update robi to samo) podbija
# version i src. Silnik ma własną numerację, a jego asset leży tylko
# w wydaniu, które go wydało, więc engineTag i engineVersion podbija się
# RĘCZNIE z SHA256SUMS.txt wydania (potem `nix-update -F strata
# --custom-dep engine --custom-dep inkling` przelicza oba hashe; strata-inkling
# wychodzi w tym samym wydaniu i z tą samą wersją co silnik). Nowszy Control ze starszym
# silnikiem działa: to silnik deklaruje min_runtime. Dlatego version, src
# i engine są atrybutami tej derywacji, a nie kryją się
# w wrapperze — tylko wtedy nix-update widzi położenie version/src
# i podmienia hashe.
#
# Sprawdzenie: `nix build .#strata` (installCheck uruchamia `strata
# --version`), potem na laptopie `strata components engine` (usable: true,
# także w wierszu inkling2), `strata launch --family coder --model IQ1_M
# --plan` i gołe `strata launch` (Inkling-2-Mini).
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  autoPatchelfHook,
  addDriverRunpath,
  jq,
  python3,
  coreutils,
  gnugrep,
  writeShellApplication,
}:

let
  # Tag wydania, które zawiera poniższy silnik: asset istnieje tylko tam, więc
  # nie wynika z `version` (nowszy Control działa ze starszym silnikiem).
  engineTag = "v0.2.20";
  engineVersion = "0.1.66";

  python = python3.withPackages (
    ps: with ps; [
      jinja2
      numpy
      pillow
      psutil
      pyyaml
      regex
      requests
      # TUI `strata launch` i `strata monitor`
      rich
      textual
      tqdm
      truststore
    ]
  );

  wrapper = writeShellApplication {
    name = "strata";
    runtimeInputs = [
      coreutils
      gnugrep
    ];
    text = ''
      app=@app@
      export STRATA_INSTALL_DIR=''${STRATA_INSTALL_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/strata/install}
      export STRATA_COMPONENTS_DIR="$app/components"
      export STRATA_UPDATE_FEED="$app/no-update-feed"
      export STRATA_CONTROL_INSTALL=1
      export PYTHONNOUSERSITE=1
      export LD_LIBRARY_PATH=${lib.escapeShellArg "${addDriverRunpath.driverLink}/lib"}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

      # Konfiguracje uruchomienia (strata-<model>.json) zapisują ścieżki store
      # (cwd, --expert-profile, vision), a launch używa ich bez sprawdzania; po
      # GC starej wersji silnik nie wystartowałby. Bez nich setup pisze je od
      # nowa z istniejących plików modelu (jak docker/entrypoint.sh).
      for config in "$STRATA_INSTALL_DIR"/strata-*.json; do
        [ -f "$config" ] || continue
        while IFS= read -r path; do
          [ -e "$path" ] || { rm -- "$config"; break; }
        done < <(grep -oE '/nix/store/[^/"]+' "$config" | sort -u)
      done

      exec ${python.interpreter} "$app/strata.py" "$@"
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "strata";
  version = "0.2.23";

  src = fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    tag = "v${finalAttrs.version}";
    hash = "sha256-s6Kuz3JIDdygNCMpvCtJZlkpjpyK6bwUKFVcTfQQXp8=";
  };

  # Silnik ma własną numerację, więc engineTag i engineVersion podbija się
  # ręcznie (SHA256SUMS.txt wydania); hashe przelicza
  # `nix-update -F strata --custom-dep engine --custom-dep inkling`.
  engine = fetchurl {
    url = "https://github.com/Niko1221/Strata/releases/download/${engineTag}/strata-engine-${engineVersion}-linux-x86_64-cuda-cuda13.tar.gz";
    hash = "sha256-E8W+vq8kV0sCMHhXvOar/T+GHzaCypjb42wcRh/V4Fk=";
  };
  inkling = fetchurl {
    url = "https://github.com/Niko1221/Strata/releases/download/${engineTag}/strata-inkling-${engineVersion}-linux-x86_64-cuda-cuda13.tar.gz";
    hash = "sha256-/aqHA3kYeYAjvTS04uHiODJBjVm5Qh8nmZWydGSIR8M=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    jq
  ];
  buildInputs = [ (lib.getLib stdenv.cc.cc) ];

  dontConfigure = true;
  dontBuild = true;
  # Silnik łata installPhase przed przeliczeniem manifestu; każda późniejsza
  # zmiana binarek w fixupPhase rozjechałaby sumy (postFixup biegnie przed
  # hookiem autoPatchelf).
  dontAutoPatchelf = true;
  dontStrip = true;
  dontPatchELF = true;
  autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" ];

  installPhase = ''
    runHook preInstall

    app=$out/share/strata
    mkdir -p $app/docs $app/third_party
    (
      cd terminal
      cp -r --parents strata.py strata_control strata_cli serve tools data setup.py \
        requirements.txt requirements-monitor.txt bench/prompts/standard-v1 ref/load.py $app/
    )
    cp docs/MANAGEMENT_PROTOCOL.md docs/TERMINAL_LAUNCH.md $app/docs/
    cp -r engine/third_party/strata-gguf-py $app/third_party/
    # `strata install` szuka setup.py w STRATA_INSTALL_DIR, a tu katalog
    # instalacji (dane użytkownika) jest oddzielony od aplikacji w store;
    # `strata launch` uruchamia setup.py z aplikacji, więc install robi to samo.
    substituteInPlace $app/strata_cli/cli.py --replace-fail \
      'installer = Path(os.environ.get("STRATA_INSTALL_DIR") or ROOT) / "setup.py"' \
      'installer = ROOT / "setup.py"'
    sed -n 's/^[[:space:]]*project([^)]*VERSION[[:space:]]*\([0-9][0-9.]*\).*/\1/p' engine/CMakeLists.txt \
      | head -n 1 > $app/VERSION
    test -s $app/VERSION

    installEngine() {
      local engine=$1/${engineVersion}-linux-x86_64-cuda-cuda13
      mkdir -p $engine
      tar -xzf $2 -C $engine
      autoPatchelf $engine
      (
        cd $engine
        jq -r '.files[].path' engine-component.json | while IFS= read -r file; do
          jq -n --arg path "$file" \
            --arg sha256 "$(sha256sum "$file" | cut -d ' ' -f 1)" \
            --argjson bytes "$(stat -c %s "$file")" \
            '{ $path, $sha256, $bytes }'
        done | jq --slurpfile files /dev/stdin '.files = $files | .signature = null' \
          engine-component.json > $TMPDIR/engine-component.json
      )
      mv $TMPDIR/engine-component.json $engine/engine-component.json
    }
    installEngine $app/components/engine ${finalAttrs.engine}
    installEngine $app/components/shapes/inkling2/engine ${finalAttrs.inkling}

    install -Dm755 ${lib.getExe wrapper} $out/bin/strata
    substituteInPlace $out/bin/strata --replace-fail '@app@' $app

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR ${python.interpreter} $out/share/strata/strata.py --version \
      | grep -F "strata ${finalAttrs.version} "
    runHook postInstallCheck
  '';

  meta = {
    description = "Inference engine for large MoE models on consumer GPUs, experts offloaded to RAM and SSD";
    homepage = "https://github.com/Niko1221/Strata";
    license = [
      lib.licenses.mit
      # cudart i cuBLAS dołączone do pakietu silnika
      lib.licenses.nvidiaCudaRedist
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "strata";
    sourceProvenance = [
      lib.sourceTypes.fromSource
      lib.sourceTypes.binaryNativeCode
    ];
  };
})
