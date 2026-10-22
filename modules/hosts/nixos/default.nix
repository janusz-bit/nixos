# Host nixos: laptop Lenovo LOQ 15IRX10 (i5-13450HX + RTX 5060, PRIME
# offload) — stacja robocza z Plasmą 6 i grami, użytkownik dinosaur.
# Tu jest tylko to, co czyni go tą maszyną: wpis rejestru, tożsamość
# (hostname, stateVersion, konto), dysk (disko.nix, snapper.nix), rozruch
# (boot.nix); SSH tylko z LAN-u daje base-ssh-lan. Funkcje stacji roboczej: modules/desktop/,
# gry: modules/gaming/, sprzęt: modules/hardware/LOQ-15IRX10/.
{ self, ... }:
{
  hosts.nixos = {
    system = "x86_64-linux";
    # Ciężki build (~400 pakietów, 3-5 h) — CI tylko przy PR i ręcznie.
    buildOnTags = false;
    modules = [
      self.modules.nixos.base
      self.modules.nixos.nixos
      self.modules.nixos.hardware-LOQ-15IRX10
    ];
  };

  flake.modules.nixos.nixos =
    { config, ... }:
    let
      user = config.customBot.defaultUser;
    in
    {
      imports = [
        self.modules.nixos.nixos-boot
        self.modules.nixos.nixos-disko
        self.modules.nixos.nixos-snapper
        self.modules.nixos.base-agenix
        self.modules.nixos.base-ssh-lan
        self.modules.nixos.desktop
        self.modules.nixos.gaming
        self.modules.nixos.base-fail2ban
        self.modules.nixos.ai-skills
        self.modules.nixos.ai-skills-external
        self.modules.nixos.nixos-remote-agent
        self.modules.nixos.nixos-claude-notify
      ];

      networking.hostName = "nixos";
      system.stateVersion = "25.11";

      customBot = {
        defaultUser = "dinosaur";
        # Desktopowy Trilium (trilium-desktop, ETAPI/MCP na 37840).
        triliumMcpUrl = "http://127.0.0.1:37840/mcp";
      };

      # Hasła początkowe install-system zmienia od razu przy instalacji.
      users.users = {
        ${user} = {
          initialPassword = user;
          isNormalUser = true;
          description = user;
          extraGroups = [
            "networkmanager"
            "wheel"
          ];
        };
        root.initialPassword = "root";
      };
    };

  flake.nixosConfigurations.default = self.nixosConfigurations.nixos;
}
