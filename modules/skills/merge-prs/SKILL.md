---
name: merge-prs
description: Take open pull requests of the current GitHub repository all the way to merged, one at a time - rebase each onto the default branch, prove it works with the repository's own checks and CI, fix what fails, merge it and push the default branch. Use when the user asks to merge, land or ship all open PRs (or the named ones), to finish pull requests, or to get work merged into main/master and pushed.
---

# merge-prs: verify, merge and push open pull requests

Asking for this skill is the user's permission to merge the PRs in scope, to
push the default branch through those merges, and to force-push a PR's own
branch with `--force-with-lease` after a rebase. Nothing else: never push or
force-push the default branch directly, never use `gh pr merge --admin` or
any other bypass of branch protection, never close a PR or delete data
without asking.

The repository's own instructions (AGENTS.md, CLAUDE.md, CONTRIBUTING) win
over this skill wherever they are stricter: their verification steps, commit
style, rules for when a push is allowed (a push can be a deployment) and
steps only the user may run. Read them before the first PR.

## 1. Scope

```sh
gh repo view --json nameWithOwner,defaultBranchRef,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
gh pr list --state open --json number,title,author,headRefName,isDraft,isCrossRepository,baseRefName
```

- The user named PRs: only those. Otherwise every open, non-draft PR
  against the default branch. Work on the current branch that has no PR yet
  counts too: push it and open one (`gh pr create`, title and body in the
  repository's commit style) before continuing.
- PRs by someone other than the authenticated user (`gh api user --jq
  .login`) or from forks: read the diff before running anything from it
  (builds, tests and hooks execute its code), and ask before merging it.
- Drafts stay out unless the user named them.
- Order: oldest first, but a PR another one builds on goes first. If two
  PRs conflict or one makes another obsolete, ask which one wins.

Handle the PRs one at a time: every merge moves the default branch, so the
next PR is rebased and verified against the new one.

## 2. Bring the PR up to date

Work in a separate worktree or a clean checkout, never on top of
uncommitted changes. Never use a bare `git stash`.

```sh
git fetch origin
gh pr checkout <n>
git rebase origin/<default>
```

Resolve conflicts by understanding both sides, not by taking one side
wholesale. If the resolution changes behaviour or is not obvious, ask. Push
the rebased branch with `git push --force-with-lease`.

## 3. Prove it works

Proof is output you saw yourself in this session, on the latest head:

- Run what CI runs (lint, format check, type check, tests, build) locally
  when it is feasible, plus the verification the repository's instructions
  require for the files the PR touches. In a Nix flake that is at least
  evaluating every affected output; follow the repository's rules about
  expensive builds (ask before multi-hour compiles).
- Check that the diff does what the PR title and description claim; a
  green CI run on a PR that does something else is not proof.
- Step that needs root, a real device or the user (activation, deployment,
  hardware): ask the user to run it and report back, or ask whether to merge
  without it. Never claim it ran.

A failure the PR caused: fix it on the PR branch with the smallest change
that works, commit in the repository's style, push, verify again. A failure
that is not the PR's (flaky test, infrastructure, an older bug on the
default branch): re-run the job once (`gh run rerun <id> --failed`); if it
fails again, report it and ask instead of patching unrelated code into the
PR.

## 4. Wait for CI and reviews

Never write a polling or `sleep` loop.

- T3 Code: `watch_pull_request`, end the turn; a wake is news, not a merge
  decision. `unwatch_pull_request` before handing back without a merge.
- Elsewhere: `gh pr checks <n> --watch --fail-fast` as one long command (it
  ends on its own), then `gh pr checks <n>` for the result.

Read every review and comment newer than the last push. Verify each bot
finding against the source: fix real ones, reply to false positives with a
written reason. Keep the PR at the size its goal needs; extra suggestions
become follow-ups in the report, not new code.

## 5. Merge gate

Merge only when all of these hold on the latest head:

- Your proof covers the whole diff.
- Required checks are green (no required checks: every check that ran is
  green, or its failure is explained and accepted by the user).
- No review requests changes; every finding is fixed or answered.
- `gh pr view <n> --json mergeable,mergeStateStatus` reports `MERGEABLE`
  and not `BEHIND`/`DIRTY`. Run `git fetch` right before; if the default
  branch moved, go back to step 2.

Merge with the method the repository uses (allowed methods above, recent
merged PRs: `gh pr list --state merged --limit 5`, `git log --first-parent
origin/<default>`):

```sh
gh pr merge <n> --merge|--squash|--rebase --delete-branch
```

The merge lands on GitHub, so that is the push of the default branch. With
a merge queue or auto-merge, stay until GitHub reports the PR as `MERGED`.
Then update the local default branch: `git fetch origin` and `git merge
--ff-only origin/<default>` on it (never a merge commit or a force-push
there). If it has local commits that are not on origin, do not push them as
part of this skill: list them in the report.

## 6. Report

One table, one row per PR: number and title, what was fixed, how it was
proven (commands and their result), merge commit or why it was not merged.
Then the decisions you made for the user, follow-ups, and anything left for
the user to run.

## Asking

A question at the end of a long run goes unseen. Use the harness question
tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) with
the PR link, what blocks it and the options, your recommendation first. While
waiting, continue with the PRs that do not depend on the answer. Without a
question tool, leave the blocked PR open and unmerged and start the final
message with the question.
