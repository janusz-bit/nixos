{ self, inputs, ... }:
{
  flake.nixosModules.ssh =
    { ... }:
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
    };

}
