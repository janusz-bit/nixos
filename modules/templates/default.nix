# Szablon flake'a `project` (też `default`, `nix flake init -t /etc/nixos`):
# flake-parts + import-tree z katalogu nix/, formatter nixfmt, hook pre-commit
# nixfmt i dev shell.
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
