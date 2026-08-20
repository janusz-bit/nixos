_: {
  # Overlay: Ollama v0.32.15 (najnowsza stabilna) — nadpisuje pkgs.ollama z nixpkgs.
  # Używany na hoście nixos (workstation) do uruchamiania lokalnych modeli LLM.
  # Aktualizacja: podnieś `version`, `hash` (nix-prefetch-url --unpack) i `vendorHash`.
  # Fix sierpień 2026: nixpkgs nadpisuje `llamaCppVersion` wewnętrznym let-bindingiem
  # (hardcoded w pkgs/by-name/ol/ollama/package.nix). Po podbiciu src do v0.32.15
  # nixpkgs check w `postPatch` walił się na mismatch b10380 vs b10488.
  # Rozwiązanie: nadpisujemy postPatch, pre-stage źródło llama.cpp b10488,
  # stosujemy Ollama's compat patch i pomijamy check (znany pin pasuje).
  flake.overlays.ollama-latest = _final: prev: rec {
    llamaCppVersion = "b10488";
    llamaCppSrc = prev.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = llamaCppVersion;
      hash = "sha256-5noPIcSD9Ki1D3J7b6JofeXiPO1RdL/Q8z+E0ZCwceY=";
    };

    ollama = prev.ollama.overrideAttrs (_: rec {
      version = "0.32.15";
      src = prev.fetchFromGitHub {
        owner = "ollama";
        repo = "ollama";
        tag = "v${version}";
        hash = "sha256-BpN3y1unf6Yd1RBura2S4O5jLSkImzi1Guo6GWbNZI8=";
      };
      vendorHash = "sha256-7l4xzQ/Qm6kWH3mitRAAdbz+FU9PqwTKRoNO0C2kNMM=";

      # Zastępuje nixpkgs postPatch: pre-stage llama.cpp zgodnie z pinem
      # i pomijamy problematyczny check "llama-cpp version mismatch".
      postPatch = ''
        substituteInPlace version/version.go \
          --replace-fail 0.0.0 '${version}'

        rm cmd/launch/*_test.go
        rm -r app

        cp -r ${llamaCppSrc} $TMPDIR/llama-cpp-src
        chmod -R +w $TMPDIR/llama-cpp-src
        ( cd $TMPDIR/llama-cpp-src && \
          cmake -DPATCH_DIR=$NIX_BUILD_TOP/source/llama/compat \
            -P $NIX_BUILD_TOP/source/llama/compat/apply-patch.cmake )
      '';
    });
  };
}
