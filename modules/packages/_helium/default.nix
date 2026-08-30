# Helium Browser — pakiet z oficjalnych binariów (.deb), wzorowany na
# pkgs/by-name/go/google-chrome/package.nix z nixpkgs.
#
# To szybki i pewny sposób: używa podpisanych buildów Helium z ich
# releases na GitHubie. Sandbox Chromium działa tu w trybie user
# namespaces (deb nie zawiera chrome-sandbox), więc nie trzeba suid.
{
  lib,
  stdenvNoCC,
  fetchurl,
  bintools,
  makeWrapper,
  patchelf,
  testers,

  # biblioteki linkowane dynamicznie (analogicznie do google-chrome)
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gcc-unwrapped,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  libdrm,
  libglvnd,
  libkrb5,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxshmfence,
  libxtst,
  libgbm,
  nspr,
  nss,
  pango,
  pipewire,
  vulkan-loader,
  wayland,
  libudev-zero ? null, # zamiast systemd-udevd
  systemd,

  # runtime
  libexif,
  pciutils,

  # dodatkowe
  curl,
  liberation_ttf,
  util-linux,
  wget,
  xdg-utils,
  flac,
  harfbuzz,
  icu,
  libopus,
  snappy,
  speechd-minimal,
  bzip2,
  libcap,

  libpulseaudio,
  pulseSupport ? true,

  adwaita-icon-theme,
  gsettings-desktop-schemas,

  libva,
  libvaSupport ? true,

  addDriverRunpath,

  # dodatkowe argumenty CLI wbudowane w wrapper
  commandLineArgs ? "",
}:

let
  pname = "helium";
  version = "0.16.2.1";

  # Helium wymaga libopus zlibowanego z custom modes (jak upstream w helium-linux)
  opusWithCustomModes' = libopus.override { withCustomModes = true; };

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    bzip2
    cairo
    curl
    cups
    dbus
    expat
    flac
    fontconfig
    freetype
    gcc-unwrapped.lib
    gdk-pixbuf
    glib
    harfbuzz
    icu
    libcap
    libdrm
    libexif
    libglvnd
    libkrb5
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    libgbm
    nspr
    nss
    opusWithCustomModes'
    pango
    pciutils
    pipewire
    snappy
    speechd-minimal
    systemd
    util-linux
    vulkan-loader
    wayland
    wget
  ]
  ++ lib.optional pulseSupport libpulseaudio
  ++ lib.optional libvaSupport libva
  ++ [
    gtk3
    gtk4
  ];

in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname version;

  src =
    let
      debArch =
        {
          aarch64-linux = "arm64";
          x86_64-linux = "amd64";
        }
        .${stdenvNoCC.hostPlatform.system}
          or (throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}");
    in
    fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-bin_${version}-1_${debArch}.deb";
      hash =
        {
          amd64 = "sha256-/mTzkjCOGmmIq0YIp0WhVCeGEA7WggKCad4SDmd8Q6Q=";
          arm64 = "sha256-k52TZo6xJ0OpwCGLXPw3D39ZysKHBFzCeEmdy1P6m+4=";
        }
        .${debArch};
    };

  strictDeps = false;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  buildInputs = [
    adwaita-icon-theme
    glib
    gtk3
    gtk4
    gsettings-desktop-schemas
  ];

  unpackPhase = ''
    runHook preUnpack
    ${lib.getExe' bintools "ar"} x $src
    tar xf data.tar.xz
    runHook postUnpack
  '';

  rpath = lib.makeLibraryPath deps;
  binpath = lib.makeBinPath [ xdg-utils ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share
    cp -v -a opt/* $out/share/
    cp -v -a usr/share/* $out/share/
    rm -rf $out/share/metainfo/net.imput.helium.metainfo.xml  # placeholder, re-added below

    exe=$out/bin/helium
    appdir=$out/share/helium

    # zamień dołączony libvulkan na nasz
    rm -v $appdir/libvulkan.so.1
    ln -v -s -t "$appdir" "${lib.getLib vulkan-loader}/lib/libvulkan.so.1"

    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail "Exec=helium" "Exec=$exe" 

    # skrypt-wraapper z deba eksportuje CHROME_WRAPPER i LD_LIBRARY_PATH
    # względem własnej lokalizacji — zostaw go w appdir i opakuj w makeWrapper
    substituteInPlace $appdir/helium-wrapper \
      --replace-fail 'export CHROME_VERSION_EXTRA=deb' 'export CHROME_VERSION_EXTRA=nix'

    makeWrapper "$appdir/helium-wrapper" "$exe" \
      --prefix LD_LIBRARY_PATH : "$rpath" \
      --prefix PATH            : "$binpath" \
      --suffix PATH            : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix XDG_DATA_DIRS   : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH:${addDriverRunpath.driverLink}/share" \
      --chdir "$appdir" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}

    # popraw interpreter i rpath w binarkach ELF
    for elf in $appdir/helium $appdir/chromedriver $appdir/helium_crashpad_handler; do
      patchelf --set-rpath $rpath $elf || true
      patchelf --set-interpreter ${bintools.dynamicLinker} $elf || true
    done

    runHook postInstall
  '';

  passthru = {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      command = "helium --version";
    };
  };

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    longDescription = ''
      Helium is a fork of ungoogled-chromium with additional
      privacy-oriented patches, prebuilt as a Debian package by upstream.
    '';
    homepage = "https://helium.computer/";
    # Helium dystrybuuje swoje buildy na GPL-3.0
    license = lib.licenses.gpl3Plus;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "helium";
    maintainers = [ ];
  };
})
