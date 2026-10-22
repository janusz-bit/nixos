# Launchery gier spoza Steama: Heroic (Epic/GOG), Lutris, Prism Launcher
# (Minecraft) i ProtonUp-Qt (wersje Protona/Wine dla launcherów).
_: {
  flake.modules.nixos.gaming-launchers =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        heroic
        protonup-qt
        (prismlauncher.override {
          # ffmpeg wymagany przez niektóre mody
          additionalPrograms = [ ffmpeg ];
          jdks = [
            graalvmPackages.graalvm-ce
            zulu8
            zulu17
            zulu
          ];
        })
        lutris
      ];
    };
}
