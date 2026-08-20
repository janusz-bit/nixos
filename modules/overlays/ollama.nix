_: {
  # Overlay: Ollama v0.32.15 (najnowsza stabilna) — nadpisuje pkgs.ollama z nixpkgs.
  # Używany na hoście nixos (workstation) do uruchamiania lokalnych modeli LLM.
  # Aktualizacja: podnieś `version`, `hash` (nix-prefetch-url --unpack) i `vendorHash`.
  flake.overlays.ollama-latest = _final: prev: {
    ollama = prev.ollama.overrideAttrs (_: rec {
      version = "0.32.15";
      src = prev.fetchFromGitHub {
        owner = "ollama";
        repo = "ollama";
        tag = "v${version}";
        hash = "sha256-BpN3y1unf6Yd1RBura2S4O5jLSkImzi1Guo6GWbNZI8=";
      };
      vendorHash = "sha256-7l4xzQ/Qm6kWH3mitRAAdbz+FU9PqwTKRoNO0C2kNMM=";
    });
  };
}
