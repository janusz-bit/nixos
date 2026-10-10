# Publiczne klucze SSH — jedno źródło prawdy dla odbiorców agenix
# (secrets.nix), authorized_keys (modules/hosts/raspberry-pi-4/configuration.nix,
# modules/hosts/nixos/remote-agent.nix) i known_hosts.
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
    # ~/.ssh/id_ed25519_laptop użytkownika nixos na RPi (Claude Code) — loguje
    # WYŁĄCZNIE na konto claude-remote laptopa (remote-agent.nix). NIE odbiorca
    # agenix, nigdy w authorized_keys dinosaura ani roota.
    claude-rpi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBm08oKyzMIfuwdh0a6xb4zArEJPL6bOpej5IgY1xs/U claude@raspberry-pi-4";
    # Prywatny w hermes-notify-key.age: na laptopie czyta go dinosaur, na RPi
    # grupa hermes (nixos). Loguje WYŁĄCZNIE na konto hermes RPi z localhost
    # (tunel cloudflared) z wymuszonym poleceniem hermes-notify-receive —
    # pozwala tylko wysłać tekst do DM na Matrixie (hermes-notify.nix).
    # NIE odbiorca agenix.
    hermes-notify = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOsvMowvhSGbJUEW5iGtzbG8+gbWCsW87+3BhPKJXz9E hermes-notify";
  };
  # Klucze hostów sshd (/etc/ssh/ssh_host_ed25519_key.pub) dla known_hosts.
  # Osobno od `hosts`: RPi wpuszcza wszystkie `hosts` jako klucze logowania.
  sshHostKeys = {
    nixos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9RxUTc2ub3uQDGc06/ZBdCRlkOhPJBEPHB5vJihakc";
    raspberry-pi-4 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5Lo9UunQr/9leQHTC776Qsg0g46Zy2Ku3B19WeML5i";
  };
}
