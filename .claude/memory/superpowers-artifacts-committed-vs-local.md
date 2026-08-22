---
name: superpowers-artifacts-committed-vs-local
description: "Superpowers writes into two places in this repo: plans in docs/superpowers/plans/ are committed and carry an execution-status banner, while .superpowers/ brainstorm scratch is gitignored on purpose"
metadata:
  node_type: memory
  type: project
---

The superpowers skills leave artifacts in two different places here, with opposite
handling. Getting it backwards either commits binary mockups or loses a plan.

- **`docs/superpowers/plans/<date>-<slug>.md` — committed.** Written by
  `superpowers:writing-plans`, consumed by `superpowers:executing-plans` or
  `superpowers:subagent-driven-development`. These are project history and are
  reviewed in PRs.
- **`.superpowers/` — gitignored, deliberately.** `superpowers:brainstorming`'s
  visual companion writes JPEG/PNG mockups, generated HTML approach variants, and
  server pid/state files there. It is local scratch. The `.gitignore` entry naming
  it is intentional; do not "fix" it by committing the folder.

**Why:** the brainstorm scratch is bulky binary and per-session state that means
nothing to a clone, while a plan is the only durable record of intent for work that
often cannot be verified by running it. The distinction is not visible from the
skills themselves - both just write files.

**How to apply:**

- A plan in this repo carries a status banner saying whether the code has ever been
  executed, stated bluntly - "written, NOT TESTED ... This code has never been
  executed." Keep that banner accurate rather than quietly dropping it once tasks are
  ticked - ticked tasks mean written, not verified.
- A plan also needs a "Context for the implementer" section. Agents and fresh
  sessions arrive with no repo knowledge, and the chunk-loading constraint that
  governs most restoration logic is not guessable from the code.
- Exact wording and required contents for both sections live in
  `docs/conventions/skills.md` under "What every plan must carry". They are stated
  inline there on purpose: they used to be pointers to an example plan file, which
  broke when that file was deleted.
- Never commit `.superpowers/`. If mockups need to survive, they belong in `docs/`
  as a deliberate choice, not as brainstorm residue.

Related: [[parallel-agents-by-file-ownership]] (how plan tasks get split across
agents), [[no-verification-scaffolding]] (why a ticked task is not evidence),
[[pz-instrument-before-fixing-runtime-faults]].
