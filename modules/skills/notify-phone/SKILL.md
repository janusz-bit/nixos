---
name: notify-phone
description: Send a push notification to the user's phone with `notify-phone`. Use when the user asks to be notified, pinged or told on their phone, or asks to be told when something finishes (a long build, CI, a VM test, a download), and when work they are waiting on away from the computer ends or needs their decision.
---

# notify-phone — push notification to the user's phone

```sh
notify-phone [-t title] [-p priority] message
```

- `priority`: 1 min, 2 low (silent), 3 default, 4 high, 5 urgent. Use 4
  only for failures or decisions that block work, 5 never unless asked.
- Keep the message short and self-contained (what finished, result, what
  is needed); the phone shows about two lines.
- Exit status 0 means the server accepted the message; a non-zero status
  means it was not delivered (no network, server down, no token for this
  account). Report that to the user instead of retrying in a loop.

Claude Code already notifies on its own when it waits for a permission
decision and when a reply ends (managed hooks), so do not send a
notification that only repeats "done" at the end of a reply. Use the command
for events inside a long task, or for a result that should arrive even when
the reply itself is not finished yet.

The token is read from a file only this account or service can read and
passed to curl from that file; never print or copy it.
