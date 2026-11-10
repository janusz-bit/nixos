# Tymczasowy overlay cargo-system-libs: brakujące biblioteki systemowe dla
# pakietów Rust z nixpkgs, które przestały się budować po dodaniu
# `cargoUseSystemLibs` do cargo-setup-hook (temporary-fixes.md, wpis 15).
#
# Hook eksportuje domyślnie m.in. ZSTD_SYS_USE_PKG_CONFIG=1,
# AWS_LC_SYS_USE_SYSTEM=1, RUSTONIG_SYSTEM_LIBONIG=1 i
# LIBSQLITE3_SYS_USE_PKG_CONFIG=1, więc crate'y *-sys nie budują już
# dołączonych kopii i padają, gdy pakiet nie ma biblioteki w buildInputs.
# Listy odpowiadają poprawkom z nixpkgs master (ark "use system zstd": zstd
# i pkg-config; codex: aws-lc, oniguruma, sqlite, zstd); obscura nie ma
# jeszcze poprawki upstream. Overlay jest w base-nix, bo obscura i codex są
# na laptopie i RPi.
#
# Sprawdzenie: `nix build --no-link
# .#nixosConfigurations.nixos.pkgs.{obscura,ark,codex}`.
_: {
  flake.overlays.cargo-system-libs =
    _final: prev:
    let
      withInputs =
        pkg:
        {
          native ? [ ],
          build,
        }:
        pkg.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ native;
          buildInputs = (old.buildInputs or [ ]) ++ build;
        });
    in
    {
      # ark nie miał wcale pkg-config, przez który zstd-sys szuka biblioteki.
      ark = withInputs prev.ark {
        native = [ prev.pkg-config ];
        build = [ prev.zstd ];
      };
      codex = withInputs prev.codex {
        build = [
          prev.aws-lc
          prev.oniguruma
          prev.sqlite
          prev.zstd
        ];
      };
      obscura = withInputs prev.obscura { build = [ prev.zstd ]; };
    };
}
