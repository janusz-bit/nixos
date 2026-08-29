# Prime Agent jako External Agent w Zedzie (ACP).
#
# Zed uruchamia agentów ACP jako subprocess BEZ interaktywnego shella, więc
# subprocess nie dziedziczy OLLAMA_API_KEY z environment.shellInit (agenix) —
# chyba że Zed został odpalony z terminala. Rozwiązanie: wrapper
# (writeShellScriptBin), który czyta klucz wprost z pliku age-sekretu i odpala
# właściwy prime-agent w trybie ACP. Dzięki temu Zed może być odpalany także
# z launchera/kickoff, nie tylko z terminala.
#
# Podłączenie w Zedzie (settings.json użytkownika, ~/.config/zed/settings.json):
#   "agent_servers": {
#     "Prime Agent": {
#       "type": "custom",
#       "command": "/run/current-system/sw/bin/prime-agent-zed"
#     }
#   }
#
# Powiązane:
# - schemat models.json/settings.json prime-agenta: modules/hosts/base/prime-agent.nix
# - źródło klucza OLLAMA_API_KEY (agenix): modules/hosts/base/agenix.nix
{ inputs, ... }:
{
  flake.modules.nixos.base-prime-agent-zed =
    { config, pkgs, ... }:
    let
      primeAgent = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent;
      ageKeyFile = config.age.secrets.ollama-api-key.path;

      primeAgentZed = pkgs.writeShellScriptBin "prime-agent-zed" ''
        # Zed nie przekazuje shell-env do subprocessów agentów ACP — re-eksportuj
        # OLLAMA_API_KEY z age-sekretu, jeśli jeszcze go nie ma.
        if [ -z "$OLLAMA_API_KEY" ] && [ -r "${ageKeyFile}" ]; then
          export OLLAMA_API_KEY="$(cat ${ageKeyFile})"
        fi
        exec ${primeAgent}/bin/prime-agent --mode acp "$@"
      '';
    in
    {
      # Wrapper na PATH wszystkich hostów bazowych (nixos, raspberry-pi-4, wsl, droid).
      environment.systemPackages = [ primeAgentZed ];
    };
}
