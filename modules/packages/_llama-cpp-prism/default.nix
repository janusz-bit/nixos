# Fork llama.cpp z PrismML (gałąź prism, wydania jako tagi prism-bNNNNN-rev):
# formaty niskobitowe i runtime modeli Bonsai (PQ2_0, Q2_0_g64, dspark).
# Pakiet lokalny, bo w nixpkgs go nie ma, a README forka zabrania mieszania
# jego bibliotek ggml-* ze stockowym llama.cpp. Nie podmienia atrybutu
# llama-cpp: whisper-cpp (przez kdenlive i ffmpeg-full) buduje się na
# nagłówkach stockowego llama.cpp, a fork raportuje 0.2.0. Uruchamiany przez
# aliasy ze ai/models.nix.
#
# Samodzielna derywacja, nie overrideAttrs llama-cpp z nixpkgs: fork stoi na
# własnej wersji mainline, a bump bazy z 0.6.0 na 0.8.0 zmienił jej
# disabledTests i wysypał build tej samej wersji forka. Tylko warianty, których
# używa ten flake: CPU i CUDA. Przy aktualizacji podbić version, src (tag z listy
# wydań forka), buildNumber, buildCommit i npmDepsHash.
#
# Sprawdzenie: `nix build .#llama-cpp-prism` (CPU) i `./result/bin/llama-cli
# --version`; wariant CUDA (cudaSupport z hardware.nvidia.enabled) pokazuje
# CUDA0 w `llama-prism serve --list-devices`, bez nvidia-offload (CUDA widzi
# dGPU bez zmiennych PRIME offload).
{
  lib,
  autoAddDriverRunpath,
  blas,
  cmake,
  config,
  ctestCheckHook,
  cudaPackages,
  cudaSupport ? config.cudaSupport,
  fetchFromGitHub,
  fetchNpmDeps,
  installShellFiles,
  ninja,
  nodejs_latest,
  npmHooks,
  openssl,
  pkg-config,
  python3,
  stdenv,
  versionCheckHook,
}:

let
  # Upstream czyta je z gita, którego nie ma w źródle; trafiają tylko do
  # `--version`, `/props` i interfejsu WWW.
  buildNumber = "10787";
  buildCommit = "73bfe6c";

  # Biblioteki CUDA wymagają libstdc++ z backendStdenv, a CUDA ogranicza z góry
  # wersję gcc.
  effectiveStdenv = if cudaSupport then cudaPackages.backendStdenv else stdenv;
