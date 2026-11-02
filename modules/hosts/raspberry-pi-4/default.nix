# Host raspberry-pi-4: domowy serwer (RPi 4B, 4 GB RAM, dysk SSD po USB),
# usługi wystawione wyłącznie przez Cloudflare Tunnel (cloudflared.nix).
# Tu: wpis rejestru, stateVersion, konto i lista modułów hosta; płytka
# i wentylator: modules/hardware/raspberry-pi-4/. Agregat importuje też base,
# bo obraz SD (sd-image.nix) składa go poza rejestrem hostów.
{ self, ... }:
{
  hosts.raspberry-pi-4 = {
    system = "aarch64-linux";
    modules = [
      self.modules.nixos.raspberry-pi-4
      ./_hardware-configuration.nix
    ];
  };

  flake.modules.nixos.raspberry-pi-4 =
    { config, ... }:
    let
      user = config.customBot.defaultUser;
    in
    {
      imports = [
        self.modules.nixos.base
        self.modules.nixos.base-agenix
        self.modules.nixos.base-fail2ban
        self.modules.nixos.base-ssh-lan
        self.modules.nixos.base-lockdown
        self.modules.nixos.hardware-raspberry-pi-4
        self.modules.nixos.hardware-raspberry-pi-4-fan
        self.modules.nixos.rpi-resources
        self.modules.nixos.rpi-network
        self.modules.nixos.rpi-ssh
        self.modules.nixos.rpi-tools
        self.modules.nixos.rpi-cloudflared
        self.modules.nixos.rpi-nextcloud
        self.modules.nixos.rpi-gitea
        self.modules.nixos.rpi-hermes
        self.modules.nixos.rpi-matrix
        self.modules.nixos.rpi-ttyd
        self.modules.nixos.rpi-claude-notify
        self.modules.nixos.rpi-remote-agent
        self.modules.nixos.rpi-laptop-llm
        self.modules.nixos.rpi-ai
      ];

      system.stateVersion = "26.05";
      time.timeZone = config.customTop.locale.timeZone;

      # Hasło początkowe z obrazu SD: zmienić `passwd` po pierwszym logowaniu
      # (SSH i tak przyjmuje tylko klucze).
      users.users.${user} = {
        initialPassword = user;
        isNormalUser = true;
        description = user;
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
      };
    };
}
