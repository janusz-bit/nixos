let
  nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQRhJASMQB1ClDBwqnYGZXSSGAr1S2y5KaQ5Z0Fc5+ root@nixos";
  droid-android = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4dg51Pg4rlE4CaiHaHUovkCIgAuJuEqkDsEMAU8ut4 root@debian";
  raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkxOS5ycYoTmCsw2/PyxFjPLa5A+qx7iFshCRI9uFBA root@raspberry-pi-4";

  # All hosts share these secrets
  allHosts = [
    nixos
    droid-android
    raspberry-pi-4
  ];
  # Server-only hosts (nixos + raspberry-pi-4)
  serverHosts = [
    nixos
    raspberry-pi-4
  ];

  mkSecret = publicKeys: {
    inherit publicKeys;
    armor = true;
  };
in
{
  "secret1.age" = mkSecret allHosts;
  "notes.age" = mkSecret allHosts;
  "nextcloud-adminpass.age" = mkSecret allHosts;
  "GITHUB_TOKEN.age" = mkSecret allHosts;
  "cloudflared-tunnel.age" = mkSecret allHosts;
  "attic-server-token.age" = mkSecret allHosts;
  "cachix-authtoken-token.age" = mkSecret allHosts;
  "ollama-api-key.age" = mkSecret allHosts;
  "google-api-key.age" = mkSecret allHosts;
  "hermes-env.age" = mkSecret serverHosts;
  "hermes-api-key.age" = mkSecret serverHosts;
  "hermes-webui-env.age" = mkSecret serverHosts;
  "librechat-env.age" = mkSecret serverHosts;
}
