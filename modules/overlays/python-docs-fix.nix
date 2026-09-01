_: {
  # Workaround dla https://github.com/NixOS/nixpkgs/issues/499166
  # (build failure python3.x-doc: TypeError w docutils parse_enumerator
  # przy docutils >= 0.22; padalo tez na 0.23).
  # Pin docutils 0.21.2 + sphinx 8.2.3 dotyczy WYLACZNIE srodowiska
  # budujacego dokumentacje cpythona (passthru.doc) — reszta systemu
  # korzysta z normalnych wersji z nixpkgs. Usunac, gdy nixpkgs naprawi
  # docs-builder. Slad w temporary-fixes.md (poz. 1).
  flake.overlays.python-docs-fix = final: prev: {
    python311 =
      let
        docsBuilderPython = prev.python3.override {
          self = docsBuilderPython;
          packageOverrides = pself: pprev: {
            docutils = pprev.docutils.overridePythonAttrs (old: rec {
              version = "0.21.2";
              src = prev.fetchurl {
                url = "mirror://sourceforge/docutils/docutils-${version}.tar.gz";
                hash = "sha256-OmsYcy7fGC2qPNEndbuzOM9WkUaPke7rEJ3v9uv6mG8=";
              };
            });
            sphinx = pprev.sphinx.overridePythonAttrs (old: rec {
              version = "8.2.3";
              src = old.src.overrideAttrs {
                tag = "v${version}";
                hash = "sha256-FoyCpDGDKNN2GMhE7gDpJLmWRWhbMCYlcVEaBTfXSEw=";
              };
              postPatch = (old.postPatch or "") + ''
                substituteInPlace pyproject.toml --replace-fail "roman-numerals-py" "roman-numerals"
              '';
              doCheck = false;
            });
          };
        };
      in
      prev.python311 // {
        doc = prev.python311.doc.overrideAttrs (_old: {
          nativeBuildInputs = with docsBuilderPython.pkgs; [
            sphinxHook
            python-docs-theme
          ];
        });
      };
  };
}
