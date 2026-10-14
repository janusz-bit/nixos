# Szablon flake'a `project` (też `default`, `nix flake init -t /etc/nixos`):
# flake-parts + import-tree z katalogu nix/, formatter nixfmt, hook pre-commit
# nixfmt i dev shell.
#
# Prefiks `_` w _project chroni pliki szablonu przed import-tree tego repo,
# które wczytałoby je jako własne moduły.
{ self, ... }:
{
  flake.templates = {
    project = {
      path = ./_project;
      description = "Flake init project";
    };
    default = self.templates.project;
  };
}
