{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  nodejs,
  makeWrapper,
  writableTmpDirAsHomeHook,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "deepseek-harness";
  version = "0.1.1-rc.2";

  src = fetchFromGitHub {
    owner = "deepseek-ai";
    repo = "deepseek-harness";
    tag = "dsh-v${finalAttrs.version}";
    hash = "sha256-rrjXoyccTxKIbZ00Z4Vy7EA9tGZ15WUqLBFnZSgw1YE=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-+PsdK9u3ZKv4XtSc8tBKKP48J/95/CGTMIUf8Q8dbok=";
    fetcherVersion = 4;
  };

  nativeBuildInputs = [
    nodejs
    pnpm_11
    pnpmConfigHook
    makeWrapper
    writableTmpDirAsHomeHook
  ];

  env.DSH_CLIENT_COMMIT_HASH = "b150a551b8d465e31e418e1b2eaf5e79bbb7d28e";

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/deepseek-harness $out/bin
    cp -r . $out/lib/deepseek-harness/

    makeWrapper ${nodejs}/bin/node $out/bin/dsh \
      --add-flags "$out/lib/deepseek-harness/apps/cli/lib/bin.js" \
      --prefix PATH : "${
        lib.makeBinPath [
          nodejs
          pnpm_11
        ]
      }" \
      --set-default NODE_ENV production

    makeWrapper ${nodejs}/bin/node $out/bin/deepseek-harness \
      --add-flags "$out/lib/deepseek-harness/apps/cli/lib/bin.js" \
      --prefix PATH : "${
        lib.makeBinPath [
          nodejs
          pnpm_11
        ]
      }" \
      --set-default NODE_ENV production

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckProgram = "${placeholder "out"}/bin/dsh";
  versionCheckProgramArg = "--version";

  meta = {
    description = "Open-source agent harness with modular plugin-based architecture";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = lib.platforms.linux;
  };
})
