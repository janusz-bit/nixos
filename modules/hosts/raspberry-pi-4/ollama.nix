# Lokalna Ollama na RPi: endpoint providera `ollama` Prime Agenta (ai.models,
# localhost:11434), przez który idą też modele chmurowe `:cloud` — demon
# przekazuje je do ollama.com z kluczem OLLAMA_API_KEY. Słucha tylko na
# localhost.
#
# Sprawdzenie: `systemctl status ollama`,
# `curl -s http://127.0.0.1:11434/api/version`.
_: {
  flake.modules.nixos.rpi-ollama =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Modele `:cloud` bez klucza dają 401. ollama-api-key.age to surowa
      # wartość (bez KEY=), której EnvironmentFile nie czyta — stąd
      # LoadCredential i export tutaj.
      ollamaServe = pkgs.writeShellApplication {
        name = "ollama-serve";
        text = ''
          OLLAMA_API_KEY="$(<"$CREDENTIALS_DIRECTORY/ollama-api-key")"
          export OLLAMA_API_KEY
          exec ${lib.getExe config.services.ollama.package} serve
        '';
      };
    in
    {
      services.ollama.enable = true;

      systemd.services.ollama.serviceConfig = {
        LoadCredential = [ "ollama-api-key:${config.age.secrets.ollama-api-key.path}" ];
        # mkForce: zastępuje ExecStart modułu nixpkgs (`ollama serve`) tym
        # samym poleceniem w opakowaniu ustawiającym klucz.
        ExecStart = lib.mkForce (lib.getExe ollamaServe);
      };
    };
}
