{ inputs, ... }:
{
  flake.modules.nixos.nixos-helium =
    { pkgs, ... }:
    {
      # Helium Browser (fork ungoogled-chromium) — pakiet z flake'a
      # github:ominit/helium-browser-flake (input helium-browser).
      # Sandbox Chromium działa na user namespaces (domyślnie włączone).
      environment.systemPackages = [
        inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.helium
      ];
    };
}
