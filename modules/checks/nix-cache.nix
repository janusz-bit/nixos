# Test VM cache'a Nix w tailnecie (rpi-nix-cache, hosts/nix-cache.nix): nginx
# oddaje nix-cache-info i pliki bez hasła, przyjmuje PUT tylko z hasłem
# z agenix (DELETE nie), nix-cache-push wysyła ścieżkę podpisaną kluczem CI,
# klient przyjmuje ją z tym kluczem i odrzuca z innym, ścieżki podpisane przez
# cache.nixos.org (także w domknięciu) i te, które cache już ma, nie są
# wysyłane, klient bierze z cache'a samą ścieżkę bez jej referencji, a
# nix-cache-gc usuwa stary narinfo, jego NAR dopiero w następnym przebiegu
# i nie rusza świeżego wpisu.
#
# Uruchomienie: nix build -L .#checks.<system>.nix-cache (wymaga kvm).
{
  self,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, self', ... }:
    let
      password = "test-password";
      # Sekret agenix testu budowany tutaj: klucz age i htpasswd zaszyfrowany
      # do niego (w repo nie ma klucza prywatnego).
      testSecret =
        pkgs.runCommand "nix-cache-test-secret"
          {
            nativeBuildInputs = [
              pkgs.age
              pkgs.openssl
            ];
          }
          ''
            mkdir "$out"
            age-keygen -o "$out/identity"
            printf 'ci:%s\n' "$(printf %s ${lib.escapeShellArg password} | openssl passwd -6 -stdin)" |
              age -r "$(age-keygen -y "$out/identity")" -o "$out/htpasswd.age"
          '';
      # Adresowane wejściem jak wyniki buildów: ścieżkę adresowaną treścią
      # (nix store add-file) Nix przyjmuje także bez podpisu.
      oldPath = pkgs.writeText "nix-cache-test-old" "old";
      freshPath = pkgs.writeText "nix-cache-test-fresh" "fresh";
      # topPath odwołuje się do upstreamPath, który test podpisuje kluczem
      # o nazwie cache.nixos.org-1.
      upstreamPath = pkgs.writeText "nix-cache-test-upstream" "upstream";
      topPath = pkgs.writeText "nix-cache-test-top" "${upstreamPath}";
    in
    {
      checks.nix-cache = pkgs.testers.runNixOSTest {
        name = "nix-cache";
        nodes.server = {
          imports = [
            self.modules.nixos.base-options
            inputs.agenix.nixosModules.default
            self.modules.nixos.rpi-nix-cache
          ];
          age = {
            identityPaths = [ "${testSecret}/identity" ];
            # mkForce: zastępuje plik z repo (rpi-nix-cache), którego klucz
            # testu nie odszyfruje.
            secrets.nix-cache-htpasswd.file = lib.mkForce "${testSecret}/htpasswd.age";
          };
          nix.settings.experimental-features = [ "nix-command" ];
          environment.systemPackages = [ self'.packages.nix-cache-push ];
          system.extraDependencies = [
            oldPath
            freshPath
            topPath
          ];
        };

        testScript =
          { nodes, ... }:
          let
            cfg = nodes.server;
            port = toString cfg.customBot.tailscaleServe.${toString cfg.customTop.nixCache.port}.port;
            inherit (cfg.systemd.services.nix-cache-gc.environment) NIX_CACHE_DIR RETENTION_DAYS;
          in
          ''
            cache = "http://127.0.0.1:${port}"
            files = "${NIX_CACHE_DIR}"
            expired = "${toString (lib.toInt RETENTION_DAYS + 1)} days ago"


            def status(args):
                return server.succeed(f"curl -s -o /dev/null -w '%{{http_code}}' {args}")


            def narinfo(path):
                return files + "/" + path.removeprefix("/nix/store/")[:32] + ".narinfo"


            def push(path):
                server.succeed(
                    f"NIX_CACHE_URL={cache} NIX_CACHE_SIGNING_KEY=\"$(cat /root/signing-key)\" "
                    f"NIX_CACHE_PUSH_PASSWORD=${password} nix-cache-push {path}"
                )
                return narinfo(path)


            def nar_of(narinfo):
                return files + "/" + server.succeed(f"sed -n 's/^URL: //p' {narinfo}").strip()


            start_all()
            server.wait_for_unit("nginx.service")
            server.wait_for_open_port(${port})

            with subtest("reads without a password, writes only PUT with one"):
                server.succeed(f"curl -sf {cache}/nix-cache-info | grep -x 'StoreDir: /nix/store'")
                assert status(f"-X PUT --data x {cache}/probe") == "401"
                assert status(f"-X PUT --data x -u ci:wrong {cache}/probe") == "401"
                assert status(f"-X PUT --data x -u ci:${password} {cache}/probe") == "201"
                assert status(f"-X DELETE -u ci:${password} {cache}/probe") == "405"
                server.succeed(f"test \"$(stat -c %U {files}/probe)\" = nginx")

            with subtest("push signs with the CI key, a client accepts only that key"):
                server.succeed("nix key generate-secret --key-name ci-test-1 > /root/signing-key")
                key = server.succeed("nix key convert-secret-to-public < /root/signing-key").strip()
                other = server.succeed(
                    "nix key generate-secret --key-name other-1 | nix key convert-secret-to-public"
                ).strip()
                old = "${oldPath}"
                old_narinfo = push(old)
                server.succeed(f"nix copy --from {cache} --to /root/good --trusted-public-keys '{key}' {old}")
                server.fail(f"nix copy --from {cache} --to /root/bad --trusted-public-keys '{other}' {old}")

            with subtest("push skips paths signed by cache.nixos.org, also in the closure"):
                server.succeed(
                    "nix key generate-secret --key-name cache.nixos.org-1 > /root/upstream-key && "
                    "nix store sign --key-file /root/upstream-key ${upstreamPath}"
                )
                server.succeed(f"test -e {push('${topPath}')}")
                server.fail("test -e " + narinfo("${upstreamPath}"))
                # Klient z referencją z innego źródła (u hostów cache.nixos.org)
                # bierze z cache'a samą podpisaną ścieżkę.
                server.succeed(
                    "nix copy --no-check-sigs --to /root/partial ${upstreamPath} && "
                    f"nix copy --no-recursive --from {cache} --to /root/partial "
                    f"--trusted-public-keys '{key}' ${topPath}"
                )
                out = server.succeed(
                    f"NIX_CACHE_URL={cache} NIX_CACHE_SIGNING_KEY=\"$(cat /root/signing-key)\" "
                    f"NIX_CACHE_PUSH_PASSWORD=${password} nix-cache-push ${topPath}"
                )
                assert "nothing to push" in out, out

            with subtest("gc: expired narinfo first, its NAR one run later, fresh entry stays"):
                fresh_narinfo = push("${freshPath}")
                old_nar = nar_of(old_narinfo)
                server.succeed(f"touch -d '{expired}' {old_narinfo} {old_nar}")
                # NAR starszy niż doba, ale z narinfo: zostaje.
                server.succeed(f"touch -d '2 days ago' {nar_of(fresh_narinfo)}")
                server.succeed("systemctl start nix-cache-gc.service")
                server.fail(f"test -e {old_narinfo}")
                server.succeed(f"test -e {old_nar}")
                server.succeed("systemctl start nix-cache-gc.service")
                server.fail(f"test -e {old_nar}")
                server.succeed(f"test -e {fresh_narinfo}")
                server.succeed(f"test -e {nar_of(fresh_narinfo)}")
          '';
      };
    };
}
