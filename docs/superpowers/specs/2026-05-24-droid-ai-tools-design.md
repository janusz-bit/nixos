# Design: Add AI Tools to Droid

## Context
The `droid` host (aarch64-linux via AVF) needs `ollama` and `opencode` installed for CLI usage, specifically targeting cloud-based LLM providers.

## Implementation
Add `ollama` and `opencode` to the system packages in `modules/hosts/droid-android/default.nix`.

### Details
- **Packages**: `pkgs.ollama`, `opencode`
- **Configuration**: 
  - Install as system packages.
  - Do NOT enable `services.ollama` as the user intends to use cloud-based LLMs and does not require a local server backend.
- **Location**: `modules/hosts/droid-android/default.nix` (within the anonymous module).

## Verification
- Verify that `ollama` and `opencode` are available in the `droid` configuration.
- Ensure no local ollama service is started.
