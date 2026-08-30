# Helium Browser — pakiet z oficjalnych binariów (.deb), wzorowany na
# pkgs/by-name/go/google-chrome/package.nix z nixpkgs.
#
# Używa podpisanych buildów Helium z ich releases na GitHubie. Sandbox
# Chromium działa tu w trybie user namespaces (deb nie zawiera
# chrome-sandbox), więc nie trzeba suid.
#
# Lista `deps` jest obcięta względem google-chrome do tego, czego binary
# *faktycznie* używa (patchelf --print-needed na helium*/binarkach +
# znane dlopen-y Chromium): ICU, harfbuzz, snappy, flac, opus, bzip2,
# krb5 itd. są skompilowane statycznie w binarce.
{
  lib,
  stdenvNoCC,
  fetchurl,
  bintools,
  makeWrapper,
  patchelf,
  testers,

  # biblioteki, które binary linkują dynamicznie (DT_NEEDED)
  alsa-lib,
  at-spi2-atk, # libatk-bridge-2.0
  at-spi2-core, # libatk-1.0, libatspi
  cairo,
  cups,
  dbus,
  expat,
  fontconfig, # dlopen — enumeracja czcionek systemowych
  gcc-unwrapped, # libgcc_s, libstdc++
  glib,
  gtk3,
  gtk4, # dlopen — dialogi (GTK3/4, wybiera Chromium w runtime)
  libglvnd, # dlopen — libGL/libEGL
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
  libxscrnsaver, # dlopen — wykrywanie bezczynności
  libxtst, # dlopen — automatyzacja inputu
  libgbm, # mesa
  nspr,
  nss,
  pango,
  pciutils, # dlopen — detekcja GPU
  pipewire, # dlopen — udostępnianie ekranu/webcam
  speechd-minimal, # dlopen — synteza mowy
  systemd, # libudev
  vulkan-loader, # zastępuje bundlowany libvulkan.so.1
  wayland, # dlopen — ozone wayland

  # opcjonalne backendy
  libpulseaudio,
  pulseSupport ? true,
  libva,
  libvaSupport ? true,

  # runtime env (ikony/schematy GSettings dla wrappera)
  adwaita-icon-theme,
  gsettings-desktop-schemas,

  addDriverRunpath, # sterownik GPU (/run/opengl-driver) do rpath
  xdg-utils,
  # dodatkowe argumenty CLI wbudowane w wrapper
  commandLineArgs ? "",
}:

let
  pname = "helium";
  version = "0.16.2.1";

  # biblioteki runtime + sterownik GPU (libGL/EGL z /run/opengl-driver)
  rpath = lib.makeLibraryPath (deps ++ [ "${addDriverRunpath.driverLink}/lib" ]);
  binpath = lib.makeBinPath [ xdg-utils ];

  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    gcc-unwrapped.lib
    glib
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
    libxscrnsaver
    libxtst
    libgbm
    libglvnd
    nspr
    nss
    pango
    pciutils
    pipewire
    speechd-minimal
    systemd
    vulkan-loader
    wayland
    gtk3
    gtk4
  ]
  ++ lib.optional pulseSupport libpulseaudio
  ++ lib.optional libvaSupport libva;
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

    # skrypt-wrapper z deba eksportuje CHROME_WRAPPER i LD_LIBRARY_PATH
    # względem własnej lokalizacji — zostaw go w appdir i opakuj w makeWrapper
    substituteInPlace $appdir/helium-wrapper \
      --replace-fail 'export CHROME_VERSION_EXTRA=deb' 'export CHROME_VERSION_EXTRA=nix'

    makeWrapper "$appdir/helium-wrapper" "$exe" \
      --prefix LD_LIBRARY_PATH : "${rpath}" \
      --prefix PATH            : "${binpath}" \
      --prefix XDG_DATA_DIRS   : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH:${addDriverRunpath.driverLink}/share" \
      --chdir "$appdir" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}

    # popraw interpreter i rpath w binarkach ELF
    for elf in $appdir/helium $appdir/chromedriver $appdir/helium_crashpad_handler; do
      patchelf --set-rpath "${rpath}" $elf || true
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
    homepage = "https://helium.computer";
    license = [
      lib.licenses.bsd3
      lib.licenses.lgpl21
    ];
    mainProgram = "helium";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
})
