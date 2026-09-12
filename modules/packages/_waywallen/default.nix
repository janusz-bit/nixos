# Waywallen — dynamiczne tapety na Waylandzie (zamiennik Wallpaper Engine
# Plugin). Pakiet z oficjalnych binariów: AppImage z release'u waywallen
# (daemon Rust + Qt/QML UI + renderery image/video + plugin wallhaven +
# layer-shell) oraz prebuild pluginu open-wallpaper-engine (tapety .pkg/web
# Wallpaper Engine), wstrzykniętego do katalogu pluginów daemona — dokładnie
# tak jak robi to flatpak upstreamu.
#
# Dlaczego nie build ze źródeł (jak w wywalonym flake'u nix-waywallen):
# build wymaga llvmPackages_latest z clang-scan-deps (moduły C++20),
# Corrosion + rustc w CMake iFetchContent i ~10 fetchowanych sub-depów
# z deps.json. AppImage jest samowystarczalny (daemon potrzebuje tylko
# glibc), a weweb (CEF) z release-zipu dostaje dokładnie ten sam fixup,
# co przy buildzie ze źródeł: podmiana libvulkan/swiftshader + rpath na
# libcef.so. Brakujące biblioteki systemowe dostarcza wrapper przez
# LD_LIBRARY_PATH (odpowiednik env z AppRun).
#
# Uwaga do wersji: `version` = waywallen (bumpuje nix-update w
# flake-update), `oweVersion` = open-wallpaper-engine — bump RĘCZNY
# (upstream wypuszcza osobne release'y; hashe dopisane w attrsetach,
# `nix hash file <plik> --sri`). Plugin KDE Plasma jest osobno w
# modules/packages/_waywallen-kde-plugin (waywallen-display, osobne
# wersjonowanie).
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  patchelf,
  bintools, # readelf — offset payloadu squashfs w AppImage
  squashfsTools, # unsquashfs
  unzip,

  # biblioteki, których binarki szukają w systemie (DT_NEEDED bez rpath /
  # dlopen): AppRun AppImage eksportował LD_LIBRARY_PATH z usr/lib, wrapper
  # odtwarza to zachowanie i dokłada biblioteki z nixpkgs
  cairo, # libcairo.so.2 — weweb-renderer ma je w DT_NEEDED
  libglvnd, # libGL/libEGL (UI, renderery, CEF)
  vulkan-loader, # podmienia bundlowany libvulkan.so.1
  mesa, # dla rpath libcef.so (dlopen GL/EGL/wayland w CEF)
  libxkbcommon,
  wayland,
  libgbm,
  libdrm,
  fontconfig,
  freetype,
  harfbuzz,
  lz4,
  libva,
  alsa-lib, # libasound (weweb)
  dbus,
  cups,
  expat,
  glib,
  gtk3, # dlopen CEF
  pango,
  at-spi2-atk,
  at-spi2-core, # atk/atspi (weweb)
  nspr,
  nss,
  systemd, # libudev (weweb)
  libpulseaudio,
  pipewire, # dlopen daemon (audio)
  gcc-unwrapped, # libstdc++ jako fallback za bundlowanym
  addDriverRunpath, # sterowniki GPU (/run/opengl-driver)

  # biblioteki X11 (weweb/CEF)
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
}:

