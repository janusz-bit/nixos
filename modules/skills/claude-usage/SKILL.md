---
name: claude-usage
description: Check how much of the user's Claude subscription limits is left (5-hour session, weekly all-models, weekly per-model, paid extra usage) and when each resets. Use before starting large or expensive work (multi-agent workflows, many subagents, long refactors, big reviews), when the user asks about remaining usage, limits or quota, and when deciding whether a task fits before a limit resets.
---

# claude-usage — remaining Claude subscription limits

CLI: `claude-usage` (installed with this skill). It reads the Claude Code
OAuth token from `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json` and
queries `GET https://api.anthropic.com/api/oauth/usage` — the same data
Claude Code's `/usage` screen shows. The token is passed to curl on stdin,
never on the command line; do not print or copy it yourself.

```sh
claude-usage          # one line per limit, local time
claude-usage --json   # raw API response (all fields, e.g. seven_day_breakdown)
```

Example output:

```
session (5h): 4% used, resets 2026-11-06 11:19 CET (in 4h 15m)
weekly (all models): 25% used, resets 2026-11-11 14:59 CET (in 5d 7h 55m)
weekly (Fable only): 0% used, resets 2026-11-11 15:00 CET (in 5d 7h 55m)
extra usage (paid credits): off
```

A `[warning]`-style suffix appears when the API marks a limit with a
severity other than `normal`.

## Reading it

- The limits are shared by everything on the account: Claude Code sessions
  (this one and any others running in parallel), claude.ai chats, Cowork.
- Hitting any one limit blocks work until its reset; the effective headroom is
  the smallest remaining one that applies to the current model. A per-model
  weekly limit applies only to that model.
- The API reports percentages, not tokens. There is no fixed "N tokens left";
  cost depends on model, context size, caching and effort level.

## Planning work against the limits

1. Run `claude-usage` before a large task and note the numbers.
2. For a rough burn rate, run it again after a representative chunk of work
   (one subagent, one phase) and extrapolate from the delta. Percentages are
   whole numbers, so measure over a chunk large enough to move them.
3. If the estimate does not fit before the relevant reset, tell the user and
   propose options: a smaller scope, fewer parallel agents, a cheaper model or
   lower effort for subagents, or waiting until the reset time.
4. Do not poll it in a loop; check at natural boundaries of the work.

## Failures

- `brak .../.credentials.json`: Claude Code is not logged in for this user
  (`claude auth login`), or credentials are stored elsewhere.
- HTTP 401: the access token expired. Any running Claude Code session
  refreshes it; retry after the next model request.
- The endpoint is internal and undocumented, so its schema may change. If the
  summary breaks, `claude-usage --json` still shows the raw response.
