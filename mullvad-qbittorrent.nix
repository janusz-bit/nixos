# Mullvad VPN dla qbittorrent — WireGuard w osobnym network namespace
#
# Architektura:
#   - Tworzony jest netns "mullvad" z własnym routingiem
#   - WireGuard (klucze Mullvad) działa tylko w tym netns
#   - qbittorrent działa w tym netns — jeśli VPN padnie, ruch nie wycieknie
#   - WebUI dostępne z hosta/LAN przez veth pair
#
# Wymagania:
#   1. Pobierz konfig WireGuard z https://mullvad.net/account/wireguard
#   2. Utwórz sops-nix secret z private key:
#      W pliku secrets.yaml dodaj:
#        mullvad-wg-private-key: <twój_private_key_base64>
#      W konfiguracji sops dodaj:
#        "mullvad-wg-private-key" = { owner = "root"; mode = "0400"; };
#   3. Uzupełnij wartości poniżej z pobranego pliku konfiguracyjnego

{ config, pkgs, lib, ... }:

let
  # ====== KONFIGURACJA MULLVAD (uzupełnij z pobranego pliku) ======
  # [Interface] Address — adres w tunelu WireGuard
  wgAddress        = "10.71.x.x/32";

  # [Interface] PrivateKey — klucz prywatny (przez sops-nix)
  wgPrivateKeyFile = "/run/secrets/mullvad-wg-private-key";

  # [Peer] Endpoint — serwer Mullvad (wybierz blisko, np. SE/PL/DE)
  # Format: hostname:port (hostname zostanie rozwikłany na IP)
  wgEndpoint       = "se-sto-wg-001.relays.mullvad.net:51820";

  # [Peer] PublicKey — klucz publiczny serwera Mullvad
  wgPeerKey        = "MULLVAD_PEER_PUBLIC_KEY";

  # [Interface] DNS — serwer DNS Mullvad
  wgDns            = "10.64.0.1";

  # ====== KONFIGURACJA SIECI ======
  netnsName    = "mullvad";
  vethHost     = "veth-mv-h";        # interfejs po stronie hosta
  vethNs       = "veth-mv-n";        # interfejs po stronie netns
  vethHostCidr = "10.200.200.1/24";
  vethNsCidr   = "10.200.200.2/24";
  vethNsIp     = "10.200.200.2";      # pod tym IP dostępny jest WebUI

  # ====== KONFIGURACJA QBITTORRENT ======
  webuiPort    = 8080;

  # ====== Ścieżki do narzędzi ======
  ip = "${pkgs.iproute2}/bin/ip";
  wg = "${pkgs.wireguard-tools}/bin/wg";

  # ====== Skrypt uruchamiający ======
  setupScript = pkgs.writeScript "mullvad-netns-setup" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # 1. Utwórz namespace
    ${ip} netns add ${netnsName} 2>/dev/null || true

    # 2. DNS dla netns (bind-mountowane nad /etc/resolv.conf w namespace)
    mkdir -p /etc/netns/${netnsName}
    echo "nameserver ${wgDns}" > /etc/netns/${netnsName}/resolv.conf

    # 3. Loopback w netns
    ${ip} -n ${netnsName} link set lo up

    # 4. Veth pair: host <-> netns (dla dostępu do WebUI)
    ${ip} link add ${vethHost} type veth peer name ${vethNs} 2>/dev/null || true
    ${ip} link set ${vethNs} netns ${netnsName} 2>/dev/null || true
    ${ip} addr add ${vethHostCidr} dev ${vethHost} 2>/dev/null || true
    ${ip} -n ${netnsName} addr add ${vethNsCidr} dev ${vethNs} 2>/dev/null || true
    ${ip} link set ${vethHost} up
    ${ip} -n ${netnsName} link set ${vethNs} up

    # 5. Rozwikłaj hostname endpointa na IP (zanim wejdziemy do netns)
    ENDPOINT_HOST="${wgEndpoint%:*}"
    ENDPOINT_PORT="${wgEndpoint#*:}"
    ENDPOINT_IP=$(${pkgs.bind.dnsutils}/bin/dig +short "$ENDPOINT_HOST" | ${pkgs.gawk}/bin/awk 'NR==1{print; exit}')
    if [ -z "$ENDPOINT_IP" ]; then
      echo "BŁĄD: Nie udało się rozwiązać $ENDPOINT_HOST" >&2
      exit 1
    fi
    echo "Endpoint: $ENDPOINT_HOST -> $ENDPOINT_IP:$ENDPOINT_PORT"

    # 6. WireGuard w netns
    ${ip} -n ${netnsName} link add wg0 type wireguard
    ${ip} -n ${netnsName} addr add ${wgAddress} dev wg0
    ${ip} netns exec ${netnsName} ${wg} set wg0 \
      private-key ${wgPrivateKeyFile} \
      peer "${wgPeerKey}" \
      endpoint "''${ENDPOINT_IP}:''${ENDPOINT_PORT}" \
      allowed-ips 0.0.0.0/0 \
      persistent-keepalive 25
    ${ip} -n ${netnsName} link set wg0 up

    # 7. Default route przez VPN (kill switch: brak trasy = brak wycieku)
    ${ip} -n ${netnsName} route add default dev wg0

    echo "Mullvad VPN netns gotowy. WebUI: http://${vethNsIp}:${toString webuiPort}"
  '';

  # ====== Skrypt zamykający ======
  teardownScript = pkgs.writeScript "mullvad-netns-teardown" ''
    #!${pkgs.bash}/bin/bash
    set -e
    ${ip} link del ${vethHost} 2>/dev/null || true
    ${ip} netns del ${netnsName} 2>/dev/null || true
    rm -f /etc/netns/${netnsName}/resolv.conf
    rmdir /etc/netns/${netnsName} 2>/dev/null || true
  '';

