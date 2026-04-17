let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcA/U1pLJuoQsS//IQ264xwbz5c9E+Yc+lZBZ/NavUm root@nixos";
  droid-android = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb1ln2lU/lR4NwlfUQ+oPurNDI+O6B0uiFCcWfYuGj3 root@nixos";
  raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgUBv6niliD4hpn9G8ngDZIFive/1qyVN9TV7S8pk9v root@raspberry-pi-4";
in
{
  "secret1.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "notes.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "nextcloud-adminpass.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
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
