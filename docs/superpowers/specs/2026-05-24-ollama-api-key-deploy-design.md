# Design: Deploy OLLAMA_API_KEY via Agenix

## Purpose
Provide the `OLLAMA_API_KEY` secret to all NixOS hosts in the fleet using the existing Agenix infrastructure.

## Architecture
The secret will be managed using the same pattern as other global tokens (`GITHUB_TOKEN`, `CACHIX_AUTH_TOKEN`).

### Components
1. **Secret Storage**: An age-encrypted file located at `modules/_secrets/ollama-api-key.age`.
2. **Configuration**: 
   - Addition of `ollama-api-key` to the shared `age.secrets` definition.
   - Addition of `OLLAMA_API_KEY` to `environment.sessionVariables` in `modules/hosts/base/agenix.nix`.

## Data Flow
`Encrypted .age file` -> `Agenix decryption` -> `System path` -> `Environment Variable`

## Success Criteria
- The `OLLAMA_API_KEY` environment variable is available in the shell session on all hosts.
- The secret is securely encrypted in the repository.
