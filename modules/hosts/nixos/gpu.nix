{ customTop, lib, ... }:
{
  flake.modules.nixos.nixos-gpu =
    { pkgs, config, ... }:
    let
      # gpu.sh używa lspci/virsh/modprobe — zamiast polegać na PATH
      # użytkownika, dowiązujemy je do PATH wrappera. UWAGA: celowo bez
      # pkgs.sudo — sudo musi zostać setuid wrapperem z /run/wrappers/bin.
      gpuScript = pkgs.symlinkJoin {
        name = "gpu";
        paths = [ (pkgs.writeShellScriptBin "gpu" (builtins.readFile ./gpu.sh)) ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/gpu --prefix PATH : ${
            lib.makeBinPath [
              pkgs.pciutils
              pkgs.libvirt
              pkgs.kmod
              pkgs.coreutils
              pkgs.gnugrep
            ]
          }
        '';
      };
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
