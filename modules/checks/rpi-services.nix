# Testy VM usług raspberry-pi-4 wystawionych przez tunel — prawdziwe moduły
# repo (self.modules.nixos.*), nie kopie konfiguracji:
#   - ttyd: agenix -> LoadCredential -> htpasswd -> nginx Basic Auth -> gniazdo
#     UNIX dostępne tylko dla nginx, --check-origin, limit żądań,
#   - trilium-server: start i zapis bazy w sandboxie systemd, zaufane proxy,
#   - pwm-fan: sterowanie linią GPIO14 w sandboxie (gpio-mockup udaje
#     /dev/gpiochip0) i pełne obroty bez czujnika temperatury,
#   - cloudflared: utwardzona jednostka startuje bez błędów uprawnień
#     (fałszywe poświadczenia, VM bez sieci — tunel się nie zestawi).
# Sekret ttyd szyfrowany kluczem age wygenerowanym przy budowie testu (nie
# kluczami hostów), więc test nie zależy od modules/_secrets.
#
# Uruchomienie: nix build .#checks.<system>.rpi-services (wymaga kvm).
{ inputs, self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      password = "test-password";
      testSecret = pkgs.runCommand "ttyd-test-secret" { nativeBuildInputs = [ pkgs.age ]; } ''
        mkdir $out
        age-keygen -o $out/identity 2>/dev/null
        printf '%s' ${password} | age -a -r "$(age-keygen -y $out/identity)" -o $out/ttyd-password.age
      '';
      cloudflaredCredentials =
        pkgs.runCommand "cloudflared-test-credentials"
          {
            nativeBuildInputs = [ pkgs.age ];
          }
          ''
            mkdir $out
            printf '%s' '{"AccountTag":"0","TunnelSecret":"AAAA","TunnelID":"00000000-0000-0000-0000-000000000000"}' \
              | age -a -r "$(age-keygen -y ${testSecret}/identity)" -o $out/credentials.age
          '';
      host = "ttyd.janusz-bit.com";
    in
    {
      # Logika sterownika wentylatora (histereza, awaria czujnika = 100%).
      checks.pwm-fan = pkgs.runCommand "pwm-fan-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        cd ${../hosts/raspberry-pi-4/_pwm-fan}
        python3 -B -m unittest -v test_pwm_fan
        touch $out
      '';

      checks.rpi-services = pkgs.testers.runNixOSTest {
        name = "rpi-services";
        nodes.machine =
          { lib, ... }:
          {
            imports = [
              inputs.agenix.nixosModules.default
              self.modules.nixos.ttyd
              self.modules.nixos.trilium
              self.modules.nixos.pwm-fan
              self.modules.nixos.cloudflared
            ];
            age = {
              identityPaths = lib.mkForce [ "${testSecret}/identity" ];
              secrets = {
                ttyd-password.file = lib.mkForce "${testSecret}/ttyd-password.age";
                cloudflared-tunnel.file = lib.mkForce "${cloudflaredCredentials}/credentials.age";
              };
            };
            # Wirtualny kontroler GPIO w miejsce BCM2835.
            boot.kernelModules = [ "gpio-mockup" ];
            boot.extraModprobeConfig = "options gpio-mockup gpio_mockup_ranges=-1,32";
            environment.systemPackages = [ pkgs.libgpiod ];
            users.users.alice.isNormalUser = true;
            virtualisation.memorySize = 1536;
          };

        testScript = ''
          machine.wait_for_unit("nginx.service")
          machine.wait_for_unit("ttyd.service")
          machine.wait_for_unit("trilium-server.service")

          # curl exits 28 when an upgraded WebSocket idles until --max-time;
          # the status code has been printed by then, hence `|| true`.
          def code(args, path="/"):
              return machine.succeed(
                  f"curl -s -o /dev/null -w '%{{http_code}}' --max-time 3 -H 'Host: ${host}' {args} http://127.0.0.1:8083{path} || true"
              ).strip()

          with subtest("ttyd listens only on a socket that only nginx may open"):
              machine.fail("ss -ltnp | grep -q ttyd")
              assert machine.succeed("stat -c '%U:%G %a' /run/ttyd").strip() == "root:nginx 750"
              sock = machine.succeed("stat -c '%U:%G %a %F' /run/ttyd/ttyd.sock").strip()
              assert sock == "root:nginx 660 socket", sock
              machine.fail("su alice -s /bin/sh -c 'curl -s --max-time 3 --unix-socket /run/ttyd/ttyd.sock http://x/'")

          with subtest("htpasswd holds only a SHA-512-crypt hash, readable by nginx"):
              machine.succeed("grep -q '^admin:\\$6\\$' /run/ttyd-auth/htpasswd")
              machine.fail("grep -q ${password} /run/ttyd-auth/htpasswd")
              assert machine.succeed("stat -c '%U:%G %a' /run/ttyd-auth/htpasswd").strip() == "root:nginx 640"

          with subtest("nginx Basic Auth guards the terminal"):
              assert code("") == "401"
              assert code("-u admin:wrong") == "401"
              assert code("-u admin:${password}") == "200"

          # Losowy Sec-WebSocket-Key jak u prawdziwego klienta (RFC 6455).
          import base64, os
          ws_key = base64.b64encode(os.urandom(16)).decode()
          ws = ("-u admin:${password} -H 'Connection: Upgrade' -H 'Upgrade: websocket' "
                f"-H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: {ws_key}' "
                "-H 'Sec-WebSocket-Protocol: tty'")

          with subtest("ttyd rejects WebSockets from a foreign Origin"):
              evil = code(f"{ws} -H 'Origin: https://evil.example'", "/ws")
              assert evil != "101", evil
              good = code(f"{ws} -H 'Origin: https://${host}'", "/ws")
              assert good == "101", good

          with subtest("Basic Auth is rate limited"):
              codes = [code("-u admin:wrong") for _ in range(30)]
              assert "429" in codes, codes

          with subtest("pwm-fan drives GPIO14 from its sandbox, full speed without a sensor"):
              # QEMU virt (aarch64) ma własny PL061 jako gpiochip0; wtedy drop-in
              # w /run podmienia tylko numer chipu — sandbox zostaje produkcyjny.
              detect = machine.succeed("gpiodetect")
              chip = next(l.split()[0] for l in detect.splitlines() if "gpio-mockup" in l)
              if chip != "gpiochip0":
                  num = chip.removeprefix("gpiochip")
                  machine.succeed(
                      "mkdir -p /run/systemd/system/pwm-fan.service.d && "
                      f"printf '[Service]\\nEnvironment=RPI_LGPIO_CHIP={num}\\nDeviceAllow=/dev/{chip} rw\\n' "
                      "> /run/systemd/system/pwm-fan.service.d/chip.conf && "
                      "systemctl daemon-reload && systemctl restart pwm-fan"
                  )
              machine.wait_for_unit("pwm-fan.service")
              pid = machine.succeed("systemctl show -p MainPID --value pwm-fan").strip()
              machine.sleep(8)
              assert machine.succeed("systemctl show -p MainPID --value pwm-fan").strip() == pid, "pwm-fan restarted"
              machine.succeed(f"gpioinfo -c {chip} 14 | grep -q output")
              machine.succeed("journalctl -u pwm-fan -b | grep -q 'unreadable, fan at 100%'")
              machine.fail("ls /.lgd-nfy* 2>/dev/null")
              assert "UNSAFE" not in machine.succeed("systemd-analyze security pwm-fan --no-pager | tail -1")

          with subtest("hardened cloudflared starts without permission errors"):
              unit = "cloudflared-tunnel-raspberry-pi-4"
              machine.wait_until_succeeds(f"journalctl -u {unit} -b | grep -q cloudflared", timeout=60)
              machine.sleep(10)
              journal = machine.succeed(f"journalctl -u {unit} -b")
              for bad in ["operation not permitted", "permission denied", "status=31/sys", "core-dump"]:
                  assert bad not in journal.lower(), f"{bad}: {journal[-2000:]}"

          with subtest("trilium serves and writes its database inside the sandbox"):
              machine.wait_until_succeeds("curl -sf -o /dev/null http://127.0.0.1:8081/", timeout=180)
              machine.wait_until_succeeds("test -s /var/lib/trilium/document.db", timeout=120)
              machine.succeed("journalctl -u trilium-server -b | grep -q 'Trusted reverse proxy: loopback'")
              assert machine.succeed("systemctl show -p NRestarts --value trilium-server").strip() == "0"
              machine.fail("journalctl -u trilium-server -b | grep -qi 'operation not permitted'")
        '';
      };
    };
}
