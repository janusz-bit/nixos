# Publiczne klucze SSH: odbiorcy agenix (secrets.nix), authorized_keys
# i known_hosts. Samodzielne wyrażenie bez argumentów, bo czytają je też
# agenix CLI i `post-install ssh` (podmienia tekst kluczy w tym pliku).
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
    # Telefon (Linux Terminal na Androidzie): tylko SSH na RPi.
    phone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4dg51Pg4rlE4CaiHaHUovkCIgAuJuEqkDsEMAU8ut4 root@debian";
    # Claude Code na RPi (~/.ssh/id_ed25519_laptop): loguje WYŁĄCZNIE na konto
    # claude-remote laptopa (remote-agent.nix), nigdy w authorized_keys
    # głównego użytkownika ani roota.
    claude-rpi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBm08oKyzMIfuwdh0a6xb4zArEJPL6bOpej5IgY1xs/U claude@raspberry-pi-4";
    # Loguje WYŁĄCZNIE na konto hermes RPi z localhost, z wymuszonym poleceniem
    # hermes-notify-receive (claude-notify.nix); prywatny w hermes-notify-key.age.
    hermes-notify = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOsvMowvhSGbJUEW5iGtzbG8+gbWCsW87+3BhPKJXz9E hermes-notify";
  };
  # Klucze hostów sshd (/etc/ssh/ssh_host_ed25519_key.pub) dla known_hosts.
  sshHostKeys = {
    nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9RxUTc2ub3uQDGc06/ZBdCRlkOhPJBEPHB5vJihakc";
    raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5Lo9UunQr/9leQHTC776Qsg0g46Zy2Ku3B19WeML5i";
  };
}
