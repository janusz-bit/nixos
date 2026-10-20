# Narzędzia CLI do pracy na serwerze, głównie dla agentów (Claude Code,
# Antigravity, OpenCode 2) i skryptów. micro, htop i uv pochodzą z base,
# git z base-git.
{ inputs, ... }:
{
  flake.modules.nixos.rpi-tools =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        nodejs_22
        ripgrep
        ffmpeg
        python311
        tea # Gitea official CLI client
        antigravity-cli
        # Claude Code — agent kodujący w terminalu (nixpkgs)
        claude-code
        # OpenCode 2 CLI z llm-agents (binarka opencode2 obok opencode v1)
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2
      ];
    };
}
