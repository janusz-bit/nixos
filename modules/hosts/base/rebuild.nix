# Aliasy aktualizacji systemu do nixosConfigurations.<customBot.flakeTarget>:
# update* z GitHuba (--refresh), update-local* z klonu w /etc/nixos oraz
# update-my-pkgs (flake-update). Alias push jest w base-agenix (token cachix).
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.<host>.config.environment.shellAliases.update-reboot`.
{ lib, ... }:
{
  flake.modules.nixos.base-rebuild =
    { config, ... }:
    let
      inherit (config.customTop.repository) flake path;
      inherit (config.customBot) flakeTarget;
      rebuild =
        mode: flakeRef:
        let
          refresh = lib.optionalString (flakeRef == flake) " --refresh";
        in
        "nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${flakeTarget}${refresh}";
      sudoRebuild = mode: flakeRef: "sudo ${rebuild mode flakeRef}";
    in
    {
      environment.shellAliases = {
        update = sudoRebuild "switch" flake;
        update-boot = sudoRebuild "boot" flake;
        # Jedno sudo na całość: po długim buildzie osobne `sudo systemctl reboot`
        # pytałoby znowu o hasło (wygasły timestamp) i reboot by nie nastąpił.
        update-reboot = "sudo sh -c '${rebuild "boot" flake} && systemctl reboot'";
        update-local = sudoRebuild "switch" path;
        update-local-boot = sudoRebuild "boot" path;
      };

      programs.fish.shellAliases.update-my-pkgs = "nix run ${path}#flake-update";
    };
}
