# Test VM lockdown (modules/hosts/base/lockdown.nix): `lockdown on` zamyka
# port otwarty w firewallu i zatrzymuje usługę z customBot.lockdownServices,
# a SSH zostaje osiągalny z drugiej maszyny (także gdy openFirewall wpisał 22
# do allowedTCPPorts). Stan przeżywa reload firewalla, ponowny start
# multi-user.target (to robi switch-to-configuration) i reboot; `lockdown off`
# przywraca port i usługę.
#
# Uruchomienie: nix build -L .#checks.<system>.lockdown (wymaga kvm).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Jak Syncthing: port otwarty w firewallu.
      openPort = 8000;
      # Jak backend tunelu: port poza firewallem, sieć dochodzi inną drogą.
      backendPort = 9000;
      httpServer = port: {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.python3} -m http.server ${toString port}";
          DynamicUser = true;
        };
      };
    in
    {
      checks.lockdown = pkgs.testers.runNixOSTest {
        name = "lockdown";
        nodes = {
          server = {
            imports = [
              self.modules.nixos.base-options
              self.modules.nixos.base-lockdown
            ];
            services.openssh.enable = true;
            networking.firewall.allowedTCPPorts = [ openPort ];
            systemd.services = {
              open-port = httpServer openPort;
              tunnel-backend = httpServer backendPort;
            };
            customBot.lockdownServices = [ "tunnel-backend" ];
          };
          client = { };
        };

        testScript = ''
          def lockdown_holds():
              server.fail("systemctl is-active tunnel-backend.service")
              # warunek pominął start, a nie oblał jednostki
              server.fail("systemctl is-failed tunnel-backend.service")
              client.fail("curl -sf --max-time 3 http://server:${toString openPort}/")
              client.succeed("nc -z -w 3 server 22")
              server.succeed("curl -sf --max-time 3 http://localhost:${toString openPort}/")

          start_all()
          server.wait_for_unit("sshd.service")
          server.wait_for_open_port(${toString openPort})
          server.wait_for_open_port(${toString backendPort})
          client.wait_for_unit("multi-user.target")

          with subtest("before lockdown: open port reachable"):
              client.succeed("curl -sf --max-time 3 http://server:${toString openPort}/")
              assert "wyłączony" in server.succeed("lockdown status")

          with subtest("lockdown on: port closed, backend stopped, SSH open"):
              server.succeed("lockdown on")
              lockdown_holds()
              assert "WŁĄCZONY" in server.succeed("lockdown status")

          with subtest("survives firewall reload and multi-user.target restart"):
              server.succeed("systemctl reload firewall.service")
              server.succeed("systemctl start multi-user.target")
              lockdown_holds()

          with subtest("survives reboot"):
              server.shutdown()
              server.start()
              server.wait_for_unit("sshd.service")
              server.wait_for_open_port(${toString openPort})
              lockdown_holds()

          with subtest("lockdown off: port and backend back"):
              server.succeed("lockdown off")
              server.wait_for_open_port(${toString backendPort})
              server.succeed("systemctl is-active tunnel-backend.service")
              client.succeed("curl -sf --max-time 3 http://server:${toString openPort}/")
        '';
      };
    };
}
