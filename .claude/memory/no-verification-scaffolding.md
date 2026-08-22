---
name: no-verification-scaffolding
description: "Never write a test, probe or harness ad-hoc: invoking superpowers:test-driven-development first is mandatory, and without it the answer is no test at all - verify by diffing against GitHub, then rebase, commit, push"
metadata:
  node_type: memory
  type: feedback
---

Do not write a test, probe, benchmark, or measurement harness off your own bat. Writing one
requires invoking `superpowers:test-driven-development` first. Absent that invocation, the
answer is no test at all - verify by diff instead.

Kami, after two rounds of exactly this: _"You don't do the test without invoking that skill.
Which you were constantly doing."_ The objection is not that tests are unwanted. It is that
they kept appearing improvised, mid-task, as a way of proving a change to myself.

**Why:** the skill exists to make tests deliberate - written before the fix, watched fail,
then watched pass. A test invented after the fact to demonstrate a change already made is a
different thing wearing the same name: it cannot fail, so it proves nothing, and it costs a
turn. Both of the ones written in this repo were thrown away, one of them as _"useless"_.

**How to apply:**

- Fix asked for, no test mentioned → make the fix. Verify with `git diff origin/master` and
  the repo's own checks. Do not invent a probe, an instrumented copy, or a before/after
  measurement, in the repo or the scratchpad.
- A test genuinely belongs → invoke `superpowers:test-driven-development` and follow it,
  including the red-green step. Never hand-roll one beside it.
- The repo's existing checks are always fine to run: `npm run check` (parses 29 Lua files),
  Running it is not authoring a test. There is no local suite to add cases to -
  the fengari UI harness was deleted 2026-08-22, see
  [[pz-verification-is-ingame-only]].
- Finish end to end without being asked again: rebase onto the remote, commit, push.
- Close the turn by invoking `superpowers:verification-before-completion`.

Where this leaves the global verify-before-claiming rules: evidence here is the diff plus the
repo's existing checks. When something cannot be verified without new scaffolding - anything
needing the game to actually run - report it unverified rather than building scaffolding to
manufacture proof.

Related: [[pz-run-the-ui-not-just-the-parser]] (what the existing suite covers - run it),
[[pz-instrument-before-fixing-runtime-faults]] (instrumenting the live game is a different
activity from writing a test, and is still the right move for a runtime fault).
