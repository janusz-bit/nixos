{ inputs, ... }:
{
  flake.overlays.bootdev-cli-overlay = final: prev: {
    bootdev-cli = prev.bootdev-cli.overrideAttrs (oldAttrs: rec {
      # Nadpisujemy wersję na najnowszą zdefiniowaną
      version = "1.28.0";

      # Pobieramy nowy kod źródłowy z GitHuba używając prev.fetchFromGitHub
      src = prev.fetchFromGitHub {
        owner = "bootdotdev";
        repo = "bootdev";
        rev = "v${version}";
        hash = "sha256-sBPId1wEsIG1E+sf+pbqfz0xW0+PHVAoRYTkFLXpWOU=";
      };

      # Nowy vendorHash dla zależności języka Go
      vendorHash = "sha256-ZDioEU5uPCkd+kC83cLlpgzyOsnpj2S7N+lQgsQb8uY=";
    });
  };
}
