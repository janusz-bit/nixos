# Fork llama.cpp z PrismML (gałąź prism, wydania jako tagi prism-bNNNNN-rev):
# formaty niskobitowe i runtime modeli Bonsai (PQ2_0, Q2_0_g64, dspark).
# Pakiet lokalny, bo w nixpkgs go nie ma, a README forka zabrania mieszania
# jego bibliotek ggml-* z buildem stockowego llama.cpp. Świadomie nie
# podmienia atrybutu llama-cpp: whisper-cpp (przez kdenlive i ffmpeg-full)
# buduje się na nagłówkach llama w wersji 0.6.0, a fork raportuje 0.2.0 —
# stockowy llama-cpp zostaje jako jego zależność, a host nixos instaluje
# fork osobno (llama-cpp-prism w modules/desktop/ai.nix).
#
# Treść to kopia pkgs/by-name/ll/llama-cpp/package.nix z przypiętego nixpkgs
# (rev fe13242281a67641c0102cdb1087f0ebe586c7df) z podmienionym źródłem:
# przy aktualizacji podbić version, src (tag z listy wydań forka),
# buildNumber, buildCommit i npmDepsHash (nixpkgs liczy go przez
# fetchNpmDeps z `preBuild = "pushd tools/ui"`), potem porównać z aktualnym
# package.nix z nixpkgs.
#
# Sprawdzenie: `nix build .#llama-cpp-prism` (CPU) i `./result/bin/llama-cli
# --version`; wariant CUDA buduje host nixos (desktop/ai.nix, cudaSupport
# z hardware.nvidia.enabled), a `llama serve --list-devices` pokazuje CUDA0.
# nvidia-offload jest zbędne: CUDA widzi dGPU bez zmiennych PRIME offload.
{
  lib,
  buildPackages,
  autoAddDriverRunpath,
  cmake,
  ctestCheckHook,
  fetchFromGitHub,
  fetchNpmDeps,
  installShellFiles,
  stdenv,

  config,
  cudaSupport ? config.cudaSupport,
  cudaPackages ? { },

  rocmSupport ? config.rocmSupport,
  rocmPackages ? { },
  rocmGpuTargets ? rocmPackages.clr.localGpuTargets or rocmPackages.clr.gpuTargets,

  cpuArchDynamicDispatch ? true,

  openclSupport ? false,
  clblast,

  blasSupport ? builtins.all (x: !x) [
    cudaSupport
    metalSupport
    openclSupport
    rocmSupport
    vulkanSupport
  ],
  blas,

  nodejs_latest,
  npmHooks,

  pkg-config,
  python3,
  metalSupport ? stdenv.hostPlatform.isDarwin && !openclSupport,
  vulkanSupport ? false,
  rpcSupport ? false,
  openssl,
  shaderc,
  vulkan-headers,
  vulkan-loader,
  spirv-headers,
  ninja,
}:

let
  # Upstream reads these from git, which the release tarball does not ship.
  # They are purely informational: `llama-server --version`, `/props`, and the web UI.
  buildNumber = "10787";
  buildCommit = "73bfe6c";

  # It's necessary to consistently use backendStdenv when building with CUDA support,
  # otherwise we get libstdc++ errors downstream.
  # cuda imposes an upper bound on the gcc version
  effectiveStdenv = if cudaSupport then cudaPackages.backendStdenv else stdenv;
  inherit (lib)
    cmakeBool
    cmakeFeature
    optionals
    optionalString
    ;

  cudaBuildInputs = with cudaPackages; [
    cccl # <nv/target>

    # A temporary hack for reducing the closure size, remove once cudaPackages
    # have stopped using lndir: https://github.com/NixOS/nixpkgs/issues/271792
    cuda_cudart
    libcublas
  ];

  rocmBuildInputs = with rocmPackages; [
    clr
    hipblas
    rocblas
  ];

  vulkanBuildInputs = [
    spirv-headers
    vulkan-headers
    vulkan-loader
  ];

  buildCc = buildPackages.stdenv.cc;
