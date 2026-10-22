# Rejestr hostów: z niego powstają nixosConfigurations.<nazwa>, workflowy CI
# (github-actions.nix) i strony docs/reference/ (docs.nix). Host deklaruje
# się w modules/hosts/<nazwa>/default.nix; procedura nowego hosta: README.md.
#
# Rejestr ustawia: nazwa hosta = nazwa konfiguracji = networking.hostName =
# customBot.flakeTarget (cel aliasów update/push); polegają na tym
# post-install (wpisy keys.nix) i nixos-rebuild bez `#<host>`. Obraz SD
# (sd-image.nix), składany poza rejestrem, ustawia te same wartości sam; inna
# wartość niż nazwa w rejestrze to błąd ewaluacji.
#
# Pułapki ewaluacji:
# - `modules` to types.raw, nie deferredModule: ten opakowuje każdą definicję
#   w dodatkowe poziomy importów, a system modułów scala listy (systemPackages,
#   overlays, reguły udev) według głębokości importu — zmieniłaby się
#   kolejność, a z nią toplevel.
# - Nazwy atrybutów (hosty, workflowy) zależą tylko od danych rejestru, nie od
#   ewaluacji NixOS: `nix flake show` i generowanie CI nie ewaluują hostów.
# - self.modules.nixos.* wolno używać w `modules` (leniwie, dopiero w
#   nixosSystem), ale nie w `imports` modułu flake-parts — tam to
#   nieskończona rekurencja.
#
# Sprawdzenie: nix eval .#nixosConfigurations --apply builtins.attrNames
{
  config,
  inputs,
  lib,
  ...
}:
{
  options.hosts = lib.mkOption {
    description = "Hosty NixOS tego flake'a (nazwa = nixosConfigurations.<nazwa>).";
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          system = lib.mkOption {
            type = lib.types.enum config.systems;
            description = "Platforma hosta: nixpkgs.hostPlatform i runner CI.";
          };
          modules = lib.mkOption {
            type = lib.types.listOf lib.types.raw;
            description = "Moduły NixOS hosta w kolejności importu.";
          };
          buildOnTags = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Czy CI buduje toplevel hosta także przy tagach v* (false dla wielogodzinnych buildów).";
          };
        };
      }
    );
  };

  config.flake.nixosConfigurations = lib.mapAttrs (
    name: host:
    inputs.nixpkgs.lib.nixosSystem {
      modules = host.modules ++ [
        {
          nixpkgs.hostPlatform = host.system;
          networking.hostName = name;
          customBot.flakeTarget = name;
        }
      ];
    }
  ) config.hosts;
}
