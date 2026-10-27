# Fork llama.cpp z PrismML (gałąź prism, wydania jako tagi prism-bNNNNN-rev):
# formaty niskobitowe i runtime modeli Bonsai (PQ2_0, Q2_0_g64, dspark).
# Pakiet lokalny, bo w nixpkgs go nie ma, a README forka zabrania mieszania
# jego bibliotek ggml-* ze stockowym llama.cpp. Nie podmienia atrybutu
# llama-cpp: whisper-cpp (przez kdenlive i ffmpeg-full) buduje się na
# nagłówkach llama 0.6.0, a fork raportuje 0.2.0. Uruchamiany przez aliasy
# ze skills/models.nix.
#
# overrideAttrs llama-cpp z nixpkgs z podmienionym źródłem: przy aktualizacji
# podbić version, src (tag z listy wydań forka), buildNumber, buildCommit
# i npmDepsHash. npmDeps z nixpkgs czyta src, patches i npmDepsHash przez
# finalAttrs, więc liczy się od źródła forka. Patch nixpkgs na mainline
# (ggml-org/llama.cpp#30034) odpada: fork ma własne poprawki w postPatch.
#
# Sprawdzenie: `nix build .#llama-cpp-prism` (CPU) i `./result/bin/llama-cli
# --version`; wariant CUDA (cudaSupport z hardware.nvidia.enabled) pokazuje
# CUDA0 w `llama-prism serve --list-devices`, bez nvidia-offload (CUDA widzi
# dGPU bez zmiennych PRIME offload).
{
  lib,
  config,
  fetchFromGitHub,
  llama-cpp,
  cudaSupport ? config.cudaSupport,
}:

let
  # nixpkgs trzyma je w let, więc podmienia się flagi CMake i preConfigure,
  # które je wstawiają.
  buildNumber = "10787";
  buildCommit = "73bfe6c";
in
(llama-cpp.override { inherit cudaSupport; }).overrideAttrs (
  finalAttrs: oldAttrs: {
    pname = "llama-cpp-prism";
    version = "b10787";

    src = fetchFromGitHub {
      owner = "PrismML-Eng";
      repo = "llama.cpp";
      tag = "prism-b10787-73bfe6c";
      hash = "sha256-rW/pMeYEahstWuQYTFLSzwwLPpVNaGfXGez6hCg8xjA=";
    };

    patches = [ ];

    # Tymczasowe (temporary-fixes.md nr 9): testy forka psują się z flagami
    # nixpkgs. test-dfly-fusion woła wewnętrzne ggml_graph_compute, którego build
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

    npmDepsHash = "sha256-2Q7XhaLAArmviOLdQsNbYTfdyDE5pW9lR26cRHEVl9k=";

    preConfigure = ''
      pushd ${finalAttrs.npmRoot}
      LLAMA_BUILD_NUMBER=${buildNumber} npm run build
      popd
    '';

    cmakeFlags = map (
      flag:
      if lib.hasPrefix "-DLLAMA_BUILD_NUMBER:" flag then
        lib.cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber
      else if lib.hasPrefix "-DLLAMA_BUILD_COMMIT:" flag then
        lib.cmakeFeature "LLAMA_BUILD_COMMIT" buildCommit
      else
        flag
    ) oldAttrs.cmakeFlags;

    disabledTests = oldAttrs.disabledTests ++ [
      # Wymaga fixture'u test-download-model (sieć).
      "test-save-load-state"
      # Błędy forka (temporary-fixes.md nr 9); rollbacki wymagają fixture'u
      # test-generate-models, więc wypadają z nim.
      "test-llama-archs"
      "test-generate-models"
      "test-recurrent-state-rollback"
      "test-recurrent-state-rollback-dsv4"
      "test-recurrent-state-rollback-nemotron-h"
    ];

    # updateScript z nixpkgs podbija mainline, nie fork.
    passthru = removeAttrs oldAttrs.passthru [ "updateScript" ];

    meta = oldAttrs.meta // {
      description =
        "Inference of LLMs in C/C++ (PrismML fork: Bonsai low-bit formats, dspark)"
        + lib.optionalString cudaSupport ", with CUDA support";
      homepage = "https://github.com/PrismML-Eng/llama.cpp";
    };
  }
)
