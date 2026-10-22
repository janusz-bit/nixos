# Przycisk awaryjny na czas CVE w usłudze sieciowej, zanim przyjdzie poprawka:
# `lockdown on` odcina od sieci wszystko poza SSH, `lockdown off` przywraca,
# `lockdown status` pokazuje stan. Opcjonalny: importują go nixos
# i raspberry-pi-4.
#
# Sieć dochodzi do hosta dwiema drogami i lockdown zamyka obie:
# - porty otwarte w firewallu (networking.firewall.allowed*, bez portów sshd
#   i portów przypiętych do interfejsu) dostają na początku łańcucha nixos-fw
#   regułę odrzucającą; to obejmuje też programy użytkownika (Steam Remote
#   Play) i usługi słuchające tylko na tych portach (avahi, cups-browsed);
# - usługi, do których sieć dochodzi inaczej (tunel Cloudflare, własne
#   połączenia wychodzące, radio), zatrzymuje systemd; każda z nich dopisuje
#   się do customBot.lockdownServices w swoim module.
# SSH zostaje: sshd, a na RPi także cloudflared, bo tunel niesie ssh.<domena>
# (jego backendy HTTP stoją, więc pozostałe nazwy dostają 502).
#
# Stan trzyma plik flagi, nie same jednostki. switch-to-configuration
# uruchamia ponownie aktywne targety, a boot multi-user.target, więc `update`
# albo restart po zaniku prądu podniósłby zatrzymane usługi. Dlatego usługi
# z listy mają ConditionPathExists=!flaga, a reguły firewalla dokłada
# extraCommands przy każdym starcie i reloadzie firewalla.
#
# Sprawdzenie: `lockdown status`, `sudo iptables -S nixos-fw | head`;
# test VM: `nix build -L .#checks.<system>.lockdown` (kvm).
_: {
  flake.modules.nixos.base-lockdown =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      flag = "/var/lib/network-lockdown";
      units = map (name: "${name}.service") config.customBot.lockdownServices;

      # Tylko porty globalne: networking.firewall.interfaces otwiera port na
      # jednym interfejsie — tu DNS sieci podman0 dla kontenerów, do którego
      # sieć z zewnątrz nie dochodzi, a jego zamknięcie odcięłoby im DNS.
      fw = config.networking.firewall;
      openPorts =
        proto:
        lib.unique (
          map toString fw."allowed${proto}Ports"
          ++ map (range: "${toString range.from}:${toString range.to}") fw."allowed${proto}PortRanges"
        );
      withProto =
        proto:
        map (port: {
          inherit proto port;
        });
      closedPorts =
        withProto "tcp" (lib.subtractLists (map toString config.services.openssh.ports) (openPorts "TCP"))
        ++ withProto "udp" (openPorts "UDP");
      closedSummary =
        if closedPorts == [ ] then
          "brak"
        else
          lib.concatMapStringsSep ", " ({ proto, port }: "${port}/${proto}") closedPorts;

      systemctlUnits =
        verb: lib.optionalString (units != [ ]) "systemctl ${verb} ${lib.escapeShellArgs units}";

      lockdown = pkgs.writeShellApplication {
        name = "lockdown";
        runtimeInputs = [
          pkgs.coreutils
          config.systemd.package
        ];
        text = ''
          flag=${lib.escapeShellArg flag}
          cmd=''${1:-}

          if [[ $cmd == on || $cmd == off ]] && ((EUID != 0)); then
            exec sudo "$0" "$@"
          fi

          show_status() {
            if [[ -e $flag ]]; then
              echo "lockdown: WŁĄCZONY od $(date -r "$flag" '+%F %T')"
            else
              echo "lockdown: wyłączony"
            fi
            echo "porty zamykane w firewallu:" ${lib.escapeShellArg closedSummary}
            ${systemctlUnits "list-units --all --no-pager"}
          }

          case $cmd in
            on)
              # Flaga przed stopem: od tej chwili nic nie podniesie usług z listy.
              touch "$flag"
              ${systemctlUnits "stop"}
              systemctl reload firewall.service
              show_status
              ;;
            off)
              rm -f "$flag"
              systemctl reload firewall.service
              ${systemctlUnits "start"}
              show_status
              ;;
            status)
              show_status
              ;;
            *)
              echo "użycie: lockdown on|off|status" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      assertions = [
        {
          assertion = fw.enable && !config.networking.nftables.enable;
          message = "base-lockdown zamyka porty regułami iptables (networking.firewall.extraCommands) i przeładowuje firewall.service: wymaga networking.firewall.enable = true bez networking.nftables.enable.";
        }
      ];

      environment.systemPackages = [ lockdown ];

      # Lista, nie napis: listy w unitConfig się sumują, więc warunek nie
      # koliduje z ConditionPathExists z modułu usługi.
      systemd.services = lib.genAttrs config.customBot.lockdownServices (_: {
        unitConfig.ConditionPathExists = [ "!${flag}" ];
      });

      # -I wstawia regułę przed ESTABLISHED,RELATED i przed akceptacją portów,
      # więc odcina też trwające połączenia na tych portach; `! -i lo` zostawia
      # połączenia lokalne. Pusty `if` byłby błędem składni, przez który
      # reload wyłącza cały firewall — stąd optionalString.
      networking.firewall.extraCommands = lib.optionalString (closedPorts != [ ]) ''
        if [ -e ${lib.escapeShellArg flag} ]; then
          ${lib.concatMapStringsSep "\n  " (
            { proto, port }: "ip46tables -I nixos-fw -p ${proto} --dport ${port} ! -i lo -j nixos-fw-log-refuse"
          ) closedPorts}
        fi
      '';
    };
}
