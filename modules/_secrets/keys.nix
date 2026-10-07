# Publiczne klucze SSH — jedno źródło prawdy dla odbiorców agenix
# (agenix-rules.nix) i authorized_keys (modules/hosts/raspberry-pi-4/configuration.nix).
{
  hosts = {
    # /root/.ssh/id_ed25519 hostów (age.identityPaths)
    nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQRhJASMQB1ClDBwqnYGZXSSGAr1S2y5KaQ5Z0Fc5+ root@nixos";
    raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkxOS5ycYoTmCsw2/PyxFjPLa5A+qx7iFshCRI9uFBA root@raspberry-pi-4";
  };
  users = {
    # ~/.ssh/id_ed25519 użytkownika dinosaur na laptopie
    janusz-bit = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICdlN9e5I4IQy6Re4Z4+BFopT6ypB3nNXzdj4XeTDewO janusz-bit@proton.me";
    # Telefon: Linux Terminal na Androidzie (AVF, Debian) — tylko SSH na RPi,
    # NIE odbiorca agenix.
    phone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4dg51Pg4rlE4CaiHaHUovkCIgAuJuEqkDsEMAU8ut4 root@debian";
  };
}
