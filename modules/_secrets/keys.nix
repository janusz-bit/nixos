# Publiczne klucze SSH: odbiorcy agenix (secrets.nix) i authorized_keys.
# Samodzielne wyrażenie bez argumentów, bo czytają je też agenix CLI
# i `post-install ssh` (podmienia tekst kluczy w tym pliku).
{
  hosts = {
    # /root/.ssh/id_ed25519 hostów (age.identityPaths)
    nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQRhJASMQB1ClDBwqnYGZXSSGAr1S2y5KaQ5Z0Fc5+ root@nixos";
    raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkxOS5ycYoTmCsw2/PyxFjPLa5A+qx7iFshCRI9uFBA root@raspberry-pi-4";
  };
  # Tylko logowanie SSH — żaden z tych kluczy NIE jest odbiorcą agenix.
  users = {
    # ~/.ssh/id_ed25519 głównego użytkownika laptopa
    janusz-bit = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICdlN9e5I4IQy6Re4Z4+BFopT6ypB3nNXzdj4XeTDewO janusz-bit@proton.me";
    # Telefon (Linux Terminal na Androidzie): SSH na RPi i, tylko z tailnetu,
    # na laptopa (hosts/nixos/ssh.nix).
    phone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4dg51Pg4rlE4CaiHaHUovkCIgAuJuEqkDsEMAU8ut4 root@debian";
  };
}
