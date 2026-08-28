# Design: prime-agent na wszystkich hostach (base)

Data: 2026-08-28

## Cel

`prime-agent` (self-improving coding agent, RLM — z flake `github:numtide/llm-agents.nix`)
ma być dostępny systemowo na **każdym** hoście: `nixos`, `raspberry-pi-4`, `wsl`, `droid`.

## Stan obecny

- `prime-agent` zainstalowany **tylko** na `raspberry-pi-4`
  (`modules/hosts/raspberry-pi-4/configuration.nix:116`).
- Flake input `llm-agents` już zadeklarowany w `flake.nix:38`.
- Wspólne pakiety wszystkich hostów: `sharedPackages` w
  `modules/hosts/base/configuration.nix` (używane przez `environment.systemPackages`
  oraz `homeModules.configuration`).

## Zmiany

1. `modules/hosts/base/configuration.nix` — dodać do `sharedPackages`:
   ```nix
   inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent
   ```
   (wzorzec identyczny z istniejącym wpisem `agenix`, linia 22; `inputs` jest
   już w scope funkcji). Efekt: prime-agent w systemPackages i home na każdym hoście.
2. `modules/hosts/raspberry-pi-4/configuration.nix` — usunąć wpis
   `prime-agent` (linia ~116), bo stanie się redundantny.

## Uzasadnienie

- `base` jest importowany przez wszystkie 4 hosty → jedna zmiana zamiast czterech.
- Wzorzec `inputs.<name>.packages.${pkgs.stdenv.hostPlatform.system}.<attr>`
  jest już używany w `sharedPackages` (agenix).
- `aarch64-linux` działa — RPi4 już używa tego atrybutu.
- Na `droid` (minimalny footprint) to tylko binarka CLI, nie serwis — brak wpływu
  na boot/ram.

## Weryfikacja

```sh
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.raspberry-pi-4.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.wsl.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.droid.config.system.build.toplevel --dry-run
```

Plus lint: `nixfmt`, `statix`, `deadnix` (pre-commit).