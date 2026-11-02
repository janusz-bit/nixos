# Launchery gier spoza Steama: Heroic (Epic/GOG), Lutris, Prism Launcher
# (Minecraft) i ProtonUp-Qt (wersje Protona/Wine dla launcherów).
_: {
  flake.modules.nixos.gaming-launchers =
    { lib, pkgs, ... }:
    let
      # Środowisko FHS lutrisa ma gtk2 na sztywno w multiPkgs, a gtk2 jest
      # w nixpkgs oznaczone jako broken (temporary-fixes.md, wpis 13).
      # Porównanie po pname, bo == na derivation wymusiłoby outPath i błąd.
      lutrisWithoutGtk2 = pkgs.lutris.override {
        buildFHSEnv =
          args:
          pkgs.buildFHSEnv (
            args
            // {
              multiPkgs = fhsPkgs: lib.filter (pkg: (pkg.pname or "") != "gtk+") (args.multiPkgs fhsPkgs);
            }
          );
      };
    in
    {
      environment.systemPackages = with pkgs; [
        heroic
        protonup-qt
        (prismlauncher.override {
          # ffmpeg wymagany przez niektóre mody
          additionalPrograms = [ ffmpeg ];
          jdks = [
            graalvmPackages.graalvm-ce
            zulu17
            zulu
          ];
        })
        lutrisWithoutGtk2
      ];
    };
}
