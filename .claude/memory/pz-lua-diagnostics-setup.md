---
name: pz-lua-diagnostics-setup
description: 'Lua language server in this repo needs .luarc.json + types/pz.lua stubs; run --check from the REPO ROOT or the config is ignored, and never "fix" atan2/duplicate-set-field warnings'
metadata:
  node_type: memory
  type: project
  originSessionId: a3a676dc-560c-46e9-9fb8-fc132dd1dc04
  modified: 2026-08-21T21:22:37.997Z
---

Editor diagnostics for the PZ mods are configured by `.luarc.json` (repo root) plus
`types/pz.lua`, a `---@meta` stub declaring the ~30 engine globals (`getPlayer`, `Events`,
`Perks`, ...). Without it the language server reports ~197 warnings, of which 192 are just
missing API definitions rather than defects. `types/` lives outside every mod's `Contents/`
so it is never packaged into a Workshop release.

**Why:** the warnings are overwhelmingly noise, and noise that large hides the few real
findings. Two of the warnings are the analyser being wrong about the game, and "fixing" the
code to satisfy them would break it or churn a correct pattern:

- `math.atan2` is flagged deprecated. PZ runs Lua 5.1 (Kahlua) where it is current, and
  vanilla itself uses it. `.luarc.json` sets `runtime.version` to Lua 5.1 to stop this.
- `duplicate-set-field` fires on the save-original-then-replace wrap that mods use on
  `ISCraftAction:complete`. Two files wrapping the same method is intended, and the chain
  composes correctly in either load order. Disabled in `.luarc.json`.

**How to apply:** run the checker from the REPO ROOT, never from a mod subfolder - the
config is discovered relative to the checked path, so checking `two-man-crew/` alone silently
ignores `.luarc.json` and reports the full 197 again:

```
"$USERPROFILE/.vscode/extensions/sumneko.lua-<ver>/server/bin/lua-language-server.exe" \
  --check="d:\Dropbox\Apps\Project Zomboid" --checklevel=Warning
```

Expect `no problems found`. When a mod starts using a new engine global, add it to the stub
with a signature verified against the installed game source, never invented - a wrong
signature turns a harmless warning into a confident wrong answer. This complements
`two-man-crew/check-lua.mjs`, which only proves files parse.

Related: [[pz-vanilla-source-is-the-api-reference]], [[pz-mod-state-survives-reinstall]].
