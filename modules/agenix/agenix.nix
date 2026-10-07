# Sekrety użytkownika (wrappery fish, nix access-tokens, skille). Właścicielem
# jest customBot.defaultUser, tryb 0400 — nie grupa `users`: na RPi do tej
# grupy należeli też użytkownicy usług (hermes). Moduł usługi, który
# potrzebuje dostępu, dopisuje go jawnie u siebie (np. trilium-etapi
# w modules/hosts/raspberry-pi-4/hermes.nix).
#
# Host odszyfrowuje tylko sekrety z customBot.userSecrets: bycie odbiorcą
# w modules/_secrets/agenix-rules.nix (kto MOŻE odszyfrować, np. RPi do rekeyingu)
# to co innego niż plik w /run/agenix (kto odszyfrowuje przy aktywacji).
# Wrappery fish i nix-access-tokens (modules/hosts/base/agenix.nix) powstają
# tylko dla obecnych sekretów.
{ inputs, customTop, ... }:
{
  flake.modules.nixos.agenix =
    { config, lib, ... }:
    let
      # nazwa w age.secrets -> plik w modules/_secrets
      files = {
        ollama-api-key = "ollama-api-key.age";
        secret1 = "secret1.age";
        github-token = "GITHUB_TOKEN.age";
        cachix-authtoken = "cachix-authtoken-token.age";
        notes = "notes.age";
        trilium-etapi = "trilium-etapi.age";
        google-api-key = "google-api-key.age";
        opencode = "opencode.age";
        llmgateway-api-key-shared = "llmgateway-api-key.age";
        openrouter-api-key = "openrouter-api-key.age";
      };
    in
    {
      imports = [
        inputs.agenix.nixosModules.default
      ];

      options.customBot.userSecrets = lib.mkOption {
        type = lib.types.listOf (lib.types.enum (lib.attrNames files));
        default = [ ];
        example = [
          "github-token"
          "ollama-api-key"
        ];
        description = ''
          Sekrety użytkownika (modules/agenix/agenix.nix) odszyfrowywane na
          tym hoście do /run/agenix dla customBot.defaultUser. Host musi być
          ich odbiorcą w modules/_secrets/agenix-rules.nix.
        '';
      };

      config.age = {
        secrets = lib.genAttrs config.customBot.userSecrets (name: {
          file = customTop.secretsDir + "/${files.${name}}";
          owner = config.customBot.defaultUser;
          mode = lib.mkDefault "0400";
        });
        identityPaths = [
          "/root/.ssh/id_ed25519"
        ];
      };
    };
}
