# devenv (https://devenv.sh): deklaratywne środowiska deweloperskie projektów.
#
# devenv rejestruje swoje cache (`cachix.pull`) per projekt, ale demon nix
# przyjmuje substituters od klienta tylko od trusted-users, a tu
# `trusted-users` celowo zostaje domyślne (tylko root, AGENTS.md: Security
# invariants). Bez cache w konfiguracji demona devenv po cichu buduje lokalnie
# wszystko z `devenv-nixpkgs/rolling`, dlatego devenv.cachix.org jest dodane
# tutaj, na poziomie hosta. To cache dla projektów devenv, nie dla tego
# flake'a: celowo nie ma go w `customTop.cache` ani w `nixConfig` w flake.nix.
#
# direnv jest włączony w base (`programs.direnv`), więc `devenv init` + `.envrc`
# z `use devenv` działa bez dodatkowej konfiguracji.
#
# Weryfikacja: `nix config show extra-substituters` zawiera devenv.cachix.org;
# `devenv shell` w nowym projekcie pobiera zależności zamiast je budować.
_: {
  flake.modules.nixos.nixos-devenv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.devenv ];

      nix.settings = {
        extra-substituters = [ "https://devenv.cachix.org" ];
        extra-trusted-public-keys = [
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };
    };
}
