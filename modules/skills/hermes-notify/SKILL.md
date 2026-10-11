---
name: hermes-notify
description: Use when you finish a longer task or the user asked to be told when you are done ("daj znać", "powiadom mnie", "let me know"), when you are blocked on a question or decision only the user can make, or when you hit an error you cannot work around. Sends a short message to the user's Matrix DM through Hermes with `claude-notify`, so it reaches them away from the terminal. Not for every reply.
---

# Notify the user on Matrix (`claude-notify`)

`claude-notify` delivers text verbatim (no LLM involved) to the user's private
Matrix room with the Hermes bot, which reaches their phone. A header with host,
account, tmux session and working directory is added automatically; do not
repeat it.

## When to send

- A longer task is finished, or the user asked to be notified.
- You are blocked: a question or decision only the user can make, and you
  cannot continue without it.
- An error you cannot work around after reasonable attempts, so work stops.

## When not to send

- After every reply, or for short tasks while the user is clearly at the
  terminal.
- Permission prompts and MCP input dialogs: a Notification hook already reports
  them.
- Progress updates, retries, or a repeat of something already sent.

## Form

- Polish, at most ~8 lines, concrete: what is done and its result, or exactly
  what you need from the user (list the options when there is a choice).
- Hermes renders the text as Markdown on Matrix: use **bold**, `inline code`
  (paths, commands, names), short lists (put a blank line before the list) and
  fenced code blocks.
- No tables and no headings. Text in `<...>` outside code is dropped as an
  unknown HTML tag, so put anything with `<` or `>` in backticks.
- Never secrets, tokens, passwords or keys; no long logs or diffs, at most the
  one line of an error that matters.

## How

```sh
claude-notify "Gotowe: <co zrobione, wynik>"

claude-notify <<'EOF'
Utknąłem: <co blokuje>
Pytanie: <decyzja, opcje>
EOF
```

Short text as an argument, longer text on stdin. Exit status 0 means Hermes
accepted the message (or the same message from this session already went out
less than 60 s ago and was skipped). Otherwise the error says why (no access to
the key from this account, limit of 30 messages per hour, the RPi
unreachable): do not retry in a loop, mention the failure in your reply
instead.

`claude-notify --print "..."` writes the final message (with the header) to
stdout instead of sending it; use it only to test the formatting.
