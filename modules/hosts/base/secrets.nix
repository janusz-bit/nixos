# Sekrety użytkownika wspólne dla hostów (wrappery fish, nix access-tokens,
# skille): właściciel customBot.defaultUser, tryb 0400, nigdy grupa `users`,
# do której należą też inne konta. Usługa, która potrzebuje sekretu, dopisuje
# dostęp jawnie u siebie (np. trilium-etapi w raspberry-pi-4/hermes.nix).
{ inputs, customTop, ... }:
{
  flake.modules.nixos.base-secrets =
    { config, lib, ... }:
    let
      userSecret = file: {
        file = customTop.secretsDir + "/${file}";
        owner = config.customBot.defaultUser;
        mode = lib.mkDefault "0400";
      };
    in
    {
      imports = [ inputs.agenix.nixosModules.default ];

      age = {
        secrets = {
          ollama-api-key = userSecret "ollama-api-key.age";
          secret1 = userSecret "secret1.age";
          github-token = userSecret "GITHUB_TOKEN.age";
          cachix-authtoken = userSecret "cachix-authtoken-token.age";
          notes = userSecret "notes.age";
          trilium-etapi = userSecret "trilium-etapi.age";
          google-api-key = userSecret "google-api-key.age";
          opencode = userSecret "opencode.age";
          llmgateway-api-key-shared = userSecret "llmgateway-api-key.age";
          openrouter-api-key = userSecret "openrouter-api-key.age";
        };
        identityPaths = [ "/root/.ssh/id_ed25519" ];
      };
    };
}
