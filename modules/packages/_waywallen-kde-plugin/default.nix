# Plugin tapety Waywallen dla KDE Plasma 6 — oficjalny wariant "embed"
# z release waywallen-display: moduł QML (WaywallenDisplayEmbed/*.so) jest
# wbudowany w kpackage, więc nie wymaga Waywallen.Display w systemie.
#
# Nie waywallen-kde z flake'a nix-waywallen: ich pakiet kopiuje surowe drzewo
# źródłowe, w którym contents/ui/Plugin/qmldir deklaruje QML z Wrapper/ —
# plasmashell rzuca "Type P.PluginDisplay unavailable", a daemon widzi
# 0 pulpitów ("No displays registered").
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waywallen-kde-plugin";
  version = "0.4.6";

  src =
    let
      arch = stdenvNoCC.hostPlatform.parsed.cpu.name;
    in
    fetchurl {
      url = "https://github.com/waywallen/waywallen-display/releases/download/v${finalAttrs.version}/waywallen-kde-${finalAttrs.version}-${arch}.zip";
      hash =
        {
          aarch64 = "sha256-c7YUMjAwto/KHwCv3gjnM6TkUCyfA+NpEP+qpyPSZyA=";
          x86_64 = "sha256-+YZHswHRbAD3Ea3H3L+MptI/I3+tGDXxORYHmtnAMs4=";
        }
        .${arch};
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
