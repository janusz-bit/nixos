{ lib, ... }:
{
  flake.modules.nixos.nixos-gpu =
    { pkgs, ... }:
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
    in
    {
      environment = {
        systemPackages = [ gpuScript ];

        # Aliasy propagują się automatycznie do fisha
        # (programs.fish.shellAliases = mkDefault environment.shellAliases).
        shellAliases = {
          # Skróty do subkomend skryptu `gpu`
          gpu-status = "gpu status";
          gpu-vfio = "gpu vfio";
          gpu-host = "gpu host";
        };
      };
    };
}
