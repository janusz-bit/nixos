# Aliasy aktualizacji systemu do nixosConfigurations.<customBot.flakeTarget>:
# update* z GitHuba (--refresh), update-local* z klonu w /etc/nixos oraz
# update-my-pkgs (flake-update). Alias push jest w base-agenix (token cachix).
#
# Host z customBot.cachedBy (laptop: świat x86-64-v3 z nixpkgs-v3) robi
# update* z GitHuba dopiero, gdy repozytorium cachedBy ma tag
# cached/nixos-<rev> dla bieżącego master: bez niego nixos-rebuild
# kompilowałby tysiące pakietów lokalnie. Bramka i rebuild czytają master
# osobno, więc commit wypchnięty pomiędzy nimi ją ominie (build pokaże wtedy
# sam, co kompiluje). update-local* (własny klon) bramki nie ma.
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.<host>.config.environment.shellAliases.update-reboot`.
{ lib, ... }:
{
  flake.modules.nixos.base-rebuild =
    { config, pkgs, ... }:
    let
      inherit (config.customTop.repository) flake path url;
      inherit (config.customBot) flakeTarget cachedBy;
      rebuild =
        mode: flakeRef:
        "nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${flakeTarget}"
        + lib.optionalString (flakeRef == flake) " --refresh";
      sudoRebuild = mode: flakeRef: "sudo ${rebuild mode flakeRef}";

      cachedCheck = pkgs.writeShellApplication {
        name = "nixos-cached-check";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
        ];
        text = ''
          url=${lib.escapeShellArg url}
          repo=https://github.com/${lib.escapeShellArg cachedBy}
          rev=$(git ls-remote "$url" refs/heads/master | cut -f1)
          [ -n "$rev" ] || { echo "cannot resolve master of $url" >&2; exit 1; }
          if git ls-remote --exit-code "$repo" "refs/tags/cached/nixos-$rev" >/dev/null; then
            echo "master $rev is fully cached ($repo)"
          else
            echo "master $rev is not fully cached yet ($repo/actions is building it);" >&2
            echo "update would compile it locally. Wait for tag cached/nixos-$rev." >&2
            exit 1
          fi
        '';
      };
      gate = lib.optionalString (cachedBy != null) "${lib.getExe cachedCheck} && ";
    in
    {
      environment.shellAliases = {
        update = gate + sudoRebuild "switch" flake;
        update-boot = gate + sudoRebuild "boot" flake;
        # Jedno sudo na całość: po długim buildzie osobne `sudo systemctl reboot`
        # pytałoby znowu o hasło (wygasły timestamp) i reboot by nie nastąpił.
        update-reboot = gate + "sudo sh -c '${rebuild "boot" flake} && systemctl reboot'";
        update-local = sudoRebuild "switch" path;
        update-local-boot = sudoRebuild "boot" path;
      };

      programs.fish.shellAliases.update-my-pkgs = "nix run ${path}#flake-update";
    };
}
