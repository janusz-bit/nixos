# Aliasy aktualizacji systemu do nixosConfigurations.<customBot.flakeTarget>:
# update* z GitHuba (--refresh), update-local* z klonu w /etc/nixos oraz
# update-my-pkgs (flake-update). Alias push jest w base-agenix (token cachix).
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.<host>.config.environment.shellAliases.update-reboot`.
{ customTop, lib, ... }:
{
  flake.modules.nixos.base-rebuild =
    { config, ... }:
    let
      inherit (customTop.repository) flake place;
      inherit (config.customBot) flakeTarget;
      rebuild =
        mode: remote:
        let
          flakeRef = if remote then flake else place;
        in
        "nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${flakeTarget}${lib.optionalString remote " --refresh"}";
      sudoRebuild = mode: remote: "sudo ${rebuild mode remote}";
    in
    {
      environment.shellAliases = {
        update = sudoRebuild "switch" true;
        update-boot = sudoRebuild "boot" true;
        # Jedno sudo na całość: po długim buildzie osobne `sudo systemctl reboot`
        # pytałoby znowu o hasło (wygasły timestamp) i reboot by nie nastąpił.
        update-reboot = "sudo sh -c '${rebuild "boot" true} && systemctl reboot'";
        update-local = sudoRebuild "switch" false;
        update-local-boot = sudoRebuild "boot" false;
      };

      programs.fish.shellAliases.update-my-pkgs = "nix run ${place}#flake-update";
    };
}
