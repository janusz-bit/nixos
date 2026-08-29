# Port notes — provenance & deviations

**Source:** https://github.com/amosblomqvist/learn — `skills/teach/SKILL.md`, upstream
commit 7cfd894 ("updated thumbnail", latest master). Ported 2026-08-30 as a
line-faithful port on user request ("wierniejszy port anglojęzycznego teach"),
replacing the earlier Polish distillation of the same methodology.

## Kept (verbatim intent, whole sections)

- The two principles and the full philosophy (connected vs lone facts, "the
  click", the brain-won't-commit mechanism).
- Principle i — unconditional truths first, the unconditional-truth-vs-axiom
  terminology block, the two strong forms (universal statements / atomic units,
  real definitions).
- Principle ii — "How could I have discovered this?", Socratic vs expository.
- The full process: probe (edge bracketing: floor+ceiling, all-correct →
  escalate, binary search, one-wrong → characterize, map every strand),
  plan (present prose + DAG, stress-test roots, **stop and wait for approval**),
  teach (per-node loop: motivate → establish → connect → quiz-check).
- The quiz-option construction procedure (bare-claim options, mutate the
  correct claim into distractors, no asymmetric bolding, regenerate don't patch).
- Formatting — LaTeX mandatory; accuracy non-negotiable paragraph.

## Deliberate deviations

1. **De-personalized.** Upstream is written for one specific learner
   (he/him throughout); here: the user / the learner / they.
2. **Tool substitution** (pi runtime → this agent), see "Tools & substitutes"
   in SKILL.md: `quiz` → graded chat questions; `ask_user_question` → open chat
   question; `researcher` → research/web-search tooling (weakened fallback
   stated explicitly where verification is impossible).
3. **Language directive added** (upstream had none — it wrote in English for an
   English learner): Polish default, mirror-the-learner rule.
4. **Session log** section + `references/notebook.md` added — a port of the
   upstream `md-log` extension; absorbs the local feature added in eb484d1.
5. **Provenance note** added at the top of SKILL.md.
6. Frontmatter `name` kept as `ai-tutor` (deployment identity, nix module path),
   description rewritten to add Polish trigger phrases to the upstream trigger
   ("Use ANY time you're explaining or teaching").
7. Rendering target: upstream assumed an Obsidian-rendered log; here a plain
   `.md` file, Obsidian-compatible (LaTeX + mermaid render natively there).

## Dropped from the previous local `ai-tutor` (deliberate, for fidelity)

Dedicated-teacher framing block, the zero-passive-consumption rule, the
single-notation rule, the "20 small steps" rule, the per-node visualization
step (upstream `teach` has none — visuals belong to the upstream `visualize`
skill, which is NOT ported here), the mandatory closing phase (kept only as an
optional notebook add-on), and the praise/directness style block. The previous
Polish version remains in git history: commits cfa7525, eb484d1.

## Not ported (out of scope)

- `skills/visualize` and the maker subagents (`mermaid-maker`, `svg-maker`,
  `researcher`) — they require a subagent runtime and the `visual-tools`
  extension. Upstream README: the system also works without them ("the main
  session does the teaching"), just without background verification and
  generated visuals. If this agent ever gains subagents, port `visualize` next.
- The pi extensions (`quiz.ts`, `ask-user-question.ts`, `md-log.ts`,
  `visual-tools`) — behavior is inlined in SKILL.md instead.
