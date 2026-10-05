#!/usr/bin/env bash
# Hook PostToolUse Claude Code (Edit|Write), podpięty w .claude/settings.json.
#  - edytowany plik .nix w repo -> nixfmt; błąd parsera wraca do Claude
#    (exit 2), więc błąd składni wychodzi od razu, a nie przy eval/commicie,
#  - modules/github-actions.nix -> `nix develop -c true` (shellHook przepina
#    .pre-commit-config.yaml na nowy store path hooka sync-github-actions)
#    + regeneracja .github/workflows — usuwa pułapkę "stale hook" z AGENTS.md.
# jq/nixfmt pochodzą z devShella (alias `claude-nixos`); poza nim hook nic
# nie robi — format i tak sprawdza pre-commit przy commicie.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}

command -v jq >/dev/null || exit 0
file=$(jq -r '.tool_input.file_path // empty')
[[ $file == "$root"/*.nix ]] || exit 0

if command -v nixfmt >/dev/null && ! out=$(nixfmt "$file" 2>&1); then
  printf 'nixfmt %s:\n%s\n' "$file" "$out" >&2
  exit 2
fi

if [[ $file == "$root/modules/github-actions.nix" ]]; then
  cd "$root" || exit 1
  if ! out=$( (nix develop -c true && nix run .#sync-github-actions) 2>&1); then
    printf 'sync-github-actions:\n%s\n' "$out" >&2
    exit 2
  fi
fi
exit 0
