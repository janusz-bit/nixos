let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQRhJASMQB1ClDBwqnYGZXSSGAr1S2y5KaQ5Z0Fc5+ root@nixos";
  droid-android = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb1ln2lU/lR4NwlfUQ+oPurNDI+O6B0uiFCcWfYuGj3 root@nixos";
  raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkxOS5ycYoTmCsw2/PyxFjPLa5A+qx7iFshCRI9uFBA root@raspberry-pi-4";
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
  "cloudflared-tunnel.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "attic-server-token.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "cachix-authtoken-token.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "ollama-api-key.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "google-api-key.age" = {
    publicKeys = [
      nixos
      droid-android
      raspberry-pi-4
    ];
    armor = true;
  };
  "hermes-env.age" = {
    publicKeys = [
      nixos
      raspberry-pi-4
    ];
    armor = true;
  };
}
