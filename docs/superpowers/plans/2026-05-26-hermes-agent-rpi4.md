# Hermes Agent on RPi4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hermes-agent as a declarative NixOS service on raspberry-pi-4 using native mode with Ollama Cloud API and Signal.

**Architecture:** New host-level nixosModule `raspberry-pi-4/hermes` following existing pattern (one file per service). Agenix secret for API keys. No container mode to save RAM.

**Tech Stack:** NixOS module system, agenix, hermes-agent flake input

---

### Task 1: Create the hermes.nix module

**Files:**
- Create: `modules/hosts/raspberry-pi-4/hermes.nix`

- [ ] **Step 1: Create the hermes module file**

```nix
{ self, inputs, ... }:
{
  flake.nixosModules."raspberry-pi-4/hermes" =
    { config, ... }:
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      services.hermes-agent = {
        enable = true;
        settings.model = {
          base_url = "https://api.ollama.cloud/v1";
          default = "gemma4:31b-cloud";
        };
        environmentFiles = [ config.age.secrets.hermes-env.path ];
        restart = "always";
        restartSec = 5;
      };
    };
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/hosts/raspberry-pi-4/hermes.nix
git commit -m "feat(rpi4): add hermes-agent module"
```

---

### Task 2: Register the hermes module in raspberry-pi-4.nix

**Files:**
- Modify: `modules/hosts/raspberry-pi-4/raspberry-pi-4.nix`

Current imports list (lines 6-22):
```nix
imports = [
  self.nixosModules."raspberry-pi-4/nextcloud"
  self.nixosModules."raspberry-pi-4/trilium"
  self.nixosModules."raspberry-pi-4/cloudflared"
  self.nixosModules."raspberry-pi-4/pwm-fan"
  self.nixosModules."agenix"
  self.nixosModules."raspberry-pi-4/specific"
  self.nixosModules."raspberry-pi-4/configuration"
  inputs.nixos-hardware.nixosModules.raspberry-pi-4
  self.nixosModules."base/git"
  self.nixosModules."base/configuration"
  self.nixosModules."options"
  (_: {
    custom.flakeTarget = "raspberry-pi-4";
    custom.defaultUser = "nixos";
  })
];
```

- [ ] **Step 1: Add hermes module import**

Add `self.nixosModules."raspberry-pi-4/hermes"` to the imports list:

```nix
imports = [
  self.nixosModules."raspberry-pi-4/nextcloud"
  self.nixosModules."raspberry-pi-4/trilium"
  self.nixosModules."raspberry-pi-4/cloudflared"
  self.nixosModules."raspberry-pi-4/pwm-fan"
  self.nixosModules."raspberry-pi-4/hermes"
  self.nixosModules."agenix"
  self.nixosModules."raspberry-pi-4/specific"
  self.nixosModules."raspberry-pi-4/configuration"
  inputs.nixos-hardware.nixosModules.raspberry-pi-4
  self.nixosModules."base/git"
  self.nixosModules."base/configuration"
  self.nixosModules."options"
  (_: {
    custom.flakeTarget = "raspberry-pi-4";
    custom.defaultUser = "nixos";
  })
];
```

Note: the `inputs.hermes-agent.nixosModules.default` import is already handled inside `hermes.nix`, so it does NOT need to be added at this level.

- [ ] **Step 2: Commit**

```bash
git add modules/hosts/raspberry-pi-4/raspberry-pi-4.nix
git commit -m "feat(rpi4): import hermes module"
```

---

### Task 3: Add hermes-env agenix secret

**Files:**
- Modify: `modules/agenix/agenix.nix`
- Modify: `modules/_secrets/secrets.nix`
- Create: `modules/_secrets/hermes-env.age` (via `agenix -e`)

- [ ] **Step 1: Add age.secrets.hermes-env to agenix.nix**

Add after the existing `age.secrets.google-api-key` block (line 41):

```nix
age.secrets.hermes-env = {
  file = custom.secretsDir + "/hermes-env.age";
  owner = "hermes";
  group = "hermes";
  mode = "0400";
};
```

- [ ] **Step 2: Add hermes-env.age to secrets.nix**

Add to `modules/_secrets/secrets.nix` before the closing `}`:

```nix
"hermes-env.age" = {
  publicKeys = [
    nixos
    raspberry-pi-4
  ];
  armor = true;
};
```

- [ ] **Step 3: Create the encrypted secret file**

Run on a machine with the nixos SSH private key:

```bash
cd /etc/nixos
nix develop -c agenix -e modules/_secrets/hermes-env.age
```

The file should contain:

```
OLLAMA_API_KEY=<your-ollama-cloud-key>
SIGNAL_PHONE_NUMBER=<your-phone-number>
```

- [ ] **Step 4: Commit**

```bash
git add modules/agenix/agenix.nix modules/_secrets/secrets.nix modules/_secrets/hermes-env.age
git commit -m "feat(secrets): add hermes-env agenix secret for RPi4"
```

---

### Task 4: Verify the build

- [ ] **Step 1: Check flake evaluation for raspberry-pi-4**

```bash
cd /etc/nixos
nix flake check --no-build
```

Expected: no evaluation errors.

- [ ] **Step 2: Build the toplevel (dry-run first)**

```bash
nixos-rebuild build --flake .#raspberry-pi-4
```

Expected: successful build without errors.

---

### Task 5: Deploy and verify on RPi4

- [ ] **Step 1: Deploy**

```bash
sudo nixos-rebuild switch --flake .#raspberry-pi-4
```

- [ ] **Step 2: Verify service is running**

```bash
systemctl status hermes-agent
```

Expected: `active (running)`.

- [ ] **Step 3: Check logs**

```bash
journalctl -u hermes-agent -f
```

Expected: hermes starts, connects to Ollama Cloud API, gateway listening.

- [ ] **Step 4: Link Signal (one-time)**

```bash
sudo -u hermes HERMES_HOME=/var/lib/hermes/.hermes hermes signal link
```

Follow the QR code / pairing instructions on your Signal app.