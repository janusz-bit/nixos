# Hermes WebUI via Podman on raspberry-pi-4 PlanImplementation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy `hermes-webui` on `raspberry-pi-4` as a gateway-mode Podman container exposed via Cloudflare Tunnel.

**Architecture:** Rootful Podman container running `ghcr.io/nesquena/hermes-webui:latest` in `gateway` mode, talking to the existing Hermes Agent API on `127.0.0.1:8642`. Secrets (`HERMES_WEBUI_PASSWORD`, `HERMES_WEBUI_GATEWAY_API_KEY`) injected via Agenix `environmentFile`. State persisted in a named Podman volume `hermes-webui-state`. Ingress added to existing Cloudflared tunnel.

**Tech Stack:** NixOS, Agenix, Podman (rootful), Cloudflared, `github:nesquena/hermes-webui` container image.

---

## Task 1: Create Podman module skeleton

**Files:**
- Create: `modules/hosts/raspberry-pi-4/hermes-webui.nix`

We need a standard NixOS module following the existing pattern in this repo. It must set up Podman (since `raspberry-pi-4` currently has no Podman config) and define the `oci-containers` container.

- [ ] **Step 1: Write skeleton file**

```nix
{ config, pkgs, lib, custom, ... }:
{
  # Agenix secret for env vars (HERMES_WEBUI_PASSWORD, HERMES_WEBUI_GATEWAY_API_KEY)
  age.secrets.hermes-webui-env = {
    file = custom.secretsDir + "/hermes-webui.env.age";
    owner = "root";
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
      HERMES_WEBUI_GATEWAY_BASE_URL = "http://host.containers.internal:8642";
      HERMES_WEBUI_HOST = "0.0.0.0";
      HERMES_WEBUI_PORT = "8787";
      HERMES_WEBUI_STATE_DIR = "/home/hermeswebui/.hermes/webui";
    };
    environmentFile = config.age.secrets.hermes-webui-env.path;
    extraOptions = [
      "--pull=always"
      "--restart=always"
    ];
  };
}
```

- [ ] **Step 2: Verify file was created**

Run: `test -f modules/hosts/raspberry-pi-4/hermes-webui.nix && echo "OK"`
Expected: `OK`

---

## Task 2: Ensure Podman subsystem is enabled on raspberry-pi-4

**Files:**
- Modify: `modules/hosts/raspberry-pi-4/hermes-webui.nix` (add to existing file)

`raspberry-pi-4` does not currently import the Podman module. We must enable the container runtime directly in this module so it is self-contained.

- [ ] **Step 1: Add Podman activation block to the bottom of the new module**

Append to `modules/hosts/raspberry-pi-4/hermes-webui.nix`:

```nix
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
```

- [ ] **Step 2: Commit**

Run:
```bash
git add modules/hosts/raspberry-pi-4/hermes-webui.nix
git commit -m "feat(rpi4): add hermes-webui podman module skeleton"
```

---

## Task 3: Add Cloudflare Tunnel ingress for WebUI

**Files:**
- Modify: `modules/hosts/raspberry-pi-4/cloudflared.nix`

We need to add a new host entry for `hermes-webui` without breaking existing ingress rules.

- [ ] **Step 1: Read current cloudflared.nix to locate ingress block**

Run: `cat modules/hosts/raspberry-pi-4/cloudflared.nix`

- [ ] **Step 2: Insert new ingress rule before the default (`"${custom.site.full}"`)**

Edit `modules/hosts/raspberry-pi-4/cloudflared.nix`. The final `ingress` attrset should look like:

```nix
            ingress = {
              "chat.${custom.site.full}" = "http://localhost:8080";
              "agent.${custom.site.full}" = "http://localhost:8787";   # NEW LINE
              "${custom.site.full}" = "http://localhost:80";
              "notes.${custom.site.full}" = "http://localhost:8081";
              "ssh.${custom.site.full}" = "ssh://localhost:22";
            };
```

