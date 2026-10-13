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
