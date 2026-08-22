---
name: pz-instrument-before-fixing-runtime-faults
description: "For a PZ fault that only appears in-game, add logging and read ~/Zomboid/Logs FIRST - three TwoManCrew builds were shipped on code-reading alone and all three were wrong"
metadata:
  node_type: memory
  type: project
  originSessionId: 22191151-f982-426b-8b95-9c0e6caccbb7
  modified: 2026-08-22T09:30:28.191Z
---

On 2026-08-22 three consecutive TwoManCrew builds were shipped to fix "Refresh does nothing"
and "Claim only says Surveying". Each fix was derived by reading the code and reasoning about
what must be happening. **All three were wrong**, and each one cost a full round trip with the
user, who had to keep reporting the same unchanged symptoms.

The mod is client Lua talking to server Lua over `sendClientCommand` / `OnClientCommand` /
`sendServerCommand`. When a button appears dead, the break is at exactly one of four points,
and reading the source cannot tell you which:

1. the server file never loaded (guard, load order, an error at file scope),
2. the client never sent,
3. the server never received,
4. the server received but its reply never arrived.

**Why:** this environment cannot run Project Zomboid. Every conclusion about runtime behaviour
is therefore a hypothesis, and a plausible one is indistinguishable from a correct one until
the game prints something. Shipping the hypothesis wastes a build AND the user's time, and
three in a row destroys trust far more than saying "I need one run to find out".

**How to apply:**

- A fault that only reproduces in-game gets **instrumentation first, fix second**. Add `print()`
  at each candidate break point, ship that, ask for one run, then fix what the log names.
- `print()` output lands in `~/Zomboid/Logs/<timestamp>_DebugLog.txt`. `npm run diagnose` reads
  the newest log and prints the chain in order, so the first `NO` is the broken link.
- **Check the log's timestamp against the install's.** A log written before the deploy says
  nothing about the new build; twice this session an old log nearly produced a false conclusion.
- Asking the user for one two-minute run is cheaper than one wrong build. Ask early.
- A green `npm test` is not evidence about the game - the stub is not PZ. See
  [[pz-run-the-ui-not-just-the-parser]].

Related: [[pz-run-the-ui-not-just-the-parser]], [[pz-ui-size-must-go-through-setters]],
[[pz-runs-lua-5-1-kahlua]].
