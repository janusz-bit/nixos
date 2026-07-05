{ self, ... }:
{
  flake.overlays.opencode-config = final: prev: {
    opencode = prev.opencode.overrideAttrs (oldAttrs: {
      postInstall = (oldAttrs.postInstall or "") + ''
        mkdir -p $out/share/opencode
        install -Dm644 ${self + /modules/configs/opencode/opencode.json} $out/share/opencode/opencode.json
        install -Dm755 ${
          self + /modules/configs/opencode/web-search-mcp.py
        } $out/share/opencode/web-search-mcp.py
        substituteInPlace $out/share/opencode/opencode.json \
          --replace-fail "/etc/opencode/web-search-mcp.py" "$out/share/opencode/web-search-mcp.py"
        wrapProgram $out/bin/opencode --set OPENCODE_CONFIG $out/share/opencode/opencode.json
      '';
    });
  };
}
