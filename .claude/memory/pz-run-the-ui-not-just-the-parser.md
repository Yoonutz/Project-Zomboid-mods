---
name: pz-run-the-ui-not-just-the-parser
description: "Run TwoManCrew's UI logic under fengari via `npm test` - the luaparse check and the language server both pass on UI that is completely broken"
metadata:
  node_type: memory
  type: project
  originSessionId: 22191151-f982-426b-8b95-9c0e6caccbb7
  modified: 2026-08-22T09:30:40.660Z
---

`node check-lua.mjs` (luaparse) and `lua-language-server --check` do **not execute a single
line**. They catch syntax and undefined globals, nothing else. Both passed cleanly on
TwoManCrew 0.2.0 while the crew widget was unclickable, the drag snapped out, and Claim never
produced an answer. Three user-visible faults, zero signals.

`two-man-crew/test-ui.mjs` (`npm test`) runs the mod's real Lua under a Lua 5.3 VM
(**fengari**) against a stub of the PZ globals the UI touches. The stub's whole point is that
it models `javaW`/`javaH` as a **separate rectangle** from the Lua fields and hit-tests
against the Java pair, exactly as the engine does - so it can catch
[[pz-ui-size-must-go-through-setters]], which no static tool can see.

**Why:** "29/29 parsed" and "no problems found" read like proof and are not. Reporting them as
verification of a UI change is how three broken builds reached the player, twice with a
confident checklist attached.

**How to apply:**

- Any change to a `client/` UI file: run `npm test` in `two-man-crew/`, not just `npm run check`.
- **Red-green every fix.** A test written against fixed code proves nothing. Reintroduce the
  bug, watch the test fail with the user's symptom, restore, watch it pass. The first version
  of this suite passed against deliberately broken code because setup happened to create the
  element at the right size - only a test that changes size _after_ creation exposed it.
- Assert the user-visible fact (is it clickable, did the drag travel the full distance, how
  many messages appeared), never an internal field.
- **Assert that the result is USABLE, not merely well-placed.** The suite passed 28x22 icon
  buttons holding a 14px icon - smaller than the text labels they replaced - because every
  button assertion was about position and none about size. The user reported them as "bugged
  and small" while the suite was green. There is now a size floor, and it fails the old numbers.
- The harness runs fengari (Lua 5.3); the game runs Kahlua (Lua 5.1). The stub shims that gap
  and a dialect check rejects 5.2+ syntax in mod code - see [[pz-runs-lua-5-1-kahlua]]. Without
  it the suite would pass code the game cannot run.
- **A green suite says nothing about whether the mod works in-game.** When the fault only
  reproduces in Project Zomboid, instrument and read the log instead of reasoning from source:
  [[pz-instrument-before-fixing-runtime-faults]].
- Even a green suite is not "verified in game" - the stub is not PZ. Say `Tested locally only`
  until it has actually run in Project Zomboid.
- `package.json` pins `luaparse` and `fengari`; installing one with `--no-save` used to evict
  the other. Use `npm install`.

Related: [[pz-ui-size-must-go-through-setters]], [[pz-vanilla-source-is-the-api-reference]].
