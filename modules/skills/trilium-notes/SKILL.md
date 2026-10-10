---
name: trilium-notes
description: Use for anything about the user's Trilium notes (daily notes, tasks, ideas, health, programming, diet/training) - searching, reading full notes, browsing the tree, creating, updating or removing notes, attributes and attachments - through Trilium's built-in MCP server from the Python kernel.
---

# Trilium Notes (MCP)

Trilium's built-in HTTP MCP server (Trilium 0.106; the server must have the
*MCP server* option enabled in Options -> AI/LLM), Bearer auth with an ETAPI
token. Server URL comes from `TRILIUM_MCP_URL`, set for every session from
`customBot.triliumMcpUrl` (`modules/options.nix`, exported in
`modules/hosts/base/prime-agent.nix`):

- raspberry-pi-4: `http://127.0.0.1:8081/mcp` (option default; also the
  fallback in `src/trilium_notes/__init__.py` when the variable is unset),
- nixos (laptop): `http://127.0.0.1:37840/mcp` (desktop Trilium, set in
  `modules/hosts/nixos/default.nix`).

The token is read from `TRILIUM_ETAPI_TOKEN` (the fish wrapper `prime-agent`
from `modules/hosts/base/agenix.nix` sets it for that process only); if the
variable is empty, the module reads the agenix file `/run/agenix/trilium-etapi`
at import time. Never print the token.

## Usage

Tools are auto-discovered from the server; call them from the IPython kernel
with keyword arguments only and always `await`. Trilium returns every result as
a JSON string — decode it with `json.loads`; failures come back as
`{"error": "..."}`, not as exceptions:

```python
import json
import trilium_notes

# 1. Discover tools / argument schemas (don't hardcode)
for t in await trilium_notes.list_tools():
    print(t["name"], "-", (t.get("description") or "")[:80])

# 2. Search notes (Trilium search syntax: '#label', '~relation', 'note.title *=* Nix')
hits = json.loads(await trilium_notes.search_notes(query="Nix", limit=10))
syntax = json.loads(await trilium_notes.load_skill(name="search_syntax"))  # full syntax guide

# 3. Read a note (find IDs with search_notes)
meta = json.loads(await trilium_notes.get_note(noteId="gizBJ1qzBFsT"))
body = json.loads(await trilium_notes.get_note_content(noteId="gizBJ1qzBFsT"))["content"]  # Markdown

# 4. Tree browsing
tree = json.loads(await trilium_notes.get_subtree(noteId="root", depth=2))

# 5. Writing (confirm with the user first); text-note content is Markdown
r = await trilium_notes.create_note(parentNoteId="root", title="Tytul", type="text", content="...")
r = await trilium_notes.append_to_note(noteId="...", content="...")
r = await trilium_notes.set_note_content(noteId="...", content="...")
```

Tools (Trilium 0.106): notes `search_notes`, `get_note`, `get_note_content`,
`create_note`, `set_note_content`, `append_to_note`, `edit_note_content`
(find-and-replace, NOT for `text` notes), `rename_note`, `delete_note`;
tree `get_child_notes`, `get_subtree`, `move_note`, `clone_note`; attributes
`get_attributes`, `get_attribute`, `set_attribute`, `delete_attribute`;
attachments `get_attachment`, `get_attachment_content`; `search_icons`;
`load_skill` (Trilium's own guides: `search_syntax`, `backend_scripting`,
`frontend_scripting`, `dashboards`). Note IDs are Trilium NoteIds (e.g.
`gizBJ1qzBFsT`), not titles.

## Formatting notes (markdown-first)

`create_note`, `set_note_content` and `append_to_note` take **Markdown** for
`text` notes and Trilium converts it to its own HTML; `get_note_content`
returns text notes as Markdown. Use native structures only — no inline
`style=`, custom CSS classes, wrapper `div`s or raw HTML (they break the theme):

- `##`/`###`/`####` headings, paragraphs, `**bold**`/`*italic*`, lists
- `>` blockquotes for callouts, formulas, answers (instead of colored boxes)
- `**PYTHON**`-style bold labels instead of badges
- fenced code blocks with a language (```` ```python ````, ```` ```sql ````)
- Markdown tables (Trilium draws the borders itself)
- no table of contents (Trilium renders its own from headings), no `var(--x)`

## Details

- Server (raspberry-pi-4): systemd unit `trilium-server`
  (`modules/hosts/raspberry-pi-4/trilium.nix`), port 8081, data dir
  `/var/lib/trilium`.
- Server (nixos): desktop app `trilium-desktop`
  (`modules/hosts/nixos/packages.nix`), started manually — MCP works only
  while it runs; port 37840, data dir `~/trilium-data` if it exists, otherwise
  `~/.local/share/trilium-data`.
- The Python package is NOT installed by the kernel bootstrap
  (`PRIME_AGENT_KERNEL_PYTHON` points to a read-only env, so
  `uv pip install --editable` can't work there). It is importable thanks to
  `PYTHONPATH` set from `modules/skills/default.nix` (pythonSkills).
- The same server is also configured as `mcpServers.trilium-notes` in Prime
  Agent's `settings.json`, and Hermes on raspberry-pi-4 uses it with the same
  token (`modules/hosts/raspberry-pi-4/hermes.nix`, header
  `Bearer ${TRILIUM_ETAPI_TOKEN}` from Hermes' own environment). Rotate the
  token in Trilium (Options -> ETAPI), then update BOTH the agenix secret on
  the laptop (`cd modules/_secrets && sudo agenix -e trilium-etapi.age -i /root/.ssh/id_ed25519`)
  and the variable in Hermes' environment.
- Destructive calls (`delete_note`, `set_note_content`, `move_note`,
  `delete_attribute`) — always confirm with the user first;
  `set_note_content` saves a note revision before overwriting.
