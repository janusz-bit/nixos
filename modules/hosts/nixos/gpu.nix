{ customTop, ... }:
{
  flake.modules.nixos.nixos-gpu =
    { pkgs, config, ... }:
    let
      gpuScript = pkgs.writeShellScriptBin "gpu" (builtins.readFile ./gpu.sh);
      flakeTarget = config.customBot.flakeTarget;
      rebuildSpecialisation =
        flakeRef:
        "sudo nixos-rebuild switch --sudo --specialisation gpu-passthrough --flake ${flakeRef}#${flakeTarget} --refresh";
    in
    {
      environment = {
        systemPackages = [ gpuScript ];

        # Aliasy propagują się automatycznie do fisha
        # (programs.fish.shellAliases = mkDefault environment.shellAliases).
        shellAliases = {
          # Boot-time: przełącz na specjalizację gpu-passthrough (GPU -> VM)
          update-passthrough = rebuildSpecialisation customTop.repository.linkFlake;
          update-passthrough-local = rebuildSpecialisation customTop.repository.place;

          # Skróty do subkomend skryptu `gpu`
          gpu-status = "gpu status";
          gpu-vfio = "gpu vfio";
          gpu-host = "gpu host";
        };
      };
    };
}
