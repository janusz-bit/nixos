let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcA/U1pLJuoQsS//IQ264xwbz5c9E+Yc+lZBZ/NavUm root@nixos";
  droid-android = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb1ln2lU/lR4NwlfUQ+oPurNDI+O6B0uiFCcWfYuGj3 root@nixos";
in
{
  "secret1.age" = {
    publicKeys = [
      nixos
      droid-android
    ];
    armor = true;
  };
  "notes.age" = {
    publicKeys = [
      nixos
      droid-android
    ];
    armor = true;
  };
  "nextcloud-adminpass.age" = {
    publicKeys = [
      nixos
      droid-android
    ];
    armor = true;
  };
  "GITHUB_TOKEN.age" = {
    publicKeys = [
      nixos
      droid-android
    ];
    armor = true;
  };
}
