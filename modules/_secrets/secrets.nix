let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKVh4xGoawFG0akl0mh34/kUDvzC8NJ/wxGgAMF7rqzm root@nixos";
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
}
