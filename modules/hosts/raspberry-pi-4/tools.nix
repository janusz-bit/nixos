# Narzędzia CLI do pracy na serwerze, głównie dla agentów (Claude Code,
# Antigravity) i skryptów. micro, htop i uv pochodzą z base, git z base-git.
_: {
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
      ];
    };
}
