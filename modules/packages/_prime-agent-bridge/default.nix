{
  lib,
  python3,
  uv,
  writeShellScriptBin,
}:
# Mały serwer OpenAI-compatible (stdlib Python, bez zależności), który
# tłumaczy /v1/chat/completions na jednorazowe wywołania
# `prime-agent --print --mode json`. Podpięty jako trzeci backend
# open-webui na raspberry-pi-4 (modules/hosts/raspberry-pi-4/open-webui.nix,
# serwis systemd prime-agent-bridge).
lib.meta.addMetaAttrs
  {
    description = "OpenAI-compatible HTTP bridge for the Prime Agent CLI";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "prime-agent-bridge";
  }
  (
    writeShellScriptBin "prime-agent-bridge" ''
      # uv musi być na PATH: prime-agent przy pierwszym użyciu bootstrapuje
      # kernel-venv IPythona przez uv (jednorazowo, potem cache w $HOME).
      export PATH="${lib.getBin uv}/bin:$PATH"
      # Seed ~/.prime/agent (models.json, settings.json, skille) przy
      # starcie: robi to hook --run wrappera prime-agent, a lista
      # /v1/models jest czytana z models.json — bez tego open-webui
      # widziałby tylko model domyślny aż do pierwszego czatu.
      # --version nie wykonuje żadnego wywołania API (~kilka s startu Node).
      "''${PRIME_AGENT_BIN:-prime-agent}" --version >/dev/null 2>&1 || :
      exec "${lib.getExe python3}" "${./bridge.py}" "$@"
    ''
  )
