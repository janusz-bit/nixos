# Narzędzia AI stacji roboczej: lokalna Ollama, llama.cpp i Strata, agenty
# kodujące (Codex, Claude Code, opencode, Pi, Antigravity), ChatGPT oraz alias
# claude-nixos. Klucze API wstrzykują wrappery fish (base/agenix.nix).
#
# Pi (pi-coding-agent) dostaje z ai-harness models.json i katalog skilli
# (/etc/pi), linkowane do ~/.pi/agent; settings.json zostaje plikiem
# użytkownika, bo Pi zapisuje w nim wybrany model, /settings i ostatnią wersję
# changelogu.
#
# Sprawdzenie: `ollama ps` (kolumna PROCESSOR: GPU przy NVIDII); `pi --list-models`
# (modele z ai.models), w sesji Pi `/skill:` podpowiada skille z ai.skills.
{ inputs, self, ... }:
{
  flake.modules.nixos.desktop-ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      user = config.customBot.defaultUser;
      piDir = "${config.users.users.${user}.home}/.pi";
    in
    {
      services.ollama = {
        enable = true;
        # Wariant CUDA dodaje katalog sterownika (runpath OpenGL) do LD_LIBRARY_PATH,
        # więc ollama znajduje libcuda.so.1; bez niego wykrywanie GPU kończy się
        # cicho na CPU (id=cpu w logu).
        package = lib.mkIf config.hardware.nvidia.enabled pkgs.ollama-cuda;
      };

      environment = {
        # Zawsze w devShellu: hooki z .claude/ i pre-commit potrzebują jego narzędzi.
        # `env -C` nie zmienia katalogu bieżącej powłoki; argumenty przechodzą
        # dalej (`claude-nixos --continue`).
        shellAliases.claude-nixos = "env -C ${config.customTop.repository.path} nix develop -c claude";

        # Bez uv: jest w base (hosts/base/configuration.nix).
        systemPackages =
          with pkgs;
          [
            codex
            claude-code
            # chatgpt z nixpkgs jest tylko na aarch64-darwin; llm-agents ma deb x86_64.
            inputs.llm-agents.packages.${system}.chatgpt
            repomix
            nodejs
            # Python bez biblioteki unsloth (unsloth-desktop niżej to osobna
            # aplikacja): torch z nixpkgs nie ma tu CUDA, a unsloth bez GPU się nie
            # importuje. Fine-tuning w projekcie uv z kołami torch+CUDA.
            (python3.withPackages (python-pkgs: [ python-pkgs.pip ]))
            antigravity-ide-fhs
            antigravity-cli
            inputs.llm-agents.packages.${system}.opencode2
            pi-coding-agent
            (llama-cpp.override { cudaSupport = config.hardware.nvidia.enabled; })
            self.packages.${system}.unsloth-desktop
            inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code-desktop
          ]
          # Strata ma tylko silnik CUDA (pakiet z wydania, _strata).
          ++ lib.optional config.hardware.nvidia.enabled strata;

        # Pi bez telemetrii instalacji i nagłówków atrybucji providera.
        sessionVariables.PI_TELEMETRY = "0";
      };

      # Katalog skilli przez L bez +: nie usuwa katalogu, który użytkownik
      # założył sam (własne skille Pi czyta też z ~/.agents/skills).
      systemd.tmpfiles.rules = [
        "d ${piDir} 0700 ${user} users - -"
        "d ${piDir}/agent 0700 ${user} users - -"
        "L+ ${piDir}/agent/models.json - - - - /etc/pi/models.json"
        "L ${piDir}/agent/skills - - - - /etc/pi/skills"
      ];
    };
}
