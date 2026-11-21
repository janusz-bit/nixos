# OpenBot (openbot.run): aplikacja Electron do pracy zespołu agentów AI
# (Codex, Claude, Gemini, Ollama, ...) na własnym komputerze. Pakowana
# z AppImage z wydań nightly-labs/openbot przez appimageTools.wrapType2,
# które daje środowisko FHS z bibliotekami Electrona (GTK 3, NSS, X11, libgbm);
# dołączone binarki (cua-driver, runtime głosu sherpa-onnx) potrzebują tylko
# bibliotek z tego samego zestawu.
#
# Electron 45 sam wybiera Wayland z XDG_SESSION_TYPE, więc wrapper nie dodaje
# flag ozone. Auto-aktualizacja electron-updatera nie działa bez zmiennej
# APPIMAGE (store jest tylko do odczytu); wersję podbija flake-update.
# Dane aplikacji: ~/.config/OpenBot.
#
# Sprawdzenie: `nix build .#openbot`, potem `openbot` (lub wpis OpenBot
# w menu) otwiera okno, a `xdg-open openbot://` trafia do aplikacji.
{
  lib,
  appimageTools,
  fetchurl,
  nix-update-script,
}:

appimageTools.wrapType2 (finalAttrs: {
  pname = "openbot";
  version = "0.76.1";

  src = fetchurl {
    url = "https://github.com/nightly-labs/openbot/releases/download/v${finalAttrs.version}/OpenBot-${finalAttrs.version}-x86_64.AppImage";
    hash = "sha256-dTum6FyHmK7PlwmUiuV0pX8n+dBmk3SQK3Em2Kc9s20=";
  };

  # Ikona ma 1600x1600, czego hicolor/index.theme nie zna, więc idzie do
  # pixmaps (fallback motywów ikon).
  extraInstallCommands = ''
    install -Dm644 ${finalAttrs.contents}/openbot.desktop \
      $out/share/applications/openbot.desktop
    substituteInPlace $out/share/applications/openbot.desktop \
      --replace-fail "Exec=AppRun %U" "Exec=openbot %U"
    install -Dm644 ${finalAttrs.contents}/openbot.png \
      $out/share/pixmaps/openbot.png
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Local-first desktop workspace for a team of AI agents";
    homepage = "https://openbot.run/";
    changelog = "https://github.com/nightly-labs/openbot/releases/tag/v${finalAttrs.version}";
    # Brak w lib.licenses; użytek komercyjny wymaga osobnej licencji.
    license = {
      fullName = "PolyForm Noncommercial License 1.0.0";
      spdxId = "PolyForm-Noncommercial-1.0.0";
      url = "https://polyformproject.org/licenses/noncommercial/1.0.0/";
      free = false;
      redistributable = true;
    };
    mainProgram = "openbot";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
