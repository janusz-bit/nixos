# Hermes WebUI via Podman on raspberry-pi-4

## Context

The `raspberry-pi-4` host already runs:

- `services.hermes-agent` (gateway API server on `127.0.0.1:8642`).
- `services.ollama` (also on `127.0.0.1`, cloud provider via `OLLAMA_API_KEY`).
- Cloudflared exposing services externally.

Goal: add `hermes-webui` to this host as a lightweight **gateway-mode** frontend.

## Decision records

| Topic | Decision | Rationale |
|---|---|---|
| Runtime | Podman container via `virtualisation.oci-containers` | “Użyj podman container” — user request. Matches workstation pattern (`nixos/podman.nix`). |
| Agent mode | `HERMES_WEBUI_CHAT_BACKEND=gateway` | Avoid in-process Hermes agent on RPi4; reuse existing API server on port 8642. |
| Image source | `ghcr.io/nesquena/hermes-webui:latest` | Upstream publishes `arm64`/`amd64` multi-arch images. |
| UID mapping | Named volume for `webui_state` + bind `/tmp/.hermes` | Per docs “named Docker volumes solve UID/GID by construction”. |
| Secrets | `hermes-webui.env` via Agenix | Keeps `HERMES_WEBUI_PASSWORD`, `HERMES_WEBUI_GATEWAY_API_KEY` off disk. |
| Auth | Password auth required (`HERMES_WEBUI_PASSWORD`) | Because host will be exposed via Cloudflare. |

## Architecture

```
┌─────────────────────────────┐
│   Cloudflare Tunnel         │
│   hermes-webui.site.full    │
└────────────┬────────────────┘
             │
┌────────────▼────────────────┐
│   Podman container          │
│   hermes-webui            │
│   :8787 (podman-bridge)     │
└────────────┬────────────────┘
             │
┌────────────▼────────────────┐
│   Hermes Agent gateway      │
│   http://127.0.0.1:8642     │
└─────────────────────────────┘
```

## Files touched

| File | Change |
|---|---|
| `modules/hosts/raspberry-pi-4/hermes-webui.nix` | **new** — Podman service definition + Agenix secret |
| `modules/hosts/raspberry-pi-4/cloudflared.nix` | add `hermes-webui` ingress rule |
| `modules/hosts/raspberry-pi-4/default.nix` | import new module (implicitly via `import-tree`, but verify naming) |
| `modules/agenix/` | create `hermes-webui.env.age` + add public key for RPi4 |

## New module: `modules/hosts/raspberry-pi-4/hermes-webui.nix`

```nix
{ config, pkgs, lib, custom, ... }:
{
  age.secrets.hermes-webui-env = {
    file = custom.secretsDir + "/hermes-webui.env.age";
    owner = "root";   # podman rootful container reads it
    group = "root";
    mode = "0400";
  };

  virtualisation.oci-containers.containers.hermes-webui = {
    autoStart = true;
    image = "ghcr.io/nesquena/hermes-webui:latest";
    ports = [ "127.0.0.1:8787:8787" ];
    volumes = [
      "hermes-webui-state:/home/hermeswebui/.hermes/webui"
    ];
    environment = {
      HERMES_WEBUI_CHAT_BACKEND = "gateway";
      HERMES_WEBUI_GATEWAY_BASE_URL = "http://127.0.0.1:8642";
      HERMES_WEBUI_HOST = "0.0.0.0";   # 0.0.0.0 inside container
      HERMES_WEBUI_PORT = "8787";
      HERMES_WEBUI_STATE_DIR = "/home/hermeswebui/.hermes/webui";
      # API key & password come from environmentFile
    };
    environmentFile = config.age.secrets.hermes-webui-env.path;
    extraOptions = [
      "--pull=always"
      "--restart=always"
    ];
  };

  # Ensure podman is enabled (should already be on rpi if it follows nixos pattern,
  # but adding here explicitly since rpi-4 currently has no podman module.)
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
}
```

## Cloudflared adjustment

Add inside the `ingress` attr:

```nix
"agent.${custom.site.full}" = "http://localhost:8787";
```

(Using `agent.` to avoid collision with `chat.` which points to Open WebUI on `8080`.)

## Agenix secret content (`hermes-webui.env`)

Format is `KEY=VALUE` lines:

```
HERMES_WEBUI_GATEWAY_API_KEY=sk-...
HERMES_WEBUI_PASSWORD=...
```

## Risks / follow-ups

1. `latest` tag drift — if upstream pushes breaking release, container auto-pulls on next start. Consider pinning to a digest or release tag after initial deploy.
2. The RPi4 does not yet have `virtualisation.podman.enabled`. Our new module turns it on. Verify `containers.enable` doesn’t conflict with any existing Docker setup (none found).
3. Agenix public key must be updated to re-encrypt `hermes-webui.env.age` for the `raspberry-pi-4` host key.
