{ self, ... }:
{
  flake.templates = {
    project = {
      path = ./_project.nix;
      description = "Flake init project";
    };
    default = self.templates.project;
  };
}
