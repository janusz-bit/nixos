{ ... }:
{
  # ollama-cuda build fails because the setup-cuda-hook sets CUDAToolkit_ROOT
  # from include-in-cudatoolkit-root markers, but cuda_nvcc's marker is empty
  # (left empty when strictDeps is set during cuda_nvcc's build).
  # CMake's FindCUDAToolkit then can't find nvcc → "CUDA Toolkit not found".
  #
  # The ollama package already creates a cudaToolkit buildEnv (with nvcc) and
  # sets CUDA_PATH, but CMake uses CUDAToolkit_ROOT (the env var), not CUDA_PATH.
  # The env var is inherited by the child ExternalProject cmake process.
  #
  # Fix: (1) limit CUDA arches to sm_120 (RTX 5060 / Blackwell),
  # (2) append cuda_nvcc's store path to CUDAToolkit_ROOT in preConfigure
  #     (after the hook sets it, before cmake runs in preBuild).
  flake.overlays.ollama-cuda = final: prev: {
    ollama-cuda = (prev.ollama-cuda.override {
      cudaArches = [ "sm_120" ];
    }).overrideAttrs (old: {
      preConfigure = ''
        # Append cuda_nvcc's path to CUDAToolkit_ROOT so FindCUDAToolkit
        # finds nvcc in the child ExternalProject build.
        export CUDAToolkit_ROOT="''${CUDAToolkit_ROOT:+$CUDAToolkit_ROOT;}${final.cudaPackages.cuda_nvcc}"
      '' + (old.preConfigure or "");
    });
  };
}
