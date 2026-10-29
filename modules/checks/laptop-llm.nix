# Test VM tunelu laptop-llm (modules/hosts/laptop-llm.nix): konto hermes na
# „RPi” dostaje przez 127.0.0.1:<port> odpowiedź serwera słuchającego tylko na
# localhost „laptopa”, inne konto RPi dostaje odmowę. Klucz tunelu nie daje na
# laptopie przekierowania do innego portu, -R, gniazd Unix ani polecenia;
# reguła iptables przeżywa reload firewalla bez mnożenia się, a przy
# nieosiągalnym laptopie połączenie kończy się w czasie ConnectTimeout.
#
# Moduły są prawdziwe; testowy customTop podmienia tylko klucze (klucz kont
# i klucz hosta laptopa) na snakeoil z nixpkgs, bo prywatna część
# keys.users.hermes-llm jest sekretem, a adresy węzłów to te z customTop.lan.
#
# Uruchomienie: nix build -L .#checks.<system>.laptop-llm (wymaga kvm).
{
  config,
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (config.customTop) lan;
in
{
  perSystem =
    { pkgs, ... }:
    let
      snakeOil = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;

      testTop = {
        options.customTop = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = lib.recursiveUpdate config.customTop {
            keys = {
              users.hermes-llm = snakeOil.snakeOilEd25519PublicKey;
              sshHostKeys.nixos = snakeOil.snakeOilPublicKey;
            };
          };
        };
      };

      lanAddress = address: {
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            inherit address;
            prefixLength = 24;
          }
        ];
      };

      httpServer = port: text: {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.python3} -m http.server --bind 127.0.0.1 --directory ${pkgs.writeTextDir "marker" text} ${toString port}";
          DynamicUser = true;
        };
      };
    in
    {
      checks.laptop-llm = pkgs.testers.runNixOSTest (
        { nodes, ... }:
        let
          listen = lib.head nodes.rpi.systemd.sockets.laptop-llm.listenStreams;
          port = lib.toInt (lib.last (lib.splitString ":" listen));
          otherPort = port + 1;
        in
        {
          name = "laptop-llm";
          nodes = {
            laptop = {
              imports = [
                testTop
                self.modules.nixos.nixos-laptop-llm
                (lanAddress lan.laptop)
              ];
              services.openssh = {
                enable = true;
                hostKeys = [
                  {
                    type = "ecdsa";
                    path = "/etc/ssh/ssh_host_ecdsa_key";
                  }
                ];
              };
              # sshd odrzuca klucz hosta czytelny dla innych (plik w store ma 0444).
              environment.etc."ssh/ssh_host_ecdsa_key" = {
                source = snakeOil.snakeOilPrivateKey;
                mode = "0600";
              };
              systemd = {
                services = {
                  llm = httpServer port "laptop-llm-ok";
                  other = httpServer otherPort "other-port";
                  "unix-marker@".serviceConfig = {
                    ExecStart = "${pkgs.coreutils}/bin/echo unix-marker";
                    StandardInput = "socket";
                  };
                };
                sockets.unix-marker = {
                  wantedBy = [ "sockets.target" ];
                  listenStreams = [ "/run/unix-marker.sock" ];
                  socketConfig = {
                    Accept = true;
                    SocketMode = "0666";
                  };
                };
              };
              environment.systemPackages = [
                pkgs.curl
                pkgs.netcat
              ];
            };

            rpi = {
              imports = [
                testTop
                inputs.agenix.nixosModules.default
                self.modules.nixos.ai-options
                self.modules.nixos.ai-models
                self.modules.nixos.rpi-laptop-llm
                (lanAddress "192.168.100.2")
                # Z modułu Hermesa rpi-laptop-llm czyta tylko konto i ustawienia.
                {
                  options.services.hermes-agent = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = "hermes";
                    };
                    settings = lib.mkOption {
                      type = lib.types.attrsOf lib.types.anything;
                      default = { };
                    };
                  };
                }
              ];
              # Sekret z repo jest zaszyfrowany dla prawdziwych hostów, więc agenix
              # go nie odszyfruje; test kładzie klucz na jego ścieżce sam.
              age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
              users = {
                users.hermes = {
                  isSystemUser = true;
                  group = "hermes";
                };
                groups.hermes = { };
              };
              environment.systemPackages = [
                pkgs.curl
                pkgs.netcat
              ];
            };
          };

          testScript = ''
            import time

            url = "http://${listen}/marker"
            ssh = "ssh -F /dev/null -i /root/test-key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null hermes-llm@${lan.laptop}"
            request = "printf 'GET /marker HTTP/1.0\\r\\n\\r\\n'"

            def access_holds():
                assert "laptop-llm-ok" in rpi.succeed(f"runuser -u hermes -- curl -sf --max-time 20 {url}")
                # 7: odmowa połączenia (REJECT), a nie błąd po drugiej stronie
                assert rpi.execute(f"runuser -u nobody -- curl -s --max-time 5 {url}")[0] == 7

            start_all()
            laptop.wait_for_unit("sshd.service")
            laptop.wait_for_open_port(${toString port}, "127.0.0.1")
            laptop.wait_for_open_port(${toString otherPort}, "127.0.0.1")
            rpi.wait_for_unit("laptop-llm.socket")
            rpi.wait_for_unit("multi-user.target")
            rpi.succeed("install -D -m 0400 ${snakeOil.snakeOilEd25519PrivateKey} ${nodes.rpi.age.secrets.hermes-llm-key.path}")
            rpi.succeed("install -m 0400 ${snakeOil.snakeOilEd25519PrivateKey} /root/test-key")

            with subtest("only hermes reaches the laptop's localhost server"):
                access_holds()

            with subtest("the key forwards only to the one port"):
                assert "laptop-llm-ok" in rpi.succeed(f"{request} | {ssh} -W 127.0.0.1:${toString port}")
                laptop.succeed("curl -sf http://127.0.0.1:${toString otherPort}/marker")
                assert rpi.execute(f"{request} | {ssh} -W 127.0.0.1:${toString otherPort}")[0] == 255

            with subtest("no remote forwarding, Unix sockets or commands"):
                # bez bloku Match `port-forwarding` z klucza pozwoliłoby na -R: -N czekałoby do timeout (124)
                assert rpi.execute(f"timeout 15 {ssh} -N -o ExitOnForwardFailure=yes -R 127.0.0.1:9000:127.0.0.1:22")[0] == 255
                laptop.succeed("nc -U /run/unix-marker.sock </dev/null | grep -q unix-marker")
                # ssh w tle nie może trzymać wyjścia polecenia sterownika testu
                rpi.succeed(f"{ssh} -f -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9002:/run/unix-marker.sock >/dev/null 2>&1")
                assert "unix-marker" not in rpi.succeed("nc -w 5 127.0.0.1 9002 </dev/null || true")
                rpi.succeed("pkill -f 'L 127.0.0.1:9002'")
                # nologin kończy z kodem 1; powłoka wykonałaby `true` (0)
                assert rpi.execute(f"{ssh} true")[0] == 1

            with subtest("firewall reload keeps exactly one owner rule"):
                rpi.succeed("systemctl reload firewall.service")
                assert rpi.succeed("iptables -S OUTPUT | grep -c -- '--dport ${toString port}'").strip() == "1"
                access_holds()

            with subtest("unreachable laptop: the connection ends within ConnectTimeout"):
                laptop.succeed("iptables -I INPUT -p tcp --dport 22 -j DROP")
                # 56: gniazdo przyjęło połączenie, a ssh skończył się po ConnectTimeout
                # bez czytania żądania, więc jądro zamyka je RST; 28 znaczyłoby zawieszenie
                start = time.monotonic()
                status = rpi.execute(f"runuser -u hermes -- curl -s --max-time 30 {url}")[0]
                elapsed = time.monotonic() - start
                assert status == 56 and elapsed < 15, f"curl {status} po {elapsed:.1f} s: " + rpi.execute("journalctl -b -u 'laptop-llm@*' --no-pager | tail -5")[1]
          '';
        }
      );
    };
}
