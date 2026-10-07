_: {
  flake.modules.nixos.trilium = _: {
    services.trilium-server = {
      enable = true;
      port = 8081;
      # installPhase z nixpkgs uzywa juz `rm -f .../linuxmusl-*.node`
      # (delete-if-present), wiec lokalne overrideAttrs jest zbedne.
      # Bylo potrzebne tylko dla nixpkgs z bezwarunkowym `rm` -
      # patrz temporary-fixes.md (pozycja zamknieta).
    };

    systemd.services.trilium-server = {
      # Ruch przychodzi wyłącznie z cloudflared (127.0.0.1). Bez zaufania do
      # tego jednego przeskoku req.ip = 127.0.0.1 dla wszystkich: wspólny
      # limit logowań (10 prób / 15 min) — bot blokował właściciela i
      # synchronizację — i brak prawdziwych IP w logach. „loopback” ufa tylko
      # proxy na pętli zwrotnej.
      environment.TRILIUM_NETWORK_TRUSTEDREVERSEPROXY = "loopback";
      serviceConfig = {
        # Moduł zostawia Restart=no: po awarii notes.* i endpoint MCP dla
        # agentów leżały do restartu systemu.
        Restart = "on-failure";
        RestartSec = "5s";
        # Moduł ustawia tylko User/Group/PrivateTmp, a to usługa z internetu.
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/trilium" ];
        ProtectHome = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        # AF_NETLINK: os.networkInterfaces() (getifaddrs) w /api/network-addresses
        # panelu MCP; zmiany przez netlink i tak wymagają CAP_NET_ADMIN.
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        SystemCallErrorNumber = "EPERM";
        UMask = "0077";
        # MemoryDenyWriteExecute celowo wyłączone: JIT V8.
      };
    };
  };
}