in
effectiveStdenv.mkDerivation (finalAttrs: {
  pname = "llama-cpp-prism";
  version = "b${buildNumber}";

  __structuredAttrs = true;
  strictDeps = true;

  outputs = [
    "out"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "PrismML-Eng";
    repo = "llama.cpp";
    tag = "prism-b${buildNumber}-${buildCommit}";
    hash = "sha256-rW/pMeYEahstWuQYTFLSzwwLPpVNaGfXGez6hCg8xjA=";
  };

  # Tymczasowe (temporary-fixes.md nr 9): testy forka psują się z tymi flagami.
  # test-dfly-fusion woła wewnętrzne ggml_graph_compute, którego build
  # z GGML_BACKEND_DL nie eksportuje, więc buduje się go pod tym samym
  # `if (NOT GGML_BACKEND_DL)` co test-barrier w mainline; test-kv-mean-center
  # tworzy model bez załadowanych backendów, więc dostaje llama_backend_init().
  postPatch = ''
    substituteInPlace tests/CMakeLists.txt \
      --replace-fail ${lib.escapeShellArg "    llama_build_and_test(test-dfly-fusion.cpp)\n"} \
      ${lib.escapeShellArg "    if (NOT GGML_BACKEND_DL)\n        llama_build_and_test(test-dfly-fusion.cpp)\n    endif()\n"}
    substituteInPlace tests/test-kv-mean-center.cpp \
      --replace-fail ${lib.escapeShellArg "int main() {\n    test_regression_safety();"} \
      ${lib.escapeShellArg "int main() {\n    llama_backend_init();\n\n    test_regression_safety();"}
  '';

  nativeBuildInputs = [
    cmake
    installShellFiles
    ninja
    nodejs_latest
    npmHooks.npmConfigHook
    pkg-config
  ]
  ++ lib.optionals cudaSupport [
    autoAddDriverRunpath
    cudaPackages.cuda_nvcc
  ];

  buildInputs = [
    openssl
  ]
  ++ lib.optionals cudaSupport [
    cudaPackages.cccl
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
  ]
  ++ lib.optionals (!cudaSupport) [ blas ];

  npmRoot = "tools/ui";
  npmDepsHash = "sha256-2Q7XhaLAArmviOLdQsNbYTfdyDE5pW9lR26cRHEVl9k=";
  npmDeps = fetchNpmDeps {
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    preBuild = ''
      pushd ${finalAttrs.npmRoot}
    '';
    hash = finalAttrs.npmDepsHash;
  };

  preConfigure = ''
    pushd ${finalAttrs.npmRoot}
    LLAMA_BUILD_NUMBER=${buildNumber} npm run build
    popd
  '';

  cmakeFlags = [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "GGML_BLAS" (!cudaSupport))
    (lib.cmakeBool "GGML_CUDA" cudaSupport)
    # -march=native zrobiłoby build niedeterministycznym; warianty CPU wybiera
    # w runtime GGML_BACKEND_DL, a katalog podaje się, bo libggml ładują też
    # inne pakiety. Pliki .so wariantów lądują w bin/ z założenia upstreamu.
    (lib.cmakeBool "GGML_NATIVE" false)
    (lib.cmakeBool "GGML_CPU_ALL_VARIANTS" true)
    (lib.cmakeBool "GGML_BACKEND_DL" true)
    (lib.cmakeFeature "GGML_BACKEND_DIR" "${placeholder "out"}/bin")
    (lib.cmakeBool "LLAMA_BUILD_EXAMPLES" false)
    (lib.cmakeBool "LLAMA_BUILD_IS_DEV" false)
    (lib.cmakeBool "LLAMA_BUILD_SERVER" true)
    (lib.cmakeBool "LLAMA_BUILD_TESTS" finalAttrs.finalPackage.doCheck)
    (lib.cmakeBool "LLAMA_OPENSSL" true)
    (lib.cmakeBool "LLAMA_TESTS_INSTALL" false)
    (lib.cmakeFeature "LLAMA_BUILD_COMMIT" buildCommit)
    (lib.cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber)
  ]
  ++ lib.optionals cudaSupport [
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
  ];

  postInstall = ''
    installShellCompletion --cmd llama-server --bash <($out/bin/llama-server --completion-bash)
  '';

  doCheck = true;

  # ctest pomija disabledTests, a cel `check` z ninja nie.
  dontUseNinjaCheck = true;

  nativeCheckInputs = [
    ctestCheckHook
    (python3.withPackages (ps: [ ps.jinja2 ]))
  ];

  # Fixture wyłączonego testu i tak by się uruchomił, jeśli wymaga go test
  # włączony, więc wyłącza się wszystkie zależne od pobieranego modelu.
  disabledTests = [
    # Wymagają sieci lub fixture'u test-download-model.
    "test-tokenizers-ggml-vocabs"
    "test-download-model"
    "test-arg-parser"
    "test-thread-safety"
    "test-state-restore-fragmented"
    "test-save-load-state"
    # Błędy forka (temporary-fixes.md nr 9); rollbacki wymagają fixture'u
    # test-generate-models, więc wypadają z nim.
    "test-llama-archs"
    "test-generate-models"
    "test-recurrent-state-rollback"
    "test-recurrent-state-rollback-dsv4"
    "test-recurrent-state-rollback-nemotron-h"
  ];

  # `--version` podaje numer builda bez przedrostka b z atrybutu version.
  nativeInstallCheckInputs = [ versionCheckHook ];
  preVersionCheck = "version=${buildNumber}";
  doInstallCheck = true;

  meta = {
    description =
      "Inference of LLMs in C/C++ (PrismML fork: Bonsai low-bit formats, dspark)"
      + lib.optionalString cudaSupport ", with CUDA support";
    homepage = "https://github.com/PrismML-Eng/llama.cpp";
    license = lib.licenses.mit;
    mainProgram = "llama";
    platforms = lib.platforms.linux;
  };
})
