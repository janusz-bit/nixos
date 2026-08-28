# Design: prime-agent + Ollama

Data: 2026-08-28

## Cel

prime-agent (self-improving coding agent, RLM) ma mieć skonfigurowanych dwóch
providerów Ollama — identycznie jak opencode — oraz startować domyślnie z modelem
`glm-5.3-flash:cloud` z ollama-cloud:

1. **ollama** (lokalny): `http://localhost:11434/v1`, model `ornith:35b`
2. **ollama-cloud**: `https://ollama.com/v1`, model `glm-5.3-flash:cloud`,
   klucz z env `OLLAMA_API_KEY`

## Stan obecny

- `prime-agent` zainstalowany w `sharedPackages`
  (`modules/hosts/base/configuration.nix:23`) — dostępny na wszystkich hostach.
- Konfiguracja prime-agenta żyje w `~/.prime/agent/`
  (`models.json`, `settings.json`) — obecnie brak takowej w repo.
- `OLLAMA_API_KEY` już eksportowany z agenix
  (`modules/hosts/base/agenix.nix:9`, sekret `ollama-api-key.age`,
  `mode = "0440"`, `group = "users"`).
- prime-agent nie ma wbudowanego providera Ollama — dodaje się go przez
  `~/.prime/agent/models.json` (API OpenAI-compatible). Rozdzielczość
  `apiKey` wspiera nazwę zmiennej środowiskowej (potwierdzone w kodzie:
  `resolveConfigValue` → `process.env[config]`).
- Wzorzec deklaratywnej konfiguracji w katalogu domowym użytkownika istnieje:
  `modules/skills/default.nix` (`environment.etc` + `systemd.tmpfiles.rules`
  z symlinkami `L+`).
- prime-agent wspiera `defaultProvider` / `defaultModel` w `settings.json`
  (docs: `settings.md`).

## Zmiany

### 1. Nowy plik: `modules/hosts/base/prime-agent.nix`

Moduł `flake.modules.nixos.base-prime-agent`:

- generuje `models.json` i `settings.json` do `/etc/prime-agent/`
  (przez `environment.etc`, read-only, zarządzane przez Nix);
- tworzy symlinki do `~/.prime/agent/` użytkownika przez
  `systemd.tmpfiles.rules` — wzorzec 1:1 z `modules/skills/default.nix:32-34`:
  ```nix
  L+ /home/${user}/.prime/agent/models.json - - - - /etc/prime-agent/models.json
  L+ /home/${user}/.prime/agent/settings.json - - - - /etc/prime-agent/settings.json
  ```
- użytkownik: `config.customBot.defaultUser` (dynamicznie: `dinosaur` na
  `nixos`, `nixos` na `raspberry-pi-4`/`wsl`, `droid` na `droid`).

### 2. Rejestracja modułu: `modules/hosts/base/default.nix`

Dodać `self.modules.nixos.base-prime-agent` do listy `imports`.

### 3. Treść `models.json`

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [{ "id": "ornith:35b" }]
    },
    "ollama-cloud": {
      "baseUrl": "https://ollama.com/v1",
      "api": "openai-completions",
      "apiKey": "OLLAMA_API_KEY",
      "models": [{ "id": "glm-5.3-flash:cloud", "reasoning": true }]
    }
  }
}
```

Uzasadnienia:

- `apiKey: "OLLAMA_API_KEY"` — prime-agent rozwiązuje to przez `process.env`;
  zmienna już eksportowana przez `base/agenix.nix` — zero nowych sekretów.
- `apiKey: "ollama"` (literal) — lokalny Ollama ignoruje klucz; wymagany tylko
  przez schemat (wg docs `models.md`).
- `compat.supportsDeveloperRole/supportsReasoningEffort: false` — zalecane
  w oficjalnych docs prime-agenta dla lokalnych serwerów Ollama.
- Model `glm-5.3-flash:cloud` oznaczony `reasoning: true` (spójnie z użyciem
  w hermes z `reasoning_effort = "max"`).

### 4. Treść `settings.json`

Minimalna, tylko wymagane klucze:

```json
{ "defaultProvider": "ollama-cloud", "defaultModel": "glm-5.3-flash:cloud" }
```

## Wpływ na hosty

| Host | ollama-cloud | ollama (lokalny) |
|---|---|---|
| `nixos` | działa (klucz z agenix) | działa (lokalny serwis Ollama w `ai.nix`) |
| `raspberry-pi-4` | działa | działa (serwis `services.ollama.enable`) |
| `wsl` | działa | provider widoczny, ale nieaktywny (brak serwisu) |
| `droid` | działa | provider widoczny, ale nieaktywny (brak serwisu) |

## Trade-offy (świadome)

- `settings.json` zarządzany deklaratywnie — zmiany z TUI (np. `/theme`,
  zapis domyślnego modelu przez `/model`) nie przetrwają rebuildu.
  Model można przełączać per-sesja przez `/model`; tylko zapis defaultu jest
  nadpisywany. Konsekwencja wybranego podejścia A (tmpfiles symlinki).
- Provider `ollama` (lokalny) będzie widoczny w `/model` także na hostach bez
  serwisu Ollama — nieaktywny do czasu uruchomienia serwisu.

## Odrzucone alternatywy

- **Overlay wrapper** (`PRIME_AGENT_CODING_AGENT_DIR`) — przenosi cały katalog
  stanu (sessions, auth, logs) do store; psuje zapis stanu.
- **Tylko models.json** — nie spełnia wymagania default model = ollama-cloud.
- **Ręczna konfiguracja** — zero deklaratywności, nie do utrzymania.

## Weryfikacja

```sh
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.raspberry-pi-4.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.wsl.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.droid.config.system.build.toplevel --dry-run
```

Plus lint: `nixfmt`, `statix`, `deadnix` (pre-commit).

Po wdrożeniu (na hoście):

```sh
prime-agent   # start z glm-5.3-flash:cloud (ollama-cloud)
# /model → widoczne providery: ollama, ollama-cloud
```