{ self, inputs, ... }:
{
  flake.nixosModules."base/ssh" =
    { config, ... }:
    {
      services.openssh = {
        enable = true;
        # require public key authentication for better security
        settings.PasswordAuthentication = false;
        settings.KbdInteractiveAuthentication = false;
      };

      programs.ssh.startAgent = false;
      programs.ssh.enableAskPassword = true;
      programs.gnupg.agent.enable = true;

      programs.ssh.extraConfig = ''
        Host ssh.*
          User ${config.custom.defaultUser}
          ProxyCommand cloudflared access ssh --hostname %h
      '';
    };

}
