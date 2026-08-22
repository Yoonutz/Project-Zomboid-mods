---
name: no-verification-scaffolding
description: "In this repo, never write tests, probes, or throwaway harnesses to verify a change; verify by diffing against the GitHub repo, then rebase, commit and push, and close with superpowers:verification-before-completion"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3b0bbc25-3b7b-4548-b74b-ad92238ddee6
  modified: 2026-08-22T10:06:43.914Z
---

Do not write tests, probes, measurement harnesses, or any other scaffolding in order to
verify a change to this repo. Kami said it twice, the second time as: _"Stop writing tests,
probes, anything for verification. Just do the damn task you are given."_ Treat any impulse
to build something that proves the work as out of scope.

Verification here is a **diff against the GitHub repo**, not an experiment. Read what
changed, confirm it is what was asked for, and stop.

**Why:** the change itself is the deliverable. A test file, a one-off probe, or a
before/after measurement is surface Kami did not ask for and costs a turn each time. He
rejected the output too - _"They are useless"_ - so this is not only about cost. The work is
judged by reading the diff, the way a reviewer would.

**How to apply:**

- Never author a test file, `probe.mjs`, benchmark, or instrumented copy of a source file to
  prove a change works. Not in the repo, not in the scratchpad, not "throwaway".
- Verify by diff: `git diff origin/master`, `git diff --stat`. Read the change; do not
  execute a constructed scenario around it.
- The repo's OWN existing checks are still fine to run (`npm run check`, `npm test`). Do not
  extend them and do not add cases - `test-ui.mjs` stays as it is unless Kami asks.
- Finish end to end without being asked again: rebase onto the remote, commit, push.
- Close such a turn by invoking `superpowers:verification-before-completion`.

This narrows what counts as evidence for the global verify-before-claiming rules: here it is
the diff plus the repo's existing checks, never a new artifact built to generate proof. When
something genuinely cannot be verified without new scaffolding, report it unverified instead
of building the scaffolding.

Related: [[pz-run-the-ui-not-just-the-parser]] (that memory describes the existing suite -
run it, do not grow it).