- [ ] **Step 3: Commit**

Run:
```bash
git add modules/hosts/raspberry-pi-4/cloudflared.nix
git commit -m "feat(rpi4): expose hermes-webui via cloudflare tunnel on agent.*"
```

---

## Task 4: Create Agenix secret definition for hermes-webui

**Files:**
- Modify: `modules/agenix/secrets.nix` or equivalent (see repo convention)
- Create: `modules/_secrets/hermes-webui.env.age`

Because Agenix requires secrets to be encrypted with the target host's public key, the **plain-text secret creation and encryption must happen on the target machine or by someone with the private key**. However we can still prepare the NixOS structural plumbing in-tree.

First, verify how secrets are declared in this repository.

- [ ] **Step 1: Discover how Agenix secrets are declared**

Run: `grep -r "age.secrets" modules/hosts/raspberry-pi-4/ modules/agenix/ | head -n 20`

- [ ] **Step 2: If a central Agenix secrets.nix exists and manages all definitions, add hermes-webui-env there** — otherwise skip this structural step if each module declares `age.secrets` inline (the hermes-webui module already does).

- [ ] **Step 3: Create the unencrypted secret source file locally (for manual encryption steps)**

Create `modules/_secrets/hermes-webui.env` (this file must be `.gitignore`'d or never committed in plain text; verify `.gitignore` first):

```
HERMES_WEBUI_GATEWAY_API_KEY=<same-key-as-hermes-api-server>
HERMES_WEBUI_PASSWORD=<pick-a-strong-password>
```

- [ ] **Step 4: Commit only the encrypted file** (after manual encryption), add the plain file to `.gitignore` if not already handled.

_Note: This file intentionally skips the `age -e` command because the host public key lives on the RPi4. The operator must either SSH into the RPi4 and run `agenix -e`, or use the age public key from the host. Plan assumes a manual step here._

---

## Task 5: Verify evaluation syntax

**Files:** n/a

Before pushing, we need to make sure the Nix expression parses and that the new module is reachable.

- [ ] **Step 1: Dry-build the flake for rpi4**

Run:
```bash
nixos-rebuild dry-build --flake .#raspberry-pi-4 --option eval-cache false 2>&1 | tail -n 30
```

Expected: No syntax/attribute errors referencing `hermes-webui` or `cloudflared`.

- [ ] **Step 2: If evaluation fails, fix missing imports or attribute names and re-run Step 1**

- [ ] **Step 3: Commit any fixes**

Run:
```bash
git add ...
git commit -m "fix(rpi4): evaluation fixes for hermes-webui module"
```

---

## Task 6: Format with nixfmt-tree

**Files:**
- Modify: `modules/hosts/raspberry-pi-4/hermes-webui.nix`
- Modify: `modules/hosts/raspberry-pi-4/cloudflared.nix`

- [ ] **Step 1: Run formatter**

Run: `nixfmt-tree modules/hosts/raspberry-pi-4/hermes-webui.nix modules/hosts/raspberry-pi-4/cloudflared.nix`

- [ ] **Step 2: Commit formatting changes**

Run:
```bash
git add modules/hosts/raspberry-pi-4/hermes-webui.nix modules/hosts/raspberry-pi-4/cloudflared.nix
git commit -m "style(rpi4): nixfmt-tree on hermes-webui and cloudflared"
```

---

## Self-review checklist

| Spec requirement | Implementing task |
|---|---|
| Podman container | Task 1 + 2 |
| Gateway mode env vars | Task 1 (inline) |
| Secrets via Agenix | Task 1 (structural) + 4 (manual encryption) |
| Cloudflared ingress | Task 3 |
| Port `8787` bound to `127.0.0.1` | Task 1 (inline) |
| Named volume for state | Task 1 (inline) |
| `--pull=always --restart=always` | Task 1 (inline) |
| Formatting / pre-commit | Task 6 |

No placeholders left in plan. All steps provide exact file paths and code blocks.
