# Test VM kopii modułu hermes-agent (modules/hosts/raspberry-pi-4/_hermes-agent):
# aktywacja nie może pisać jako root przez ścieżki, które konto hermes
# podmienia na symlinki (upstream: stateDir/home -> /etc dawało roota przy
# najbliższym switch/boot). Pakiet hermes zastępuje atrapa — aktywacja
# potrzebuje z niego tylko hermesVenv z hermes_cli.config_defaults.
#
# Uruchomienie: nix build .#checks.<system>.hermes-activation (wymaga kvm).
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      configDefaults = pkgs.writeTextDir "lib/hermes_cli/config_defaults.py" ''
        DEFAULT_CONFIG = {"_config_version": 99}
      '';
      hermesVenv = pkgs.writeShellScriptBin "python3" ''
        PYTHONPATH=${configDefaults}/lib exec ${pkgs.python3}/bin/python3 "$@"
      '';
      # Bramka „hermes gateway” tylko czeka — test dotyczy aktywacji.
      stubPackage = (pkgs.writeShellScriptBin "hermes" "exec sleep infinity").overrideAttrs {
        passthru = { inherit hermesVenv; };
      };
      stubPlugin = pkgs.runCommand "stub-plugin" { } ''
        mkdir $out
        echo "name: stub" > $out/plugin.yaml
      '';
    in
    {
      checks.hermes-activation = pkgs.testers.runNixOSTest {
        name = "hermes-activation";
        nodes.machine = {
          imports = [
            (import ../hosts/raspberry-pi-4/_hermes-agent/nixos-module.nix {
              inputs.self = inputs.hermes-agent;
            }).flake.nixosModules.default
          ];
          services.hermes-agent = {
            enable = true;
            package = stubPackage;
            settings.model.default = "from-nix";
            environmentFiles = [ "/run/hermes-test.env" ];
            extraPlugins = [ stubPlugin ];
          };
        };

        testScript = ''
          home = "/var/lib/hermes/.hermes"
          activate = "/run/current-system/activate"

          def as_hermes(cmd):
              return machine.succeed(f"setpriv --reuid=hermes --regid=hermes --init-groups -- sh -c '{cmd}'")

          def owner_mode(path):
              return machine.succeed(f"stat -c '%U:%G %a' {path}").strip()

          machine.wait_for_unit("multi-user.target")

          with subtest("normal activation: state files owned by the service"):
              machine.succeed("install -o hermes -g hermes -m 0400 /dev/null /run/hermes-test.env")
              machine.succeed("echo TEST_SECRET=s3cret > /run/hermes-test.env")
              # config.yaml left behind by another user (old CLI run as nixos)
              machine.succeed(f"install -o root -g hermes -m 0660 /dev/null {home}/config.yaml")
              machine.succeed(f"echo 'user_key: kept' > {home}/config.yaml")
              machine.succeed(activate)
              assert owner_mode(f"{home}/config.yaml") == "hermes:hermes 640", owner_mode(f"{home}/config.yaml")
              cfg = machine.succeed(f"cat {home}/config.yaml")
              assert "user_key: kept" in cfg and "from-nix" in cfg, cfg
              assert owner_mode(f"{home}/.env") == "hermes:hermes 640"
              machine.succeed(f"grep -qx TEST_SECRET=s3cret {home}/.env")
              machine.succeed(f"test -L {home}/plugins/nix-managed-stub-plugin")
              assert owner_mode("/var/lib/hermes") == "hermes:hermes 2770"

          # Each vector alone, so every code path that could follow it is reached.
          vectors = [
              ("/var/lib/hermes/home", "/target-home", "dir"),
              ("/var/lib/hermes/workspace", "/target-workspace", "dir"),
              (f"{home}/cron", "/target-cron", "dir"),
              (f"{home}/plugins", "/target-plugins", "dir"),
              (f"{home}/config.yaml", "/target-config", "file"),
              (f"{home}/.env", "/target-env", "file"),
          ]
          for link, target, kind in vectors:
              with subtest(f"symlink {link} -> {target} is never followed by root"):
                  if kind == "dir":
                      machine.succeed(f"mkdir -m 0755 {target}")
                  else:
                      # world-readable: the service may read it, so the deepest path runs
                      machine.succeed(f"install -m 0644 /dev/null {target} && echo original > {target}")
                  as_hermes(f"rm -rf {link} && ln -s {target} {link}")
                  machine.execute(activate)  # may fail on the refused path; root effects matter
                  mode = "755" if kind == "dir" else "644"
                  assert owner_mode(target) == f"root:root {mode}", f"{target}: {owner_mode(target)}"
                  machine.succeed(f"test -z \"$(find {target} -mindepth 1 2>/dev/null)\"" if kind == "dir"
                                  else f"grep -qx original {target}")
                  # restore a real path for the next vector
                  as_hermes(f"rm -f {link}")
                  if kind == "dir":
                      as_hermes(f"mkdir {link}")
                  machine.succeed(activate)

          with subtest("activation is clean again after the attack"):
              machine.succeed(activate)
              assert owner_mode(f"{home}/config.yaml") == "hermes:hermes 640"
              machine.succeed(f"grep -qx TEST_SECRET=s3cret {home}/.env")
        '';
      };
    };
}
