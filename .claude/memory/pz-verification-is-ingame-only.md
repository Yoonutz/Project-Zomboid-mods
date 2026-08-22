---
name: pz-verification-is-ingame-only
description: "The fengari UI test harness was deleted by decision on 2026-08-22 - `npm run check` never executes a line, so any behaviour claim about this mod is proved in a real Project Zomboid session or reported Unverified"
metadata:
  node_type: memory
  type: project
---

There is **no local test suite** for this repo, and that is a decision, not a gap to fill.

`two-man-crew/test-ui.mjs` used to run the mod's Lua under fengari against a hand-written
stub of the PZ globals. It was deleted on 2026-08-22 at the owner's instruction, along with
the `test` script and the `fengari` dependency. The reasoning: the stub was our own guess at
the engine, so a green run proved the guess was self-consistent, never that the game agreed.

**Do not rebuild it.** Not as `test-ui.mjs`, not as a "quick harness", not as a probe file
next to the code under test. Proposing a mock of the engine is proposing the thing that was
just removed. See [[no-verification-scaffolding]].

What remains:

| Command               | What it does                     | What it proves about the game |
| --------------------- | -------------------------------- | ----------------------------- |
| `npm run check`       | luaparse over every Lua file     | Nothing. It never runs a line |
| `lua-language-server` | undefined globals, from the stub | Nothing. Static only          |
| `npm run diagnose`    | reads the newest game log        | Real, but only after a run    |

**Why:** the harness was originally built because three user-visible faults shipped while the
static checks were green. Deleting it does not make those checks stronger - it removes the
last thing in the repo that executed any mod code. The honest consequence is that the
reporting bar goes up, not that verification got easier.

**How to apply:**

- A UI or behaviour change is reported `Unverified: not loaded in Project Zomboid`. Never
  "tested", never "works", on the strength of a parser.
- Ask for one real game run and a screenshot. That request is cheap; a wrong build costs a
  round trip. Three builds reasoned from source alone were all wrong -
  [[pz-instrument-before-fixing-runtime-faults]].
- When a fault only appears in-game, ship `print()` calls first and fix what the log names.
  `npm run diagnose` reads the newest log and prints the command chain in order.
- Keep pure logic pure. Functions with no engine call (verdict rules, text builders) are the
  only things that could ever be checked locally, so write them as plain functions taking
  plain tables rather than reaching for globals inside.

Related: [[no-verification-scaffolding]], [[pz-instrument-before-fixing-runtime-faults]],
[[pz-vanilla-source-is-the-api-reference]].