let
  pname = "waywallen";
  version = "0.3.9";
  oweVersion = "0.2.9";

  arch =
    {
      aarch64-linux = "aarch64";
      x86_64-linux = "x86_64";
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}");

  owe = fetchurl {
    url = "https://github.com/waywallen/open-wallpaper-engine/releases/download/v${oweVersion}/org.waywallen.open-wallpaper-engine-${oweVersion}-linux-${arch}.zip";
    hash =
      {
        aarch64 = "sha256-wW81CmUsM8W3NPPiHm71XzETlPxQ7+gpzTLwHFSviCc=";
        x86_64 = "sha256-MM/uWgQzIOD7GUtEfMegfexd+KsjgSHy82LI97aCAng=";
      }
      .${arch};
  };

  # biblioteki runtime + sterowniki GPU (libGL/EGL z /run/opengl-driver)
  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gcc-unwrapped.lib
    glib
    gtk3
    harfbuzz
    libdrm
    libgbm
    libglvnd
    libpulseaudio
    libva
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    lz4
    mesa
    nspr
    nss
    pango
    pipewire
    systemd
    vulkan-loader
    wayland
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname version;

  oweSrc = owe;

  src = fetchurl {
    url = "https://github.com/waywallen/waywallen/releases/download/v${finalAttrs.version}/waywallen-${finalAttrs.version}-${arch}.AppImage";
    hash =
      {
        aarch64 = "sha256-0e3f7t3Qwq6cg20c75bmdbVULLaheWAugP/M4vQWFPA=";
        x86_64 = "sha256-499tPXymKD0Owftj/Asgu08ZmHBMuFKPHdsR+ribmt8=";
      }
      .${arch};
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # binarki z releasu mają zostać dokładnie takie, jak wydał je upstream
  dontFixup = true;
  dontStrip = true;

  nativeBuildInputs = [
    bintools
    makeWrapper
    patchelf
    squashfsTools
    unzip
  ];

  installPhase = ''
    runHook preInstall
    # $out nie istnieje na wejściu — bez mkdir cp -a skopiuje usr AS $out
    mkdir -p $out

    # Rozpakuj AppImage: payload to squashfs doklejony do runtime'u ELF.
    # --appimage-extract nie działa w tym runtime'cie, więc offset liczymy
    # tak samo jak appimage-exec.sh (e_shoff + e_shentsize * e_shnum).
    offset=$(readelf -h $src | awk 'NR==13{e_shoff=$5} NR==18{e_shentsize=$5} NR==19{e_shnum=$5} END{print e_shoff+e_shentsize*e_shnum}')
    unsquashfs -q -d appdir -o "$offset" $src

    # Zachowujemy layout usr/ (AppRun: LD_LIBRARY_PATH=usr/lib,
    # qt.conf w usr/bin rozwiązuje pluginy/QML względnie do binarki),
    # bo daemon szuka zasobów względem ścieżki binarki.
    cp -a appdir/usr $out/
    chmod -R u+w $out

    # open-wallpaper-engine jako plugin daemona — dokładnie jak w flatpaku
    # upstreamu (kpackage z plugin.toml, id = org.waywallen.open-wallpaper-engine)
    owePlugin=$out/usr/share/waywallen/plugins/org.waywallen.open-wallpaper-engine
    mkdir -p $owePlugin
    unzip -q $oweSrc -d $owePlugin

    # CEF (weweb): wyrzuć bundlowane libvulkan.so.1 i SwiftShader —
    # niepatchowane binarki z hardcoded ścieżkami, nie działają na NixOS.
    # Podmień libvulkan na systemowy loader (zna ścieżki ICD).
    weweb=$owePlugin/lib/weweb
    rm -f $weweb/libvulkan.so.1 $weweb/libvk_swiftshader.so $weweb/vk_swiftshader_icd.json
    ln -s ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $weweb/libvulkan.so.1

    # libcef.so to niepatchowana binarka bez rpath — dlopenuje GL/EGL/Wayland
    # w runtime. UWAGA: nie podmieniaj bundlowanego libEGL.so/libGLESv2.so —
    # to własna implementacja EGL/GLES (ANGLE) CEF; systemowy libglvnd nie
    # obsługuje ANGLE-owych atrybutów kontekstu na NVIDIA (EGL_BAD_ATTRIBUTE).
    patchelf --add-rpath "${
      lib.makeLibraryPath [
        mesa
        vulkan-loader
        wayland
        libglvnd
      ]
    }" $weweb/libcef.so

    # desktop + ikony do standardowych ścieżek
    mkdir -p $out/share
    cp -a $out/usr/share/applications $out/usr/share/icons $out/usr/share/metainfo $out/share/
    substituteInPlace $out/share/applications/org.waywallen.waywallen.desktop \
      --replace-fail "Exec=waywallen" "Exec=$out/bin/waywallen"

    # wrapper odtwarza env z AppRun + biblioteki, których nie ma w bundlu
    makeWrapper $out/usr/bin/waywallen $out/bin/waywallen \
      --prefix LD_LIBRARY_PATH : "$out/usr/lib" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath (deps ++ [ "${addDriverRunpath.driverLink}/lib" ])
      }" \
      --prefix QT_PLUGIN_PATH : "$out/usr/plugins" \
      --prefix QML2_IMPORT_PATH : "$out/usr/qml" \
      --prefix QML_IMPORT_PATH : "$out/usr/qml"

    runHook postInstall
  '';

  meta = {
    description = "Wayland wallpaper app: daemon, Qt/QML UI, renderer plugins and Wallpaper Engine support";
    longDescription = ''
      Waywallen — dynamiczne tapety na Waylandzie (zamiennik Wallpaper Engine
      Plugin). Zbudowany z oficjalnego AppImage (daemon + UI + pluginy
      image/video/wallhaven + layer-shell) oraz release-zipu pluginu
      open-wallpaper-engine (tapety .pkg/web z Wallpaper Engine).
      Tapety na Plasma 6: modules/packages/_waywallen-kde-plugin.
    '';
    homepage = "https://github.com/waywallen/waywallen";
    license = with lib.licenses; [
      mit # waywallen (AppImage)
      gpl2Only # open-wallpaper-engine
    ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    mainProgram = "waywallen";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
