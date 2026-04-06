{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  buildFHSEnv,
  writeShellScript,
  libX11,
  makeDesktopItem,
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
      libX11
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

  runScript = writeShellScript "tdm-installer-entry" ''
    set -e
    install_dir="''${TDM_HOME:-$HOME/Games/darkmod}"
    mkdir -p "$install_dir"
    cd "$install_dir"
    # Child processes (e.g. self-update .cmd scripts) must resolve sh/bash from this FHS env.
    export PATH="/bin:/usr/bin:$PATH"
    exec ${unwrapped}/libexec/tdm/tdm_installer.linux64 "$@"
  '';

  desktopItem = makeDesktopItem {
    name = "tdm-installer";
    desktopName = "The Dark Mod Installer";
    exec = "tdm-installer";
    comment = "The Dark Mod Installer";
    categories = [ "Game" ];
    terminal = false;
  };
in
buildFHSEnv {
  pname = "tdm-installer";
  version = "zipsync";
  inherit runScript;

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cp -r ${desktopItem}/share/applications/* $out/share/applications/
  '';

  # Self-update .cmd scripts use #!/bin/bash; FHS env supplies /bin/bash without touching host /bin.
  meta = with lib; {
    description = "Official The Dark Mod installer (downloads game data on first run)";
    longDescription = ''
      Runs in an FHS bubblewrap so self-update shell scripts find /bin/bash on NixOS.
      Game files go to $HOME/Games/darkmod by default (override with TDM_HOME); set a writable path in the GUI if needed.
    '';
    homepage = "https://www.thedarkmod.com/";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "tdm-installer";
  };

  passthru.unwrapped = unwrapped;
}
