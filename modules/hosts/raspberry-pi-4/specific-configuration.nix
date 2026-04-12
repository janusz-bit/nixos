{ ... }:
{
  flake.nixosModules.raspberry-pi-4-specific-configuration =
    { pkgs, ... }:
    {
      hardware = {
        raspberry-pi."4".apply-overlays-dtmerge.enable = true;
      };
      console.enable = false;
      environment.systemPackages = with pkgs; [
        libraspberrypi
        raspberrypi-eeprom
      ];
      hardware.raspberry-pi."4".fkms-3d.enable = true;
      services.xserver = {
        enable = true;
      };
      boot.kernelParams = [
        "snd_bcm2835.enable_hdmi=1"
        "snd_bcm2835.enable_headphones=1"
      ];
      systemd.services.btattach = {
        before = [ "bluetooth.service" ];
        after = [ "dev-ttyAMA0.device" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.bluez}/bin/btattach -B /dev/ttyAMA0 -P bcm -S 3000000";
        };
      };
    };
}
