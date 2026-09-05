---
name: trilium-notes
description: Read, search, edit and organize the user's Trilium notes (daily notes, tasks, ideas, health, programming, diet/training) through Trilium's built-in MCP server. Use for anything about the user's notes - searching content, reading full notes, browsing the tree, creating/updating/removing notes, attributes and attachments.
---

# Trilium Notes (MCP)

HTTP MCP server at `http://127.0.0.1:8081/mcp` (TriliumNext 0.105 built-in),
Bearer auth with the ETAPI token from `/run/agenix/trilium-etapi`
(loaded automatically into `TRILIUM_ETAPI_TOKEN` at import time).

## Usage

Tools are auto-discovered from the server; call them from the IPython kernel.
Always `await` - results are already-parsed Python (str/dict):

```python
import trilium_notes

# 1. Discover tools / argument schemas (don't hardcode)
for t in await trilium_notes.list_tools():
    print(t["name"], "-", t["description"][:80])

# 2. Search notes (Trilium search syntax; docs via load_skill("search_syntax"))
r = await trilium_notes.search_notes(query="Nix")

# 3. Read a note (find IDs with search_notes)
r = await trilium_notes.get_note(noteId="gizBJ1qzBFsT")
r = await trilium_notes.get_note_content(noteId="gizBJ1qzBFsT")

# 4. Tree browsing
r = await trilium_notes.get_subtree(noteId="root", depth=2)

# 5. Writing (confirm with the user first)
r = await trilium_notes.create_note(parentNoteId="root", title="Tytul", type="text", content="...")
r = await trilium_notes.append_to_note(noteId="...", content="...")
r = await trilium_notes.set_note_content(noteId="...", content="...")
```

Key tools: `search_notes`, `get_note`, `get_note_content`, `get_subtree`,
`get_child_notes`, `create_note`, `append_to_note`, `edit_note_content`,
`set_note_content`, `rename_note`, `delete_note`, `set_attribute`.
Note IDs are Trilium NoteIds (e.g. `gizBJ1qzBFsT`), not titles.

## Details

- Server: systemd unit `trilium-server`, port 8081, data dir `/var/lib/trilium`.
- The ETAPI token is shared with the Hermes agent (its `~/.hermes/.env`).
  Rotate in Trilium UI (Settings -> ETAPI tokens), then update BOTH the
  agenix secret (`modules/_secrets/trilium-etapi.age` via
  `sudo agenix -e modules/_secrets/trilium-etapi.age`) and Hermes env.
- Destructive calls (`delete_note`, `set_note_content`) - always confirm
  with the user first.
