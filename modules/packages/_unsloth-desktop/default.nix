{
  lib,
  stdenv,
  cacert,
  buildFHSEnv,
  nix-update-script,
  fetchurl,
  dpkg,
  glib-networking,
}:

buildFHSEnv (
  finalAttrs:
  let
    unsloth-desktop-unwrapped = stdenv.mkDerivation {
      pname = "unsloth-desktop-unwrapped";
      inherit (finalAttrs) version src;

      nativeBuildInputs = [ dpkg ];

      dontConfigure = true;
      dontBuild = true;
      dontStrip = true;
      dontPatchELF = true;

      # Instalator linkuje ~/.local/bin/unsloth do CLI w venv. ~/.local/bin jest
      # w PATH przed /run/current-system/sw/bin, więc taki link przesłoniłby
      # polecenie unsloth z tej paczki, a bez FHS Python z uv nie znajduje CA
      # (CERTIFICATE_VERIFY_FAILED). Aplikacja uruchamia backend bezpośrednio
      # z venv, a `unsloth studio update` uruchamia pobrany instalator tylko
      # z --shortcuts-only, który kończy się przed tym miejscem.
      installPhase = ''
        runHook preInstall
        dpkg-deb -x $src $out
        substituteInPlace $out/usr/lib/Unsloth/install.sh \
          --replace-fail 'ln -sfn "$VENV_DIR/bin/unsloth" "$_shim_path"' 'rm -f "$_shim_path"'
        runHook postInstall
      '';

      meta = {
        description = "Unsloth Studio desktop payload from the upstream .deb (unwrapped)";
        homepage = "https://unsloth.ai/";
        license = lib.licenses.agpl3Only;
        platforms = [ "x86_64-linux" ];
        sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      };
    };

    targetPkgs =
      pkgs: with pkgs; [
        webkitgtk_4_1
        gtk3
        libsoup_3
        glib-networking
        gsettings-desktop-schemas
        hicolor-icon-theme
        shared-mime-info
        libayatana-appindicator
        libnghttp2
        nodejs_24
        cacert
        gcc
        pciutils
      ];

    # Python z uv (python-build-standalone) w venv szuka CA w /etc/ssl/cert.pem,
    # którego NixOS nie ma.
    profile = ''
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export GIO_EXTRA_MODULES="${glib-networking}/lib/gio/modules:$GIO_EXTRA_MODULES"
      export WEBKIT_DISABLE_DMABUF_RENDERER=1
      export CC=gcc
    '';

    # CLI z venv (`unsloth studio setup`, `unsloth studio -p 8888`) w tym samym
    # środowisku co aplikacja.
    unsloth-cli = buildFHSEnv {
      pname = "unsloth";
      inherit (finalAttrs) version;
      inherit targetPkgs profile;
      includeClosures = true;
      runScript = ''"$HOME/.unsloth/studio/unsloth_studio/bin/unsloth"'';
    };
  in
  {
    pname = "unsloth-desktop";
    version = "0.1.915-beta";

    # version i src sa atrybutami pakietu, a nie wewnetrznej derywacji:
    # tylko wtedy nix-update znajduje ich pozycje i podmienia wersje oraz hash.
    src = fetchurl {
      url = "https://github.com/unslothai/unsloth/releases/download/v${finalAttrs.version}/Unsloth-Desktop-Ubuntu.deb";
      hash = "sha256-q8t2YxLKOkc7FwWSv2lfykVmZC6XIZqd6sStTm5h4I0=";
    };

    includeClosures = true;
    inherit targetPkgs profile;

    runScript = "${unsloth-desktop-unwrapped}/usr/bin/unsloth-studio";

    extraInstallCommands = ''
      ln -s ${lib.getExe unsloth-cli} $out/bin/unsloth
      install -Dm644 ${unsloth-desktop-unwrapped}/usr/share/applications/Unsloth.desktop \
        $out/share/applications/unsloth-desktop.desktop
      substituteInPlace $out/share/applications/unsloth-desktop.desktop \
        --replace-fail "Exec=unsloth-studio" "Exec=unsloth-desktop"
      install -Dm644 ${unsloth-desktop-unwrapped}/usr/share/icons/hicolor/128x128/apps/unsloth-studio.png \
        $out/share/icons/hicolor/128x128/apps/unsloth-studio.png
    '';

    passthru = {
      inherit unsloth-desktop-unwrapped unsloth-cli;
      # Upstream oznacza wszystkie wydania sufiksem -beta, a nix-update
      # pomija takie wersje bez --version=unstable.
      updateScript = nix-update-script { extraArgs = [ "--version=unstable" ]; };
    };

    meta = {
      description = "Desktop application for running and training AI models locally";
      homepage = "https://unsloth.ai/";
      changelog = "https://github.com/unslothai/unsloth/releases";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [ parry-97 ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "unsloth-desktop";
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      longDescription = ''
        Wraps the upstream Unsloth Desktop .deb in an FHS environment.

        The app manages its own runtime in ~/.unsloth/studio: on first run it
        bootstraps a uv venv, installs the unsloth PyPI backend and PyTorch
        (CUDA wheels selected by GPU), and downloads prebuilt llama.cpp binaries.
        These runtime components are not part of this package. The `unsloth`
        command runs the CLI from that venv in the same FHS environment; the
        bundled installer no longer links it into ~/.local/bin.

        Note: the in-app self-updater cannot replace the read-only store binary;
        update by rebuilding this package.
      '';
    };
  }
)
