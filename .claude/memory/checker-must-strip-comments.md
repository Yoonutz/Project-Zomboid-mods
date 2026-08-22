---
name: checker-must-strip-comments
description: "A text-search check for a code pattern passes on a file whose code was deleted but whose explaining comment survives - strip comments before matching, and prove every check red before trusting it green"
metadata:
  node_type: memory
  type: project
---

Any check in `two-man-crew/check-lua.mjs` that looks for a code pattern must strip
Lua comments first. The `isClient()` server-guard check did not, and it silently
passed on a file whose guard had been deleted.

The mechanism is worth understanding, because it will recur. The guard ships with a
comment above it explaining why it exists, and that comment necessarily contains the
words it is explaining:

```lua
-- where the guarded server files have bailed out. isClient() is false in
-- singleplayer, so this does not disable anything offline.
if isClient() then return end
```

Delete the last line and a search for `isClient()` still matches, because the comment
carries the string. The check reported `server guards  ok` on a file it should have
failed. Self-documenting code and text-searching checks are actively hostile to each
other: the better the comment, the more reliably it defeats the check.

**Why this one mattered:** the check existed specifically because that guard rule had
already shipped broken twice. A check that cannot fail is worse than no check, because
its green output is read as proof.

**How to apply:**

- Strip comments before matching: `text.replace(/--\[\[[\s\S]*?\]\]|--[^\n]*/g, '')`.
- Match the statement, not the token. `isClient()` appears in prose;
  `if isClient() then return end` does not.
- **Prove every check red before trusting it green.** Break the real thing it guards -
  delete a guard, rename a function, drift a version - and confirm exit 1. Then restore
  and confirm exit 0. All three checks in the gate were verified this way, and this is
  the only one of the three that turned out to be broken. Reading the code did not
  reveal it; running it red did.

The same trap applies to the dangling-call scan, which matches call sites by regex.
A commented-out call would count as a live one.

Related: [[server-files-need-isclient-guard]], [[pz-verification-is-ingame-only]],
[[no-verification-scaffolding]].
