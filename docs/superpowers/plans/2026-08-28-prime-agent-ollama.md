# prime-agent + Ollama Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skonfigurować providery Ollama (lokalny + ollama-cloud) i default model `glm-5.3-flash:cloud` dla prime-agenta, deklaratywnie na wszystkich hostach.

**Architecture:** Nowy moduł NixOS `base-prime-agent` generuje `models.json` i `settings.json` do `/etc/prime-agent/` przez `environment.etc` i linkuje je przez `systemd.tmpfiles.rules` (wzorzec `L+` z `modules/skills/default.nix`) do `~/.prime/agent/` użytkownika `config.customBot.defaultUser`. Klucz API ollama-cloud jest rozwiązywany z env `OLLAMA_API_KEY`, już eksportowanego przez `base-agenix`.

**Tech Stack:** Nix (flake-parts + import-tree), NixOS `environment.etc` + `systemd-tmpfiles`, prime-agent 0.7.2 (`~/.prime/agent/models.json` + `settings.json`).

**Spec:** `docs/superpowers/specs/2026-08-28-prime-agent-ollama-design.md`

## Global Constraints

- Sekrety nigdy w `.nix` files (world-readable `/nix/store`) — klucz tylko przez env `OLLAMA_API_KEY` (dosłowny string w models.json to **nazwa zmiennej**, nie wartość).
- Formatowanie wymuszone: `nixfmt` (`nix fmt`), `statix`, `deadnix` — uruchamiać przed commitami kodu.
- Wzorzec repo: `flake.modules.nixos.<name> = { ... }`; moduły rejestrowane w `modules/hosts/base/default.nix` `imports`.
- Użytkownik z opcji, nie hardcoded: `config.customBot.defaultUser` (`dinosaur` na `nixos`, `nixos` na RPi4/WSL, `droid` na droid).
- Walidacja buildów: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run` (bez `--sudo`, eval-only).

---

### Task 1: Moduł `base-prime-agent` (models.json + settings.json + symlinki)

**Files:**
- Create: `modules/hosts/base/prime-agent.nix`
- Modify: `modules/hosts/base/default.nix` (lista `imports`, linie 11-19)

**Interfaces:**
- Consumes: `config.customBot.defaultUser` (string, z `modules/options.nix`); moduł `base-agenix` (eksportuje `OLLAMA_API_KEY` w `environment.shellInit` — uruchamiany dla interaktywnych shelli, z których startuje prime-agent).
- Produces: moduł `self.modules.nixos.base-prime-agent`; pliki `/etc/prime-agent/models.json` i `/etc/prime-agent/settings.json` w store; tmpfiles symlinki `~/.prime/agent/{models,settings}.json` dla default usera.

- [ ] **Step 1: Utwórz `modules/hosts/base/prime-agent.nix`**

```nix
# Deklaratywna konfiguracja Prime Agenta (providers + default model).
# Pliki generowane do /etc/prime-agent i symlinkowane przez tmpfiles do
# ~/.prime/agent/ (domyślny katalog konfiguracji prime-agenta) — ten sam
# wzorzec co modules/skills/default.nix.
# Klucz API ollama-cloud: "OLLAMA_API_KEY" to nazwa zmiennej środowiskowej
# (prime-agent resolve'uje ją przez process.env); wartość pochodzi z agenix
# (modules/hosts/base/agenix.nix), nigdy nie trafia do /nix/store.
{
  flake.modules.nixos.base-prime-agent =
    { config, ... }:
    let
      user = config.customBot.defaultUser;

      modelsJson = builtins.toJSON {
        providers = {
          ollama = {
            baseUrl = "http://localhost:11434/v1";
            api = "openai-completions";
            # Literal "ollama" — lokalny Ollama ignoruje klucz, ale schemat go
            # wymaga (docs: packages/coding-agent/docs/models.md).
            apiKey = "ollama";
            compat = {
              supportsDeveloperRole = false;
              supportsReasoningEffort = false;
            };
            models = [
              {
                id = "ornith:35b";
              }
            ];
          };
          ollama-cloud = {
            baseUrl = "https://ollama.com/v1";
            api = "openai-completions";
            # Nazwa zmiennej env — wartość z agenix (base/agenix.nix).
            apiKey = "OLLAMA_API_KEY";
            models = [
              {
                id = "glm-5.3-flash:cloud";
                reasoning = true;
              }
            ];
          };
        };
      };

      settingsJson = builtins.toJSON {
        defaultProvider = "ollama-cloud";
        defaultModel = "glm-5.3-flash:cloud";
      };
    in
    {
      environment.etc = {
        "prime-agent/models.json".text = modelsJson + "\n";
        "prime-agent/settings.json".text = settingsJson + "\n";
      };

      systemd.tmpfiles.rules = map (
        name: "L+ /home/${user}/.prime/agent/${name} - - - - /etc/prime-agent/${name}"
      ) [
        "models.json"
        "settings.json"
      ];
    };
}
```

- [ ] **Step 2: Zarejestruj moduł w `modules/hosts/base/default.nix`**

Edytuj listę `imports` — dodaj `self.modules.nixos.base-prime-agent`:

```nix
      imports = [
        self.modules.nixos.base-configuration
        self.modules.nixos.base-shell
        self.modules.nixos.base-git
        self.modules.nixos.nix-settings
        self.modules.nixos.base-ssh
        self.modules.nixos.base-agenix
        self.modules.nixos.base-prime-agent
        self.modules.nixos.options
      ];
