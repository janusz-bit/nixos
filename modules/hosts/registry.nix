# Rejestr hostów: jedno miejsce, z którego powstają nixosConfigurations.<nazwa>,
# workflowy CI (github-actions.nix: build każdego hosta i lista ewaluacji)
# i strona docs/hosts.md. Nazwa hosta = nazwa konfiguracji = cel aliasów
# update/push (customBot.flakeTarget ustawia rejestr, nie host).
#
# Host deklaruje się w modules/hosts/<nazwa>/default.nix:
#   hosts.<nazwa> = { system = "x86_64-linux"; modules = [ … ]; };
# Procedura nowego hosta (sprzęt, dysk, klucze, sekrety): README.md.
#
# Pułapki ewaluacji:
# - `modules` to lista surowych wartości (types.raw), nie deferredModule.
#   deferredModule opakowuje każdą definicję w dodatkowe poziomy importów,
#   a system modułów scala listy (systemPackages, overlays, reguły udev)
#   według głębokości importu — zmieniłaby się kolejność, a z nią toplevel.
# - Nazwy atrybutów (hosty, workflowy) zależą wyłącznie od danych rejestru,
#   nigdy od ewaluacji konfiguracji NixOS: `nix flake show` i generowanie CI
#   nie ewaluują hostów.
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
          customBot.flakeTarget = name;
        }
      ];
    }
  ) config.hosts;
}
