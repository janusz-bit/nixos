# Hermes Agent on Raspberry Pi 4 - Design Spec

## Summary

Add hermes-agent as a declarative NixOS service on the raspberry-pi-4 host, using the native (non-container) mode with the Ollama Cloud API provider and Signal messaging platform.

## Architecture

- **Mode**: Native (hardened systemd service, no container - saves RAM on RPi4)
- **Model**: `gemma4:31b-cloud` via Ollama Cloud API
- **Platform**: Signal (requires one-time QR code pairing after deployment)
- **Secrets**: agenix-encrypted `hermes-env.age` file containing `OLLAMA_API_KEY` and `SIGNAL_PHONE_NUMBER`
- **addToSystemPackages**: false (headless server; CLI accessible via `sudo -u hermes`)

## Files to Create/Modify

| File | Action | Description |
|---|---|---|
| `modules/hosts/raspberry-pi-4/hermes.nix` | CREATE | New nixosModule defining hermes-agent service |
| `modules/hosts/raspberry-pi-4/raspberry-pi-4.nix` | MODIFY | Add hermes module import + hermes-agent nixos module |
| `modules/agenix/agenix.nix` | MODIFY | Add `age.secrets.hermes-env` |
| `modules/_secrets/secrets.nix` | MODIFY | Add `hermes-env.age` with publicKeys for nixos + raspberry-pi-4 |
| `modules/_secrets/hermes-env.age` | CREATE | Encrypted env file (created via `agenix -e`) |
| `flake.nix` | NO CHANGE | `hermes-agent` input already exists (line 35) |

## Hermes Configuration

```nix
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
```

## Post-Deployment Steps

1. Create and encrypt `hermes-env.age` via `agenix -e modules/_secrets/hermes-env.age` with:
   ```
   OLLAMA_API_KEY=<key>
   SIGNAL_PHONE_NUMBER=<phone>
   ```
2. `nixos-rebuild switch` on RPi4
3. Signal pairing: run the appropriate hermes command to link Signal account
4. Verify: `systemctl status hermes-agent` + `journalctl -u hermes-agent -f`

## Constraints

- RPi4 is aarch64-linux with limited RAM - native mode chosen over container
- agenix secret must be encrypted before first deploy
- Ollama Cloud API base_url needs verification at deploy time