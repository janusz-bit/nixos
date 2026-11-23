{
  lib,
  buildFHSEnv,
  fetchurl,
  fetchzip,
  imagemagick,
  runCommand,
  writeShellApplication,
}:

# Instalator jest pod niewersjonowanym URL-em i sam pobiera swoje nowsze wersje,
# więc ten z paczki służy tylko do pierwszego startu: launcher kopiuje go do
# katalogu gry i stamtąd uruchamia (w store nie mógłby się nadpisać). Gdy
# upstream wymieni plik, pobranie z czystego store kończy się błędem hasha:
# `nix-update -F thedarkmod --version=skip` odświeża hash.
buildFHSEnv (
  finalAttrs:
  let
    # Biblioteki silnika 2.14 (DT_NEEDED i dlopen thedarkmod.x64) i instalatora
    # (libX11). Dźwięk idzie przez ALSA, a więc przez wtyczkę PipeWire hosta.
    targetPkgs =
      pkgs: with pkgs; [
        alsa-lib
        libGL
        libx11
        libxcursor
        libxext
        libxi
        libxinerama
        libxrandr
        libxrender
        libxxf86vm
        stdenv.cc.cc.lib
      ];

    # Katalog gry (~6 GB) należy do instalatora (zipsync zapisuje w nim
    # .zipsync/lastinstall.ini), więc leży w $HOME, nie w store.
    launcher = writeShellApplication {
      name = "thedarkmod-launcher";
      text = ''
        game_dir="$HOME/Games/darkmod"
        mkdir -p "$game_dir"
        cd "$game_dir"
        if [[ $1 == game && -x ./thedarkmod.x64 ]]; then
          shift
          exec ./thedarkmod.x64 "$@"
        fi
        shift
        if [[ ! -x ./tdm_installer.linux64 ]]; then
          install -m755 ${finalAttrs.src}/tdm_installer.linux64 ./tdm_installer.linux64
        fi
        exec ./tdm_installer.linux64 "$@"
      '';
    };

    # Instalator nie ma ikony, a gra leży poza store, więc logo bierzemy z ikony
    # Windows ze źródeł silnika (oficjalny mirror SVN). Wpisy 10-14 (od zera)
    # to komplet 32-bitowych RGBA; wcześniejsze są 4/8-bitowe albo ditherowane,
    # a jeden 4-bitowy jest uszkodzony, przez co icotool kończy się błędem
    # na całym pliku — ImageMagick czyta tylko wskazany wpis.
    icons =
      runCommand "thedarkmod-icons"
        {
          nativeBuildInputs = [ imagemagick ];
          src = fetchurl {
            url = "https://raw.githubusercontent.com/stgatilov/darkmod_src/1ebe26440ffbeccb64e9c047c13a4f39e4eae21a/sys/win32/rc/res/darkmod.ico";
            hash = "sha256-D2+o+Uq1/VWEcS1dzDAQzxdlIPYnwbXkjZxqdjZUdi0=";
          };
        }
        ''
          for entry in 10:256 11:48 12:32 13:24 14:16; do
            size=''${entry#*:}
            dir=$out/share/icons/hicolor/''${size}x''${size}/apps
            mkdir -p "$dir"
            magick "$src[''${entry%%:*}]" "png32:$dir/thedarkmod.png"
          done
        '';

    tdm-installer = buildFHSEnv {
      pname = "tdm-installer";
      inherit (finalAttrs) version;
      inherit targetPkgs;
      runScript = "${lib.getExe launcher} installer";
    };
  in
  {
    pname = "thedarkmod";
    version = "0-unstable-2026-04-26";

    src = fetchzip {
      url = "https://update.thedarkmod.com/zipsync/tdm_installer.linux64.zip";
      hash = "sha256-7ILaZZ1woS8B70FRFl0iPjzwqufU3kctMSps9z5Bv+8=";
      stripRoot = false;
    };

    inherit targetPkgs;
    runScript = "${lib.getExe launcher} game";

    extraInstallCommands = ''
      ln -s ${lib.getExe tdm-installer} $out/bin/tdm-installer
      mkdir -p $out/share
      ln -s ${icons}/share/icons $out/share/icons
    '';

    passthru = { inherit icons launcher tdm-installer; };

    meta = {
      description = "Stealth game in the style of Thief, run through its official installer";
      longDescription = ''
        `thedarkmod` starts the game from ~/Games/darkmod, or the official
        installer when the game is not installed yet; `tdm-installer` always
        starts the installer (game updates, other releases).
      '';
      homepage = "https://www.thedarkmod.com/";
      license = lib.licenses.gpl3Plus;
      platforms = [ "x86_64-linux" ];
      mainProgram = "thedarkmod";
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
)
