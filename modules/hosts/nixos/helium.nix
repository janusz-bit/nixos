_: {
  flake.modules.nixos.nixos-helium =
    { pkgs, ... }:
    {
      # Helium Browser (fork ungoogled-chromium) — pełna implementacja w
      # modules/packages/_helium, udostępniana przez overlay local-packages.
      # Sandbox Chromium działa na user namespaces (domyślnie włączone).
      environment.systemPackages = [ pkgs.helium ];
    };
}
