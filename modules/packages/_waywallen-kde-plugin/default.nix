# Plugin tapety Waywallen dla KDE Plasma 6 — oficjalny wariant "embed"
# z release waywallen-display.
#
# "-embed" = moduł QML (WaywallenDisplayEmbed/*.so) skompilowany i
# wbudowany w kpackage, więc jest samowystarczalny: nie wymaga
# Waywallen.Display instalowanego systemowo.
#
# Dlaczego nie waywallen-kde z flake'a nix-waywallen: ich pakiet kopiuje
# surowe drzewo źródłowe, w którym contents/ui/Plugin/qmldir deklaruje
# QML, których tam nie ma (siedzą w Wrapper/) — plasmashell rzuca
# "Type P.PluginDisplay unavailable", a daemon widzi 0 pulpitów
# ("No displays registered").
#
# Jak w _helium: podpisane hashem binarki z oficjalnego releasu
# (fetchurl), nie budują się ze źródeł. Fix reconnect backoffu
# ("plasma empty displays on login") jest dopiero od v0.3.3.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waywallen-kde-plugin";
  version = "0.3.3";

  src =
    let
      zipArch =
        {
          aarch64-linux = "aarch64";
          x86_64-linux = "x86_64";
        }
        .${stdenvNoCC.hostPlatform.system}
          or (throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}");
    in
    fetchurl {
      url = "https://github.com/waywallen/waywallen-display/releases/download/v${finalAttrs.version}/waywallen-kde-${finalAttrs.version}-${zipArch}-embed.zip";
      hash =
        {
          aarch64 = "sha256-nccbfL/bByW/zvks0fZBQEkYdCZ8ZBP/YUwPM40iXPw=";
          x86_64 = "sha256-0SGuTy/KLSZkts1qb1x3GticUwOI3CQVWyRNhzOuBZ4=";
        }
        .${zipArch};
    };

  dontConfigure = true;
  dontBuild = true;
  # binarki z releasu mają zostać dokładnie takie, jak wydał je upstream
  dontFixup = true;

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    runHook preInstall
    # setup.sh sam wchodzi do jedynego katalogu zipa (source root:
    # org.waywallen.kde) — kopiujemy jego zawartość
    mkdir -p $out/share/plasma/wallpapers/org.waywallen.kde
    cp -r . $out/share/plasma/wallpapers/org.waywallen.kde/
    runHook postInstall
  '';

  meta = {
    description = "Waywallen KDE Plasma 6 wallpaper plugin (official embed package)";
    homepage = "https://github.com/waywallen/waywallen-display";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
