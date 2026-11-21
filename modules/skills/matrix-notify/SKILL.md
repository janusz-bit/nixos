---
name: matrix-notify
description: Send a notification to the user over Matrix with `matrix-notify` (it reaches their phone and laptop through the Matrix app). Use when the user asks to be notified, pinged or told on their phone, or asks to be told when something finishes (a long build, CI, a VM test, a download), and when work they are waiting on away from the computer ends or needs their decision.
---

# matrix-notify — message to the user's Matrix notification room

```sh
matrix-notify [-t title] [-q] message
```

- The message goes from the bot account to the user's private
  "Powiadomienia agentów AI" room on the home Matrix server (tailnet only);
  the Matrix app on the phone shows it as a chat notification.
- `-q` sends it as a quiet notice: it lands in the room without a push
  sound. Use it for progress and routine results; leave it out for failures,
  finished long tasks the user waits for, and decisions that block work.
- `-t` adds a bold title line (e.g. the project or task name).
- Keep the message short and self-contained (what finished, result, what is
  needed); the phone shows about two lines.
- Exit status 0 means the server accepted the message; a non-zero status
  means it was not delivered (no network, server down, no bot token for this
  account). Report that to the user instead of retrying in a loop.
- The room is not end-to-end encrypted and the server keeps its history:
  never put secrets, tokens or private data into a message.

Claude Code already notifies on its own when it waits for a permission
decision and (quietly) when a reply ends (managed hooks), so do not send a
notification that only repeats "done" at the end of a reply. Use the command
for events inside a long task, or for a result that should arrive even when
the reply itself is not finished yet.

The bot token is read from a file owned by this account and passed to curl
from that file; never print or copy it.
