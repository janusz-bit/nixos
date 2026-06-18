{ inputs, ... }:
{
  # Workaround for stale npmDepsHash in hermes-agent's nix/lib.nix.
  #
  # The upstream-locked revision (c5eb64b9) carries npmDepsHash =
  # "sha256-m9cjbjzi4SaFCjODfdrawS5e+1ag+MpRn528/upSNqo=" which no
  # longer matches the realized fetchNpmDeps output on current
  # nixos-unstable (nixpkgs changed how fetchNpmDeps hashes the
  # workspace lockfile). Upstream's `fix-lockfiles` CI hasn't caught
  # up because it runs on a pinned nixpkgs that still agrees with the
  # old hash.
  #
  # We re-apply the `fix-lockfiles --apply` result by patching the
  # hermes-agent source tree (substituting the stale npmDepsHash in
  # nix/lib.nix) and re-running callPackage against the patched tree.
  # This fixes the hash at the point hermes-agent.nix does
  # `callPackage ./lib.nix`, which is where the broken fetchNpmDeps
  # invocation lives.
  flake.overlays.hermes-agent = final: _prev: {
    hermes-agent =
      let
        hermes = inputs.hermes-agent;
        patchedSrc = final.applyPatches {
          name = "hermes-agent-source-patched";
          src = hermes.outPath;
          postPatch = ''
            substituteInPlace nix/lib.nix \
              --replace \
                "sha256-m9cjbjzi4SaFCjODfdrawS5e+1ag+MpRn528/upSNqo=" \
                "sha256-kbjJksq7limRIYqP3DwI+GNgCXkG96tXcsQqmuEedxo="
          '';
        };
      in
      final.callPackage "${patchedSrc}/nix/hermes-agent.nix" {
        inherit (inputs.hermes-agent.inputs)
          uv2nix
          pyproject-nix
          pyproject-build-systems
          ;
        npm-lockfile-fix =
          inputs.hermes-agent.inputs.npm-lockfile-fix.packages.${final.stdenv.hostPlatform.system}.default;
        rev = hermes.rev or null;
      };
  };
}
