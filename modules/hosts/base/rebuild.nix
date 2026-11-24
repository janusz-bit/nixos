# Aliasy aktualizacji systemu do nixosConfigurations.<customBot.flakeTarget>:
# update* z GitHuba (--refresh), update-local* z klonu w /etc/nixos oraz
# update-my-pkgs (flake-update). Alias push jest w base-agenix (token cachix).
#
# Host z customBot.cachedBy (laptop: świat x86-64-v3 z nixpkgs-v3) robi
# update* z GitHuba dopiero, gdy repozytorium cachedBy ma tag
# cached/nixos-<rev> dla bieżącego master (cały świat w cache'u RPi,
# hosts/nix-cache.nix), gdy ten cache odpowiada i gdy bieżący nix.conf już go
# używa i ufa kluczowi nixpkgs-v3 (customTop.nixCache.v3PublicKey; build
# czyta stary nix.conf, nie ten z nowej konfiguracji): bez któregokolwiek
# nixos-rebuild kompilowałby tysiące pakietów lokalnie. Bramka i rebuild
# czytają master osobno, więc commit wypchnięty pomiędzy nimi ją ominie
# (build pokaże wtedy sam, co kompiluje). update-local* (własny klon) bramki
# nie ma.
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.<host>.config.environment.shellAliases.update-reboot`.
{ lib, ... }:
{
  flake.modules.nixos.base-rebuild =
    { config, pkgs, ... }:
    let
      inherit (config.customTop.repository) flake path url;
      inherit (config.customTop) nixCache;
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
          pkgs.curl
          config.nix.package
        ];
        text = ''
          url=${lib.escapeShellArg url}
          repo=https://github.com/${lib.escapeShellArg cachedBy}
          rev=$(git ls-remote "$url" refs/heads/master | cut -f1)
          [ -n "$rev" ] || { echo "cannot resolve master of $url" >&2; exit 1; }
          cache=${lib.escapeShellArg nixCache.url}
          if ! git ls-remote --exit-code "$repo" "refs/tags/cached/nixos-$rev" >/dev/null; then
            echo "master $rev is not fully cached yet ($repo/actions is building it);" >&2
            echo "update would compile it locally. Wait for tag cached/nixos-$rev." >&2
            exit 1
          fi
          if ! curl -sf --connect-timeout 5 --max-time 15 -o /dev/null "$cache/nix-cache-info"; then
            echo "the tailnet cache $cache does not answer; update would compile the x86-64-v3 world locally." >&2
            exit 1
          fi
          key=${lib.escapeShellArg nixCache.v3PublicKey}
          target=${lib.escapeShellArg "${flake}#${flakeTarget}"}
          substituters=" $(nix config show substituters) "
          keys=" $(nix config show trusted-public-keys) "
          if [[ $substituters != *" $cache "* || $keys != *" $key "* ]]; then
            echo "this nix.conf does not take $cache signed by $key yet; update would compile the x86-64-v3 world locally." >&2
            echo "Once: sudo nixos-rebuild switch --flake $target --refresh --option extra-substituters $cache --option extra-trusted-public-keys $key" >&2
            exit 1
          fi
          echo "master $rev is fully cached in $cache ($repo)"
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
