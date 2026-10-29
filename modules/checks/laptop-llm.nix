# Test VM laptop-llm (modules/hosts/laptop-llm.nix): pierwsze żądanie konta
# hermes z „RPi” uruchamia na „laptopie” Stratę dla Hermesa (run config
# odtworzony z ustawieniami modelu z ai.models i z --kv-resident; config
# z innym KV jest odtwarzany, zgodny zostaje), po bezczynności proxy i Strata
# się zatrzymują, a przy zajętym dGPU żądanie kończy się szybko i gniazdo
# zostaje sprawne. Inne konto RPi dostaje odmowę; klucz tunelu nie daje na
# laptopie przekierowania do innego portu, -R, gniazd Unix ani polecenia;
# reguła iptables przeżywa reload firewalla bez mnożenia się, a przy
# nieosiągalnym laptopie połączenie kończy się w czasie ConnectTimeout.
#
# Moduły są prawdziwe. Testowy customTop podmienia tylko klucze na snakeoil
# z nixpkgs (prywatna część keys.users.hermes-llm jest sekretem). Atrapy:
# `strata` (pakiet lokalny tylko x86_64, model ok. 90 GB) trzyma się kontraktu
# setup.py — `install` pisze strata-coder-<rozmiar>.json z --max-context i --kv
# w args, `serve` bez niego odmawia — i serwuje pliki przez http.server;
# `nvidia-smi` czyta zajętość VRAM
# z /run/fake-vram-used.
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

      fakeStrata =
        final:
        final.writeShellApplication {
          name = "strata";
          runtimeInputs = [
            final.coreutils
            final.python3
          ];
          text = ''
            install_dir=$HOME/.local/share/strata/install
            case $1 in
              install)
                echo "$*" >> "$HOME/install-args"
                while (($#)); do
                  [[ $1 == --model ]] && model=$2
                  [[ $1 == --context ]] && context=$2
                  [[ $1 == --kv ]] && kv=$2
                  shift
                done
                mkdir -p "$install_dir"
                printf '{"args": ["--max-context", "%s", "--kv", "%s"]}\n' "$context" "$kv" \
                  > "$install_dir/strata-coder-''${model,,}.json"
                ;;
              serve)
                while (($#)); do
                  [[ $1 == --config ]] && config=$2
                  [[ $1 == --port ]] && port=$2
                  shift
                done
                [[ -e $config ]]
                exec python3 -m http.server --bind 127.0.0.1 --directory ${
                  final.linkFarm "strata-fake-www" {
                    marker = final.writeText "marker" "laptop-llm-ok\n";
                    health = final.writeText "health" "ok\n";
                  }
                } "$port"
                ;;
            esac
          '';
        };

      fakeNvidiaSmi = pkgs.writeShellApplication {
        name = "nvidia-smi";
        text = "cat /run/fake-vram-used";
      };
    in
    {
      checks.laptop-llm = pkgs.testers.runNixOSTest (
        { nodes, ... }:
        let
          listen = lib.head nodes.rpi.systemd.sockets.laptop-llm.listenStreams;
          strataArgs = lib.splitString " " nodes.laptop.systemd.services.strata-hermes.serviceConfig.ExecStart;
          runConfig = lib.elemAt strataArgs (
            lib.lists.findFirstIndex (arg: arg == "--config") null strataArgs + 1
          );
          inherit (nodes.laptop.ai.models.qwen3-8-flash-next-coder-iq1_m) context;
          port = lib.toInt (lib.last (lib.splitString ":" listen));
          otherPort = port + 1;
        in
        {
          name = "laptop-llm";
          # Węzeł laptop dokłada overlay z atrapą strata.
          node.pkgsReadOnly = false;
          nodes = {
            laptop = {
              imports = [
                testTop
                self.modules.nixos.ai-options
                self.modules.nixos.ai-models
                self.modules.nixos.nixos-laptop-llm
                (lanAddress lan.laptop)
              ];
              nixpkgs.overlays = [ (final: _: { strata = fakeStrata final; }) ];
              # Moduł bierze nvidia-smi z wyjścia `bin` pakietu sterownika.
              hardware.nvidia.package = fakeNvidiaSmi // {
                bin = fakeNvidiaSmi;
              };
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
                tmpfiles.rules = [ "f /run/fake-vram-used 0644 root root - 44" ];
                services = {
                  # 15 min bezczynności to za długo na test.
                  strata-hermes-proxy.environment.STRATA_HERMES_IDLE = lib.mkForce "3s";
                  other = {
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      ExecStart = "${lib.getExe pkgs.python3} -m http.server --bind 127.0.0.1 --directory ${pkgs.writeTextDir "marker" "other-port"} ${toString otherPort}";
                      DynamicUser = true;
                    };
                  };
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
            import json
            import shlex
            import time

            url = "http://${listen}/marker"
            ssh = "ssh -F /dev/null -i /root/test-key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null hermes-llm@${lan.laptop}"
            request = "printf 'GET /marker HTTP/1.0\\r\\n\\r\\n'"

            def access_holds():
                assert "laptop-llm-ok" in rpi.succeed(f"runuser -u hermes -- curl -sf --max-time 30 {url}")
                # 7: odmowa połączenia (REJECT), a nie błąd po drugiej stronie
                assert rpi.execute(f"runuser -u nobody -- curl -s --max-time 5 {url}")[0] == 7

            def setup_runs():
                return laptop.succeed("cat /var/lib/strata/install-args").splitlines()

            def config_args():
                return json.loads(laptop.succeed("cat ${runConfig}"))["args"]

            def strata_stops():
                laptop.wait_until_fails("systemctl is-active strata-hermes-proxy.service", timeout=30)
                laptop.wait_until_fails("systemctl is-active strata-hermes.service", timeout=30)
                laptop.succeed("systemctl is-active strata-hermes-proxy.socket")

            start_all()
            laptop.wait_for_unit("sshd.service")
            laptop.wait_for_unit("strata-hermes-proxy.socket")
            laptop.wait_for_open_port(${toString otherPort}, "127.0.0.1")
            rpi.wait_for_unit("laptop-llm.socket")
            rpi.wait_for_unit("multi-user.target")
            rpi.succeed("install -D -m 0400 ${snakeOil.snakeOilEd25519PrivateKey} ${nodes.rpi.age.secrets.hermes-llm-key.path}")
            rpi.succeed("install -m 0400 ${snakeOil.snakeOilEd25519PrivateKey} /root/test-key")

            with subtest("the first hermes request starts Strata, other accounts are refused"):
                laptop.fail("systemctl is-active strata-hermes.service")
                access_holds()
                laptop.succeed("systemctl is-active strata-hermes.service")
                runs = setup_runs()
                assert len(runs) == 1 and "--context ${toString context} --kv int8 --vision no" in runs[0], runs
                args = config_args()
                assert args[args.index("--kv-resident") + 1] == "20480", args

            with subtest("idle: the proxy exits and Strata stops with it"):
                strata_stops()

            with subtest("a run config with other KV is rebuilt, a matching one is kept"):
                other = json.dumps({"args": ["--max-context", "${toString context}", "--kv", "q4_0"]})
                laptop.succeed(f"printf %s {shlex.quote(other)} | runuser -u strata -- tee ${runConfig} >/dev/null")
                access_holds()
                assert len(setup_runs()) == 2
                args = config_args()
                assert args[args.index("--kv") + 1] == "int8" and "--kv-resident" in args, args
                strata_stops()
                access_holds()
                assert len(setup_runs()) == 2
                strata_stops()

            with subtest("busy dGPU: the request ends fast and the socket stays usable"):
                laptop.succeed("echo 4000 > /run/fake-vram-used")
                start = time.monotonic()
                status = rpi.execute(f"runuser -u hermes -- curl -s --max-time 30 {url}")[0]
                elapsed = time.monotonic() - start
                # 52/56: połączenie zamknięte bez odpowiedzi; 28 znaczyłoby zawieszenie
                assert status in (52, 56) and elapsed < 15, f"curl {status} po {elapsed:.1f} s"
                laptop.succeed("journalctl -b -u strata-hermes.service | grep -q 'dGPU zajęte'")
                strata_stops()
                laptop.succeed("echo 44 > /run/fake-vram-used")
                access_holds()
                strata_stops()

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
