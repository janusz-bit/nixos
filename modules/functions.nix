{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      _module.args.custom.function = {
        autostart =
          package:
          pkgs.makeAutostartItem {
            name = "${package.pname}";
            package = package;
          };
      };
    };
}
