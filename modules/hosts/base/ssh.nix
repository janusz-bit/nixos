{ self, inputs, ... }:
{
  flake.modules.nixos.base-ssh =
    { config, ... }:
    {
      services.openssh = {
        enable = true;
        # require public key authentication for better security
        settings.PasswordAuthentication = false;
        settings.KbdInteractiveAuthentication = false;
      };

      programs = {
        ssh = {
          startAgent = false;
          enableAskPassword = true;
          extraConfig = ''
            Host ssh.*
              User root
              ProxyCommand cloudflared access ssh --hostname %h
          '';
        };
        gnupg.agent.enable = true;
      };
    };

}
