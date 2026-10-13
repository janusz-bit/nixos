# Aliasy aktualizacji systemu z tego flake'a; celem jest
# nixosConfigurations.<customBot.flakeTarget> (ustawia rejestr hostów):
#   update / update-boot / update-reboot   z GitHuba (--refresh)
#   update-local / update-local-boot       z kopii w /etc/nixos
#   push            (fish) build toplevela z GitHuba i wypchnięcie do cachix
#   update-my-pkgs  (fish) flake-update: flake.lock i pakiety lokalne
{ customTop, lib, ... }:
{
  flake.modules.nixos.base-rebuild =
    { config, ... }:
    let
      inherit (customTop.repository) linkFlake place;
      inherit (config.customBot) flakeTarget;
      rebuild =
        mode: remote:
        let
          flakeRef = if remote then linkFlake else place;
        in
        "nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${flakeTarget}${lib.optionalString remote " --refresh"}";
      update_alias = mode: remote: "sudo ${rebuild mode remote}";
    in
    {
      environment.shellAliases = {
        update = update_alias "switch" true;
        update-boot = update_alias "boot" true;
        # Jedno sudo na całość: po długim buildzie osobne `sudo systemctl reboot`
        # pytałoby znowu o hasło (wygasły timestamp) i reboot by nie nastąpił.
        update-reboot = "sudo sh -c '${rebuild "boot" true} && systemctl reboot'";
        update-local = update_alias "switch" false;
        update-local-boot = update_alias "boot" false;
      };

      programs.fish.shellAliases = {
        # Tylko w fish: token cachix wstrzykuje funkcja `cachix-push`
        # (base/agenix.nix), niewidoczna dla innych procesów.
        push = "nix build ${linkFlake}#nixosConfigurations.${flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | cachix-push ${customTop.cache.cachix.name}";
        update-my-pkgs = "nix run ${place}#flake-update";
      };
    };
}
