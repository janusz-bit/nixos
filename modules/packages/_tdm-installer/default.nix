{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  buildFHSEnv,
  writeShellScript,
  makeDesktopItem,
  libx11,
}:

let
  unwrapped = stdenv.mkDerivation {
    pname = "tdm-installer-unwrapped";
    version = "zipsync";

    src = fetchzip {
      url = "https://update.thedarkmod.com/zipsync/tdm_installer.linux64.zip";
      sha256 = "0pfjdb0n2d4xdh5s1rv0vmxaw8bwj8sn4ifm3gkwwc7s1pg7frgm";
      stripRoot = false;
    };

    nativeBuildInputs = [ autoPatchelfHook ];

    buildInputs = [
      stdenv.cc.cc.lib
      libx11
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/libexec/tdm
      install -m755 "$src/tdm_installer.linux64" $out/libexec/tdm/tdm_installer.linux64
      runHook postInstall
    '';
  };

  runScript = writeShellScript "tdm-entry" ''
    set -e
    install_dir="''${TDM_HOME:-$HOME/Games/darkmod}"
    mkdir -p "$install_dir"
    cd "$install_dir"

    # Skrypty aktualizatora gry (.cmd) używają #!/bin/bash
    export PATH="/bin:/usr/bin:$PATH"

    # Jeśli gra jest zainstalowana, uruchom ją. W przeciwnym razie uruchom instalator.
    if [ -x "./thedarkmod.x64" ]; then
      exec ./thedarkmod.x64 "$@"
    else
      exec ${unwrapped}/libexec/tdm/tdm_installer.linux64 "$@"
    fi
  '';

  desktopItem = makeDesktopItem {
    name = "tdm-installer";
    desktopName = "The Dark Mod";
    exec = "tdm-installer";
    comment = "The Dark Mod Game and Installer";
    categories = [ "Game" ];
    terminal = false;
  };
in
buildFHSEnv {
  pname = "tdm-installer";
  version = "zipsync";
  inherit runScript;

  targetPkgs =
    pkgs: with pkgs; [
      libx11
      libxext
      libxxf86vm
      libGL
      openal
      libpng
      libjpeg
      curl
      boost
      ffmpeg
      xdg-utils
      zlib
      stdenv.cc.cc.lib
    ];

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cp -r ${desktopItem}/share/applications/* $out/share/applications/
  '';

  meta = with lib; {
    description = "Official The Dark Mod installer and game runner";
    longDescription = ''
      Runs in an FHS bubblewrap supplying all dependencies required by the Dark Mod engine
      (OpenAL, MESA, X11, etc.) on NixOS.
      Game files go to $HOME/Games/darkmod by default (override with TDM_HOME).
    '';
    homepage = "https://www.thedarkmod.com/";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "tdm-installer";
  };

  passthru.unwrapped = unwrapped;
}
