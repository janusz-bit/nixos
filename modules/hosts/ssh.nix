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
      # By default, KDE prompts you to enter the passwords for your SSH keys to unlock them across session starts. To avoid being asked to unlock your SSH keys every time a session is restarted (e.g., after logging out or rebooting), you can use ksshaskpass to store the passwords.
      environment.variables = {
        SSH_ASKPASS_REQUIRE = "prefer";
      };

      programs.ssh.startAgent = true;
      programs.gnupg.agent.enable = true;
    };

}
