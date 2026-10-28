# Podbija strata w modules/packages/_strata/default.nix.
#
# nix-update robi to, co potrafi z tagu: wersję, hash src oraz hashe
# engine i llamaCpp (`--custom-dep`). Ten skrypt dokłada dwie rzeczy,
# których z tagu nie odczyta: wersję silnika (asset CUDA 13 w SHA256SUMS.txt
# wydania, własna numeracja — bywa starsza niż Control) i LLAMA_CPP_COMMIT
# z setup.py wydania. Dlatego version, src, engine i llamaCpp muszą być
# atrybutami derywacji, a nie kryć się w wrapperze.
{
  coreutils,
  curl,
  git,
  gnugrep,
  gnused,
  jq,
  nix,
  nix-update,
  writeShellApplication,
}:

writeShellApplication {
  name = "update-strata";
  runtimeInputs = [
    coreutils
    curl
    git
    gnugrep
    gnused
    jq
    nix
    nix-update
  ];
  text = builtins.readFile ./update.sh;
}
