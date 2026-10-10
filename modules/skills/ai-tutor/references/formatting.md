# Formatting — LaTeX math and the mermaid dependency map

Moved verbatim from SKILL.md (port of upstream `skills/teach` @ 7cfd894; see port-notes.md). SKILL.md keeps the short form of these rules; this file is the full text.

## Math renders as LaTeX

Everything written in a session is a Markdown log that renders LaTeX math natively. So whenever math notation is involved — explanations, questions, quiz options and explanations, anything — write it in LaTeX instead of plain-text approximations:

- Inline math: `$f(x)$`
- Centered display math: `$$` fenced on its own lines, e.g. `$$\n f(x) \n$$`

If LaTeX can be used, it should be. Write $f(x) = x^2$, not `f(x) = x^2`.

## The dependency map (Phase 2)

The plan's backbone is a small ```mermaid``` graph: unconditional truths at the roots, each derived node hanging off what it depends on, the learner's goal as the sink. It *is* the teaching order. Keep it small: few nodes, short labels — a map, not the territory. Full rule: [process.md](process.md), Phase 2; example in the [notebook.md](notebook.md) skeleton.