```

- [ ] **Step 3: Format i lint**

Run (z `/etc/nixos`):
```sh
nix fmt modules/hosts/base/prime-agent.nix modules/hosts/base/default.nix
statix check modules/hosts/base/prime-agent.nix modules/hosts/base/default.nix
deadnix modules/hosts/base/prime-agent.nix modules/hosts/base/default.nix
```
Expected: formatter bez zmian (lub tylko drobne kosmetyczne); brak findings.

- [ ] **Step 4: Eval-check na wszystkich 4 hostach**

Run (z `/etc/nixos`):
```sh
nix eval '.#nixosConfigurations.nixos.config.environment.etc."prime-agent/models.json".text' --raw | jq .
nix eval '.#nixosConfigurations.raspberry-pi-4.config.environment.etc."prime-agent/models.json".text' --raw | jq .
nix eval '.#nixosConfigurations.wsl.config.environment.etc."prime-agent/settings.json".text' --raw
nix eval '.#nixosConfigurations.droid.config.environment.etc."prime-agent/settings.json".text' --raw
```
Expected: JSON z providerami `ollama` i `ollama-cloud`; settings z `defaultProvider: "ollama-cloud"`. Każdy eval kończy się kodem 0.

- [ ] **Step 5: Dry-run build na wszystkich hostach**

Run (z `/etc/nixos`):
```sh
for h in nixos raspberry-pi-4 wsl droid; do
  nix build .#nixosConfigurations.$h.config.system.build.toplevel --dry-run 2>&1 | tail -1
done
```
Expected: każdy host wypisuje eval bez błędów (dry-run pokazuje co zbudować/zciągnąć; błąd eval = fail).

- [ ] **Step 6: Commit**

```bash
git add modules/hosts/base/prime-agent.nix modules/hosts/base/default.nix
git commit -m "nixos: prime-agent ollama providers + default model (base)"
```

---

### Task 2: Aktualizacja AGENTS.md (dokumentacja żywa)

**Files:**
- Modify: `AGENTS.md` (sekcja `### 1. base (The Foundation)`)

**Interfaces:**
- Consumes: zmerge'owany Task 1.
- Produces: dokumentacja AGENTS.md zgodna ze stanem repo (repo convention: „AGENTS.md is the repo's living documentation").

- [ ] **Step 1: Dodaj wpis o konfiguracji prime-agent w sekcji base**

W `AGENTS.md`, w sekcji `### 1. base (The Foundation)`, zaraz po punkcie
`**OpenCode**:` (który opisuje `modules/overlays/opencode.nix`), dodaj:

```markdown
* **Prime Agent config** (`modules/hosts/base/prime-agent.nix`): deklaratywna
  konfiguracja prime-agenta — `models.json` (providery `ollama` lokalny,
  `http://localhost:11434/v1`, model `ornith:35b`, z `compat.supportsDeveloperRole/supportsReasoningEffort = false`;
  oraz `ollama-cloud`, `https://ollama.com/v1`, model `glm-5.3-flash:cloud` z
  `reasoning = true`, klucz z env `OLLAMA_API_KEY` z agenix) i `settings.json`
  (`defaultProvider = "ollama-cloud"`, `defaultModel = "glm-5.3-flash:cloud"`).
  Pliki generowane do `/etc/prime-agent/` i symlinkowane przez tmpfiles do
  `~/.prime/agent/` użytkownika `customBot.defaultUser`. Trade-off: zmiany
  settings.json z TUI nie przetrwają rebuildu.
```

- [ ] **Step 2: Lint-nie dotyczy, commit**

```bash
git add AGENTS.md
git commit -m "docs: prime-agent ollama config in base (AGENTS.md)"
```

---

### Task 3: Weryfikacja końcowa (deploy + runtime smoke test)

**Files:**
- Brak zmian w plikach — walidacja po `switch` na hoście lokalnym (`nixos`).

**Interfaces:**
- Consumes: zmerge'owane Task 1 + 2.
- Produces: działający prime-agent z providerami Ollama na hoście.

- [ ] **Step 1: Pre-commit hooks przechodzą**

Run (z `/etc/nixos`):
```sh
nix build .#checks.x86_64-linux.pre-commit --no-link
```
Expected: build OK (nixfmt, statix, deadnix, workflow-sync).

- [ ] **Step 2: Deploy na hoście lokalnym**

Run (z `/etc/nixos`):
```sh
sudo nixos-rebuild switch --flake .#nixos
```
Expected: aktywacja bez błędów; systemd-tmpfiles tworzy symlinki.

- [ ] **Step 3: Zweryfikuj symlinki i treść**

Run:
```sh
ls -l ~/.prime/agent/models.json ~/.prime/agent/settings.json
cat ~/.prime/agent/settings.json
```
Expected:
```
/home/dinosaur/.prime/agent/models.json -> /etc/prime-agent/models.json
/home/dinosaur/.prime/agent/settings.json -> /etc/prime-agent/settings.json
{"defaultProvider":"ollama-cloud","defaultModel":"glm-5.3-flash:cloud"}
```

- [ ] **Step 4: Smoke test prime-agenta**

Run (interaktywnie, wymaga `OLLAMA_API_KEY` z shellInit):
```sh
prime-agent --version
# w TUI: /model → provider ollama-cloud wybrany jako default; /providers
# pokazuje ollama i ollama-cloud; wyślij krótki prompt do glm-5.3-flash:cloud
```
Expected: wersja bez błędu; default provider/model ustawione; odpowiedź z modelu
przychodzi (ollama-cloud, klucz z env). Lokalny `ollama` widoczny w selektorze
(aktywny tylko przy działającym serwisie Ollama).