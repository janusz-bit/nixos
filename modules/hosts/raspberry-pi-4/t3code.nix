# T3 Code (pingdotgg/t3code, pakiet z flake llm-agents): webowy interfejs do agentów
# kodujących (Claude Code, Codex, OpenCode), z telefonu przez aplikację T3 Code
# na Androida. t3 słucha tylko na 127.0.0.1:3773 i nie ma go w Cloudflare
# Tunnel: telefon dochodzi do niego lokalnym przekierowaniem portu SSH na konto
# t3-tunnel, przez ssh.<domena> (Cloudflare Access, cloudflared.nix) albo
# w domu z LAN-u.
#
# Granica zaufania:
# - t3-tunnel: konto systemowe bez powłoki (nologin) i bez grup; jedyny klucz
#   to keys.users.phone z from=<localhost, LAN>,restrict,port-forwarding, a blok
#   Match w sshd zostawia tylko lokalne przekierowanie do 127.0.0.1:3773 (bez
#   -R i bez gniazd Unix). Localhost, bo przez tunel sshd widzi połączenie
#   z cloudflared na RPi. Ten sam klucz loguje się dalej jako nixos (ssh.nix).
# - t3 wymaga parowania także od połączeń z 127.0.0.1: przy `--mode web --host
#   127.0.0.1` działa polityka "loopback-browser"
#   (apps/server/src/auth/EnvironmentAuthPolicy.ts w t3code), w której jedyną
#   drogą wejścia jest jednorazowy token parowania wymieniany na sesję. Bez
#   tokenu nie przejdą też inne konta RPi, które dosięgają 127.0.0.1:3773.
# - Serwer to agent z powłoką, więc działa jako osobny użytkownik t3code: bez
#   sudo, bez grup, bez sekretów i bez dostępu do /var/lib innych usług, z
#   zapisem tylko do własnego StateDirectory.
#
# Telefon: klucz phone należy do roota Debiana na telefonie (root@debian), więc
# tunel startuje `sudo ssh -N rpi-t3`, a wpis idzie do /root/.ssh/config
# (cloudflared w PATH roota):
#   Host rpi-t3
#     HostName ssh.<domena>
#     User t3-tunnel
#     ProxyCommand cloudflared access ssh --hostname %h
#     LocalForward 3773 127.0.0.1:3773
#     ExitOnForwardFailure yes
#     ServerAliveInterval 30
# W domu można zamiast tunelu podać HostName <IP RPi> bez ProxyCommand.
# Aplikacja łączy się z http://127.0.0.1:3773 na telefonie.
#
# Jednorazowo: logowanie Claude Code na koncie usługi
#   sudo -u t3code -H claude auth login
# Parowanie urządzenia (przy działającym tunelu): token ważny 5 minut, link
# /pair#token=… wklejony w aplikacji w "Add environment". Domyślny zakres to
# pełny dostęp, także terminal agenta, więc link traktuj jak hasło; węższy
# zakres dają powtórzone --scope.
#   sudo -u t3code -H env T3CODE_HOME=/var/lib/t3code \
#     t3 auth pairing create --base-url http://127.0.0.1:3773 --label telefon
# Sesje: ten sam prefiks z `t3 auth session list` / `t3 auth session revoke`
# (t3 jest w systemPackages).
#
# Pamięć: serwer Node plus agent to kilkaset MB przy 4 GB RAM RPi, razem
# z Nextcloudem i Hermesem; w razie presji pamięci zatrzymaj `t3code`.
#
# Sprawdzenie: `systemctl status t3code`, `journalctl -u t3code -b`,
# `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3773/` (200),
# `sudo sshd -T -C user=t3-tunnel,host=phone,addr=127.0.0.1 | grep -E 'allowtcpforwarding|permitopen|allowstreamlocal'`
# (local, 127.0.0.1:3773, no); z telefonu po `sudo ssh -N rpi-t3` aplikacja na
# http://127.0.0.1:3773 prosi o parowanie.
{ inputs, ... }:
{
  flake.modules.nixos.rpi-t3code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.customTop) keys lan;
      port = 3773;
      home = "/var/lib/t3code";
      tunnelUser = "t3-tunnel";
      t3code = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
    in
    {
      customBot.lockdownServices = [ "t3code" ];

      environment.systemPackages = [ t3code ];

      users = {
        users = {
          t3code = {
            isSystemUser = true;
            group = "t3code";
            inherit home;
            shell = pkgs.bashInteractive;
          };
          ${tunnelUser} = {
            isSystemUser = true;
            group = tunnelUser;
            description = "Przekierowanie portu z telefonu do T3 Code";
            openssh.authorizedKeys.keys = [
              ''from="127.0.0.1,::1,${lan.subnet}",restrict,port-forwarding ${keys.users.phone}''
            ];
          };
        };
        groups = {
          t3code = { };
          ${tunnelUser} = { };
        };
      };

      # mkAfter: wszystko po Match należy do bloku, a extraConfig idzie za
      # settings, więc blok musi zamykać sshd_config. `restrict` w kluczu nie
      # zawęża celu ani kierunku przekierowania — robi to dopiero ten blok.
      services.openssh.extraConfig = lib.mkAfter ''
        Match User ${tunnelUser}
          AllowTcpForwarding local
          AllowStreamLocalForwarding no
          PermitOpen 127.0.0.1:${toString port}
      '';

      systemd.services.t3code = {
        description = "T3 Code";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        # Dostawcy agentów t3 szuka w PATH.
        path = with pkgs; [
          claude-code
          git
          bashInteractive
        ];
        environment = {
          HOME = home;
          T3CODE_HOME = home;
        };
        serviceConfig = {
          ExecStart = "${lib.getExe' t3code "t3"} serve --mode web --host 127.0.0.1 --port ${toString port} --no-browser";
          User = "t3code";
          Group = "t3code";
          StateDirectory = "t3code";
          StateDirectoryMode = "0700";
          WorkingDirectory = home;
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
        };
      };
    };
}