in {
  # ====== Pakiety ======
  environment.systemPackages = with pkgs; [
    qbittorrent
    wireguard-tools
    iproute2
  ];

  # ====== Utworzenie netns + WireGuard ======
  systemd.services.mullvad-netns = {
    description = "Mullvad VPN network namespace for qbittorrent";
    wantedBy = [ "multi-user.target" ];
    before = [ "qbittorrent.service" ];
    path = with pkgs; [ iproute2 wireguard-tools bind.dnsutils gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = setupScript;
      ExecStop = teardownScript;
    };
  };

  # ====== qbittorrent w netns ======
  systemd.services.qbittorrent = {
    description = "qBittorrent (via Mullvad VPN namespace)";
    wantedBy = [ "multi-user.target" ];
    after = [ "mullvad-netns.service" " network.target" ];
    requires = [ "mullvad-netns.service" ];
    serviceConfig = {
      Type = "simple";
      User = "qbittorrent";
      Group = "qbittorrent";
      NetworkNamespacePath = "/var/run/netns/${netnsName}";
      ExecStart = "${pkgs.qbittorrent}/bin/qbittorrent-nox --webui-port=${toString webuiPort}";
      StateDirectory = "qbittorrent";
      WorkingDirectory = "/var/lib/qbittorrent";
      Restart = "on-failure";
      RestartSec = 5;
      # Bezpieczeństwo
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/qbittorrent" ];
      PrivateTmp = true;
    };
  };

  # ====== Użytkownik qbittorrent ======
  users.users.qbittorrent = {
    isSystemUser = true;
    group = "qbittorrent";
    home = "/var/lib/qbittorrent";
    createHome = true;
  };
  users.groups.qbittorrent = {};

  # ====== Forward WebUI z hosta do netns (dostęp z LAN) ======
  # socat przekazuje ruch z hosta:8080 do netns:8080
  systemd.services.mullvad-webui-forward = {
    description = "Forward WebUI port to Mullvad namespace";
    wantedBy = [ "multi-user.target" ];
    after = [ "mullvad-netns.service" ];
    requires = [ "mullvad-netns.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString webuiPort},fork,reuseaddr,bind=0.0.0.0 TCP:${vethNsIp}:${toString webuiPort}";
      Restart = "always";
      RestartSec = 3;
    };
  };

  # ====== Firewall: WebUI dostępny z LAN ======
  networking.firewall.allowedTCPPorts = [ webuiPort ];
}