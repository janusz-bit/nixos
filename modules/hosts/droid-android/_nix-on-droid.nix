{ pkgs, ... }:
{
  environment.packages = with pkgs; [
    git
    micro
    ollama
  ];

  environment.etcBackupExtension = ".bak";

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Nix-on-Droid's state version is independent of the old AVF NixOS guest.
  system.stateVersion = "24.05";
}
