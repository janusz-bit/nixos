let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjrLDPgDObcVj9Pt8YCXzeVDAnDSuuieAARRbk19QRU root@nixos";
  wsl = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb1ln2lU/lR4NwlfUQ+oPurNDI+O6B0uiFCcWfYuGj3 root@nixos";
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
