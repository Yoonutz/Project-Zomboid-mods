---
name: pz-runs-lua-5-1-kahlua
description: "PZ runs Lua 5.1 via Kahlua, so the current lua.org manual is the wrong reference; docs/lua-language-reference.md holds the link and the 5.2+ trap list"
metadata:
  node_type: memory
  type: project
  originSessionId: f7f25fd5-cc96-4376-8fe8-902f0e8bc06e
  modified: 2026-08-22T09:21:08.131Z
---

Project Zomboid embeds **Kahlua**, a Java implementation of **Lua 5.1**. Lua's current
release is 5.5, so the default lua.org manual link is the wrong one for this repo.

Correct reference: <https://www.lua.org/manual/5.1/manual.html>

`docs/lua-language-reference.md` (added 2026-08-22) records this plus the deviations.
Read it before writing base-Lua code; it separates base-language questions from the
PZ-API questions that `docs/api-documentation-sources.md` routes.

**Why:** the 5.2+ features that do not exist here (`goto`/`continue`, `table.unpack`,
`//`, bitwise operators, integer subtype, `load` on a string, `\z`/`\x` escapes) all
look correct to anyone working from a current manual, and fail only at runtime in-game
where this environment cannot test them.

**How to apply:** consult the 5.1 manual, never the current one. Two specifics that bite
most: `require` takes **slash** paths relative to a `media/lua/{client,server,shared}`
root (1,112 slash-form uses in the shipped source, zero dot-form), and `unpack` is the
global, not `table.unpack`. The shipped game uses `io` zero times, `coroutine` zero,
`debug` zero, `pcall`/`xpcall` zero, and `os` exactly once (`os.date`) - errors are
normally left to surface in `~/Zomboid/Logs/` rather than caught locally.

Zero-usage counts show what is idiomatic, not a hard proof a function is absent. Verified
by word-boundary grep over the shipped source - see
[[pz-vanilla-source-is-the-api-reference]], which stays the highest-confidence check.

Related: [[pz-api-doc-sources-ranked]], [[pz-lua-diagnostics-setup]].
