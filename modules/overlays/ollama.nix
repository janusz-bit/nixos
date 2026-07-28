{ ... }:
{
  # ollama-cuda in nixpkgs builds for ALL real CUDA architectures by default
  # (sm_75, sm_80, sm_86, sm_89, sm_90, sm_100, sm_103, sm_120, sm_121).
  # Compiling 9 architectures is extremely resource-intensive and the build
  # fails at 73% (make Error 2) during the CUDA runner compilation.
  # Override to only build for the GPU actually present (RTX 5060 = sm_120).
  # This also speeds up the build dramatically (1 arch vs 9).
  flake.overlays.ollama-cuda = final: prev: {
    ollama-cuda = prev.ollama-cuda.override {
      cudaArches = [ "sm_120" ];
    };
  };
}