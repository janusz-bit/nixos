_: {
  flake.modules.nixos.nixos-helium =
    { pkgs, ... }:
    {
      # Helium Browser (fork ungoogled-chromium) — pakiet lokalny
      # modules/packages/_helium (overlay local-packages); tam opis, czemu
      # nie github:ominit/helium-browser-flake.
      # Sandbox Chromium działa na user namespaces (domyślnie włączone).
      environment.systemPackages = [ pkgs.helium ];
    };
}
