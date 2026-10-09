# Helium Browser (fork ungoogled-chromium) z oficjalnego tar.xz
# (imputnet/helium-linux), pakowany jak google-chrome w nixpkgs.
#
# Binarka jest bajt w bajt ta sama co w .deb i w
# github:ominit/helium-browser-flake — o działaniu decyduje wyłącznie to,
# co przeglądarka znajdzie w runtime. Chromium ładuje przez dlopen()
# biblioteki spoza DT_NEEDED, a ANGLE jest wkompilowane statycznie w
# `helium`, więc wszystkie te dlopen-y idą przez RUNPATH tej binarki:
# - libpci: bez niej ANGLE nie rozpoznaje GPU (chrome://gpu: VENDOR=0x0000)
#   i nie działają obejścia z gpu_driver_bug_list, np. msaa_is_slow dla
#   Intela (rasteryzacja z MSAA na iGPU),
# - libvulkan.so.1: dołączony loader nie zna /run/opengl-driver i nie widzi
#   żadnego ICD (Dawn/WebGPU tylko na SwiftShader) — podmieniony na loader
#   z nixpkgs,
# - libva (VA-API), libpulse (zamiast ALSA), pipewire (udostępnianie ekranu
#   na Waylandzie), speech-dispatcher (Web Speech), GTK 3 (UI; bez niego
#   Helium spada na Qt).
# RUNPATH zamiast LD_LIBRARY_PATH: zmienna nie przecieka do programów
# uruchamianych z przeglądarki (xdg-open). dontPatchELF, bo --shrink-rpath
# w fixupPhase wyciąłby katalogi bibliotek ładowanych tylko przez dlopen.
#
# Wrapper bez flag: Chromium 154 sam wybiera Wayland z XDG_SESSION_TYPE
# (--ozone-platform-hint i WaylandWindowDecorations już nie istnieją),
# VA-API jest domyślnie włączone, a upstream prosi pakujących, żeby nie
# dodawali flag zależnych od środowiska.
#
# Pomiar względem ominit (0.18.2.1, host nixos, przebiegi przeplatane, po
# jednej przeglądarce): start do `load` 290 vs 323 ms (n=10, p<0,001; UI w
# Qt, na które ominit spadał bez GTK, kosztuje ok. +85 ms), odtwarzanie
# 4K60 H.264/VP9/AV1 przez VA-API 0,44 vs 0,56 rdzenia (n=8, p<0,01; cały
# nadmiar w procesie GPU, samo libpci go nie usuwa), Speedometer 3.1 bez
# różnicy.
#
# Test: nix build .#helium, potem w chrome://gpu GPU0/GPU1 = 0x10de/0x8086,
# "Driver Bug Workarounds" zawiera msaa_is_slow, a Vulkan widzi Intel+NVIDIA.
{
  lib,
  stdenvNoCC,
  fetchurl,
  bintools,
  makeWrapper,
  patchelf,
  nix-update-script,
  versionCheckHook,

  # DT_NEEDED
  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  glib,
  libgbm,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  systemd,

  # dlopen()
  gtk3,
  libglvnd,
  libpulseaudio,
  libva,
  pciutils,
  pipewire,
  speechd-minimal,
  vulkan-loader,

  adwaita-icon-theme,
  gsettings-desktop-schemas,
  xdg-utils,
}:

let
  rpath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    systemd

    gtk3
    libglvnd
    libpulseaudio
    libva
    pciutils
    pipewire
    speechd-minimal
    vulkan-loader
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "helium";
  version = "0.18.2.1";

  src =
    let
      arch =
        {
          x86_64-linux = "x86_64";
          aarch64-linux = "arm64";
        }
        .${stdenvNoCC.hostPlatform.system}
          or (throw "helium: unsupported system ${stdenvNoCC.hostPlatform.system}");
    in
    fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${finalAttrs.version}/helium-${finalAttrs.version}-${arch}_linux.tar.xz";
      hash =
        {
          x86_64 = "sha256-RJPXVrmK++P9fUXA7CFcI/WgVR+ucVWG/mzjsimLFVw=";
          arm64 = "sha256-2EVqgJIHVwPnn/4yHlXMl57osZ8ncJzxZY7Jwthrfyk=";
        }
        .${arch};
    };

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  # Setup hooki wypełniają $XDG_ICON_DIRS i $GSETTINGS_SCHEMAS_PATH dla
  # wrappera; bez schematów GTK przerywa proces przy dialogach (np. wydruku).
  buildInputs = [
    adwaita-icon-theme
    glib
    gsettings-desktop-schemas
    gtk3
  ];

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    appdir=$out/lib/helium
    mkdir -p $appdir
    cp -a . $appdir
    ln -sf ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $appdir/libvulkan.so.1

    for elf in $appdir/{helium,helium_crashpad_handler,chromedriver}; do
      patchelf --set-interpreter ${bintools.dynamicLinker} --set-rpath ${rpath} $elf
    done

    # CHROME_WRAPPER trafia do Exec= skrótów generowanych przez Chromium
    # (PWA, skróty URL), więc wskazują one wrapper z PATH, a nie ścieżkę
    # konkretnej wersji w store (restart przeglądarki i tak używa argv[0]).
    makeWrapper $appdir/helium $out/bin/helium \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --set CHROME_WRAPPER helium \
      --set CHROME_VERSION_EXTRA nix

    install -Dm444 $appdir/helium.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail "Exec=helium" "Exec=$out/bin/helium"
    install -Dm444 $appdir/product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png

    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    homepage = "https://helium.computer";
    changelog = "https://github.com/imputnet/helium-linux/releases/tag/${finalAttrs.version}";
    license = with lib.licenses; [
      gpl3Only
      bsd3
    ];
    mainProgram = "helium";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
