---
name: pz-language-server-catches-stranded-refs
description: "lua-language-server is NOT on PATH but ships inside the VS Code Lua extension - it is the only check here doing scope analysis, and skipping it shipped a per-frame crash that lagged the whole machine"
metadata:
  node_type: memory
  type: project
---

`lua-language-server` is not on PATH. It is installed, inside the VS Code Lua extension, and
that copy runs fine from a shell:

```
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" \
  --check=. --checklevel=Warning
```

Run it from the **repo root**, or `.luarc.json` is not picked up. "Command not found" means look
in the extensions folder, never that the gate can be skipped.

**Why this matters more than it looks.** It is the only check in this repo that does scope
analysis. `npm run check` (luaparse) validates syntax and is blind to whether an identifier
exists; there is no test suite ([[pz-verification-is-ingame-only]]). So this tool is the single
thing standing between a deletion and a runtime nil.

**What skipping it cost, 2026-08-22 (`0.4.0`):** a UI rewrite deleted a block that defined a
local `vw`. One line further down still used it in `self.width - PAD - vw - 8 - labelW`. As a
now-undefined global it evaluated to nil, and the game threw:

```
java.lang.RuntimeException: __sub not defined for operands in prerender
```

Inside `prerender`, so it fired **once per rendered frame**. The player's whole PC lagged, not
just the game. luaparse had reported `29/29 parsed` on that exact file.

**How to apply:**

- Run it after **every** Lua change, and especially after any deletion. Assume a deletion has
  stranded a reference until this says otherwise.
- Deleting a block means checking what it _defined_, not only what referenced it. Grepping for
  the removed function name is not enough - locals declared inside the cut are the ones that
  bite, because they silently become globals reading nil.
- A new engine global gets added to `types/pz.lua` with its signature verified against the
  installed game source, rather than silencing the warning. `ISTabPanel` and `triggerEvent` were
  added this way.
- Never "fix" the pre-existing atan2 or duplicate-set-field warnings -
  [[pz-lua-diagnostics-setup]].

Related: [[pz-verification-is-ingame-only]], [[pz-lua-diagnostics-setup]],
[[pz-instrument-before-fixing-runtime-faults]].