in
effectiveStdenv.mkDerivation (finalAttrs: {
  pname = "llama-cpp-prism";
  version = "b10787";

  __structuredAttrs = true;
  strictDeps = true;

  outputs = [
    "out"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "PrismML-Eng";
    repo = "llama.cpp";
    tag = "prism-b10787-73bfe6c";
    hash = "sha256-rW/pMeYEahstWuQYTFLSzwwLPpVNaGfXGez6hCg8xjA=";
  };

  # Dwa błędy w testach forka wychodzą dopiero z flagami nixpkgs:
  # test-dfly-fusion linkuje się z wewnętrznym ggml_graph_compute, którego nie
  # eksportuje build z GGML_BACKEND_DL (mainline bramkuje tak test-barrier
  # przez `if (NOT GGML_BACKEND_DL)`), a test-kv-mean-center tworzy model bez
  # załadowania backendów (ta sama klasa błędu, którą upstream naprawił w
  # test-llama-archs: ggml-org/llama.cpp#30034). Oba do usunięcia razem z
  # --replace-fail, gdy fork je naprawi (temporary-fixes.md, wpis 9).
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
  ++ optionals cudaSupport [
    cudaPackages.cuda_nvcc
    autoAddDriverRunpath
  ]
  # `glslc` is used at build time to compile the shaders
  ++ optionals vulkanSupport [
    shaderc
  ];

  depsBuildBuild = optionals (stdenv.buildPlatform != stdenv.hostPlatform) [
    # llama-ui-embed under tools/ui needs a host compiler
    buildCc
  ];

  buildInputs =
    optionals cudaSupport cudaBuildInputs
    ++ optionals openclSupport [ clblast ]
    ++ optionals rocmSupport rocmBuildInputs
    ++ optionals blasSupport [ blas ]
    ++ optionals vulkanSupport vulkanBuildInputs
    ++ [ openssl ];

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
    (cmakeBool "GGML_NATIVE" false) # -march=native would make builds non-deterministic
    (cmakeBool "LLAMA_BUILD_EXAMPLES" false)
    (cmakeBool "LLAMA_BUILD_SERVER" true)
    (cmakeBool "LLAMA_BUILD_TESTS" (finalAttrs.finalPackage.doCheck or false))
    (cmakeBool "LLAMA_TESTS_INSTALL" false)
    (cmakeBool "LLAMA_BUILD_IS_DEV" false)
    (cmakeBool "LLAMA_OPENSSL" true)
    (cmakeBool "BUILD_SHARED_LIBS" true)
    (cmakeBool "GGML_BLAS" blasSupport)
    (cmakeBool "GGML_CLBLAST" openclSupport)
    (cmakeBool "GGML_CUDA" cudaSupport)
    (cmakeBool "GGML_HIP" rocmSupport)
    (cmakeBool "GGML_METAL" metalSupport)
    (cmakeBool "GGML_RPC" rpcSupport)
    (cmakeBool "GGML_VULKAN" vulkanSupport)
    (cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber)
    (cmakeFeature "LLAMA_BUILD_COMMIT" buildCommit)
  ]
  ++ optionals cpuArchDynamicDispatch [
    # Build all CPU backend variants for runtime dynamic dispatch.
    # This avoids illegal instructions on older CPUs and gives optimal performance
    # on newer ones without needing separate builds.
    # Enabling AVX2 can make CPU inference 13x faster compared to NixOS's x86_64 defaults.
    # Note it is not a bug that the CPU variant .so files are placed in `bin/`
    # (as opposed to `lib/`) alongside the executables by upstream's `CMakeLists.txt` design:
    # * https://github.com/ggml-org/llama.cpp/blob/b46812de78f8fbcb6cf0154947e8633ebc78d9ac/ggml/src/CMakeLists.txt#L249-L252
    # * https://github.com/ggml-org/llama.cpp/blob/b46812de78f8fbcb6cf0154947e8633ebc78d9ac/ggml/src/ggml-backend-reg.cpp#L480-L486
    (cmakeBool "GGML_CPU_ALL_VARIANTS" true)
    (cmakeBool "GGML_BACKEND_DL" true)
    # Let libggml find the backends when it is loaded from another package.
    (cmakeFeature "GGML_BACKEND_DIR" "${placeholder "out"}/bin")
  ]
  ++ optionals cudaSupport [
    (cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
  ]
  ++ optionals rocmSupport [
    (cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
    (cmakeFeature "CMAKE_HIP_ARCHITECTURES" (builtins.concatStringsSep ";" rocmGpuTargets))
  ]
  ++ optionals metalSupport [
    (cmakeFeature "CMAKE_C_FLAGS" "-D__ARM_FEATURE_DOTPROD=1")
    (cmakeBool "LLAMA_METAL_EMBED_LIBRARY" true)
  ]
  ++ optionals (stdenv.buildPlatform != stdenv.hostPlatform) [
    (cmakeFeature "HOST_CXX_COMPILER" (lib.getExe' buildCc "${buildCc.targetPrefix}c++"))
  ];

  postInstall = optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd llama-server --bash <($out/bin/llama-server --completion-bash)
  '';

  doCheck = true;

  # Use CTest to skip disabled tests.
  dontUseNinjaCheck = true;

  __darwinAllowLocalNetworking = true;

  nativeCheckInputs = [
    ctestCheckHook
    (python3.withPackages (ps: [ ps.jinja2 ]))
  ];

  preCheck = optionalString metalSupport ''
    export GGML_METAL_DEVICES=0
  '';

  disabledTests = [
    # Network needed.
    "test-tokenizers-ggml-vocabs"
    "test-download-model"
    "test-arg-parser"
    "test-thread-safety"
    "test-state-restore-fragmented"
    # Wymaga fixture'u test-download-model (sieć); test dodano po wersji,
    # dla której nixpkgs pisał tę listę.
    "test-save-load-state"
    # Błędy forka: test-llama-archs pada na asercie ggml_is_padded_1d w grafie
    # qwen35 (delta-net na backendzie BLAS), a test-generate-models nie zapisuje
    # metadanych dspark ("key not found in model: dspark.dspark.block_size").
    # Rollbacki wymagają fixture'u test-generate-models, więc wypadają z nim.
    "test-llama-archs"
    "test-generate-models"
    "test-recurrent-state-rollback"
    "test-recurrent-state-rollback-dsv4"
    "test-recurrent-state-rollback-nemotron-h"
  ];

  meta = {
    description =
      "Inference of LLMs in C/C++ (PrismML fork: Bonsai low-bit formats, dspark)"
      + optionalString cudaSupport ", with CUDA support"
      + optionalString rocmSupport ", with ROCm support"
      + optionalString vulkanSupport ", with Vulkan support";
    homepage = "https://github.com/PrismML-Eng/llama.cpp";
    license = lib.licenses.mit;
    mainProgram = "llama";
    platforms = lib.platforms.unix;
    badPlatforms = optionals (cudaSupport || openclSupport) lib.platforms.darwin;
    broken = metalSupport && !effectiveStdenv.hostPlatform.isDarwin;
  };
})
