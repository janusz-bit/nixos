let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrOn7Xvw90cBH1EJiFOR6r3RHXRsbFLm0Wpi6H+db+o root@nixos
";
  wsl = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq10J7I5kid1/2R3OZFGAqE9BDqYp1h98nHuBg5KylF root@nixos";
in
{
  "secret1.age" = {
    publicKeys = [
      nixos
      wsl
    ];
    armor = true;
  };
  "notes.age" = {
    publicKeys = [
      nixos
      wsl
    ];
    armor = true;
  };
}
