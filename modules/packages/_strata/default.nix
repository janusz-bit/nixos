# Strata (Niko1221/Strata): silnik inferencji dużych modeli MoE na zwykłym
# GPU — eksperci, którzy nie mieszczą się w VRAM, siedzą w RAM albo na SSD.
# Uruchamia m.in. Qwen3.8-Flash-Next w kwantyzacjach GSQ-RCO od
# ISTA-DASLab (`strata launch --family coder --model IQ1_M`), z API
# OpenAI/Anthropic na 127.0.0.1:8080. W nixpkgs go nie ma.
#
# Terminal (strata_cli, strata_control, serve, setup.py, tools) jest
# w Pythonie i pochodzi ze źródeł tagu; pliki to te z
# packaging/package_terminal.py, a VERSION (wersja Control, z którą silnik
# porównuje min_runtime) ten sam projekt CMake co w archiwum upstreamu.
# Silnik to gotowy pakiet CUDA 13 z tego samego wydania (sm_75/86/89/120,
# z dołączonymi cudart i cuBLAS): upstream buduje go CUDA 13.0, bo 13.2
# źle kompiluje sm_120, a build ze źródeł to lokalna kompilacja CUDA.
# autoPatchelf zmienia binarki, a Control sprawdza przy każdym starcie
# sha256 i rozmiar każdego pliku z engine-component.json oraz podpis
# ed25519 manifestu, więc manifest dostaje nowe sumy i signature = null
# (silnik figuruje jako unsigned). Autentyczność zapewnia hash fetchurl,
# zgodny z SHA256SUMS.txt wydania. libcuda.so.1 (sterownik) ładuje się przez
# LD_LIBRARY_PATH z wrappera, bo dlopen robią też sondy GPU w Pythonie.
#
# Wrapper odcina samoaktualizację (Control i silnik w read-only store):
# STRATA_UPDATE_FEED wskazuje nieistniejącą ścieżkę, więc `strata update`
# i zapasowe pobieranie silnika w `launch` kończą się błędem bez sieci;
# STRATA_CONTROL_INSTALL=1 trzyma setup.py w trybie aplikacji (bez pip
# i kompilatora, zapisy tylko do STRATA_INSTALL_DIR). Modele dalej pobiera
# z Hugging Face (domyślnie do ~/.local/share/strata/Strata-data, inny
# katalog: --data-dir). llama.cpp (gguf-py do przygotowania modelu) jest
# przypięty jak LLAMA_CPP_COMMIT w setup.py i linkowany do katalogu
# instalacji, jak w docker/entrypoint.sh — inaczej setup pobrałby zip.
#
# Aktualizacja: version (tag), hash src, engineVersion i hash silnika
# (wydanie podaje go w SHA256SUMS.txt; silnik Qwen bywa starszy niż
# Control), rev i hash llamaCpp z LLAMA_CPP_COMMIT w setup.py. Wydania
# wychodzą kilka razy dziennie, więc bez nix-update w flake-update.
#
# Sprawdzenie: `nix build .#strata` (installCheck uruchamia `strata
# --version`), potem na laptopie `strata components engine` (usable: true)
# i `strata launch --family coder --model IQ1_M --plan`.
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
  engineVersion = "0.1.50";

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

  llamaCpp = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  };

  unwrapped = stdenv.mkDerivation (finalAttrs: {
    pname = "strata-unwrapped";
    version = "0.2.6";

    src = fetchFromGitHub {
      owner = "Niko1221";
      repo = "Strata";
      tag = "v${finalAttrs.version}";
      hash = "sha256-HLlmKl+RDIP84KdifVUzduQ+ZN+51DbGaw9t+ITJkm8=";
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
      mkdir -p $app/docs $app/bench/prompts $app/ref
      cp -r strata.py strata_control strata_cli serve tools data setup.py \
        requirements.txt requirements-monitor.txt $app/
      cp docs/MANAGEMENT_PROTOCOL.md docs/TERMINAL_LAUNCH.md $app/docs/
      cp -r bench/prompts/standard-v1 $app/bench/prompts/
      cp ref/load.py $app/ref/
      sed -n 's/^[[:space:]]*project([^)]*VERSION[[:space:]]*\([0-9][0-9.]*\).*/\1/p' CMakeLists.txt \
        | head -n 1 > $app/VERSION
      test -s $app/VERSION

      # get_llama_cpp() przyjmuje katalog z gguf-py i ggml/CMakeLists.txt.
      llama=$app/third_party/llama.cpp
      mkdir -p $llama/ggml
      cp -r ${llamaCpp}/gguf-py ${llamaCpp}/LICENSE $llama/
      cp ${llamaCpp}/ggml/CMakeLists.txt $llama/ggml/

      engine=$app/components/engine/${engineVersion}-linux-x86_64-cuda-cuda13
      mkdir -p $engine
      tar -xzf ${finalAttrs.passthru.engine} -C $engine
      autoPatchelf $engine
      (
        cd $engine
        jq -r '.files[].path' engine-component.json | while IFS= read -r file; do
          jq -n --arg path "$file" \
            --arg sha256 "$(sha256sum "$file" | cut -d ' ' -f 1)" \
            --argjson bytes "$(stat -c %s "$file")" \
            '{ $path, $sha256, $bytes }'
        done | jq -s . > $TMPDIR/files.json
        jq --slurpfile files $TMPDIR/files.json '.files = $files[0] | .signature = null' \
          engine-component.json > $TMPDIR/engine-component.json
      )
      mv $TMPDIR/engine-component.json $engine/engine-component.json

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      HOME=$TMPDIR ${python.interpreter} $out/share/strata/strata.py --version \
        | grep -F "strata ${finalAttrs.version} "
      runHook postInstallCheck
    '';

    passthru.engine = fetchurl {
      url = "https://github.com/Niko1221/Strata/releases/download/v${finalAttrs.version}/strata-engine-${engineVersion}-linux-x86_64-cuda-cuda13.tar.gz";
      hash = "sha256-kMYB3BBgr0iqzPhQYpdaEcSuJWkOwkLjvJPplFfJOAs=";
    };

    meta = {
      description = "Inference engine for large MoE models on consumer GPUs, experts offloaded to RAM and SSD";
      homepage = "https://github.com/Niko1221/Strata";
      license = [
        lib.licenses.mit
        # cudart i cuBLAS dołączone do pakietu silnika
        lib.licenses.nvidiaCudaRedist
      ];
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [
        lib.sourceTypes.fromSource
        lib.sourceTypes.binaryNativeCode
      ];
    };
  });

  app = "${unwrapped}/share/strata";
in
writeShellApplication {
  name = "strata";
  runtimeInputs = [
    coreutils
    gnugrep
  ];
  text = ''
    STRATA_INSTALL_DIR=''${STRATA_INSTALL_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/strata/install}
    export STRATA_INSTALL_DIR
    export STRATA_COMPONENTS_DIR=${lib.escapeShellArg "${app}/components"}
    export STRATA_UPDATE_FEED=${lib.escapeShellArg "${app}/no-update-feed"}
    export STRATA_CONTROL_INSTALL=1
    export PYTHONNOUSERSITE=1
    export LD_LIBRARY_PATH=${lib.escapeShellArg "${addDriverRunpath.driverLink}/lib"}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Link odświeżany przy każdym starcie: po aktualizacji pakietu wskazuje
    # nowy llama.cpp. Prawdziwego katalogu (pobranego wcześniej) nie rusza.
    seed=$STRATA_INSTALL_DIR/third_party/llama.cpp
    mkdir -p "$STRATA_INSTALL_DIR/third_party"
    if [ -L "$seed" ] || [ ! -e "$seed" ]; then
      ln -sfnT ${lib.escapeShellArg "${app}/third_party/llama.cpp"} "$seed"
    fi

    # Konfiguracje uruchomienia (strata-<model>.json) zapisują ścieżki store
    # (cwd, --expert-profile, vision), a launch używa ich bez sprawdzania; po
    # GC starej wersji silnik nie wystartowałby. Bez nich setup pisze je od
    # nowa z istniejących plików modelu (jak docker/entrypoint.sh).
    for config in "$STRATA_INSTALL_DIR"/strata-*.json; do
      [ -f "$config" ] || continue
      while IFS= read -r path; do
        if [ ! -e "$path" ]; then
          rm -- "$config"
          break
        fi
      done < <(grep -oE '/nix/store/[^/"]+' "$config" | sort -u)
    done

    exec ${python.interpreter} ${lib.escapeShellArg "${app}/strata.py"} "$@"
  '';
  passthru = { inherit unwrapped; };
  meta = unwrapped.meta // {
    mainProgram = "strata";
  };
}
