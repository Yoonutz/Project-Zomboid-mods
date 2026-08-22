---
name: pz-vanilla-source-is-the-api-reference
description: "The installed game ships its full Lua source at D:\\Games\\Steam\\steamapps\\common\\ProjectZomboid\\media\\lua - grep it to verify any PZ API or copy a UI style, instead of trusting docs or memory"
metadata:
  node_type: memory
  type: reference
  originSessionId: a3a676dc-560c-46e9-9fb8-fc132dd1dc04
  modified: 2026-08-22T08:32:50.526Z
---

The installed game ships its complete Lua source, readable and greppable:

```
D:\Games\Steam\steamapps\common\ProjectZomboid\media\lua\{client,server,shared}
D:\Games\Steam\steamapps\common\ProjectZomboid\media\ui        # UI textures
D:\Games\Steam\steamapps\common\ProjectZomboid\media\scripts   # item/recipe scripts
```

This is the authoritative reference for anything the mods touch, and it beats both the
vendored `docs/` snapshot and any recollection. CLAUDE.md already requires verifying unfamiliar
APIs; this is where to do it.

Scale, surveyed 2026-08-22 (Steam buildid 24775755):

| Tree                | Contents                                        |
| ------------------- | ----------------------------------------------- |
| `lua/client`        | 728 files - UI, rendering, input, context menus |
| `lua/server`        | 294 files - authority, ModData, client commands |
| `lua/shared`        | 373 files - both sides, `Definitions/`, helpers |
| `scripts/generated` | 1004 `.txt` - B42 `craftRecipe` item scripts    |
| `ui/`               | 1538 PNGs across 132 folders                    |

`media/` as a whole is far larger (maps, models, sound, textures). Never run `du -sh`
or an unfiltered recursive walk on it - that timed out at two minutes. Scope every
search to a subtree and a file type.

**Why:** every API claim in this repo's mods is checkable in seconds, so an unverified claim is
a choice rather than a limitation. It also settles questions the docs do not cover - whether a
method exists server-side, whether a list is 0-indexed, what a real call site passes.

**How to apply:**

- Verify a function before using it: `grep -rn "getWorldAgeHours" <pz>/media/lua | head`.
  A hit in `server/` proves it is server-safe; only `client/DebugUIs/` hits mean "unproven".
- Match UI style by sampling the real asset, not by eye - but decode the PIXELS, not just
  the mode. Many vanilla icons are greyscale+alpha (`LA`, PNG colour type 4), and copying
  that format alone produced two all-white TwoManCrew icons: every opaque pixel was value
  255, so they rendered as blank squares and nobody noticed until 0.1.8. Print the gray
  range and the transparent-pixel count before accepting generated art; a single-value
  range means there is no shading and the icon is blank. Mod icons may be full RGBA
  (colour type 6) - `getTexture` loads both, so match the art, not the colour type.
- Confirm a pattern is real by finding vanilla doing it - e.g. `Events.OnGameStart.Add` for
  player-dependent UI, `getTexture("media/ui/...")` for textures.
- Distinguish "no verified API" from "no API": several fallbacks in `two-man-crew` exist only
  because nothing in this tree confirmed a server-safe call. Re-grep before assuming a gap.
- Settle "which guard" by counting real usage, not by reasoning. `isClient()` and
  `isServer()` are NOT opposites: both are false in singleplayer. 33 files under
  `lua/server/` open with `if isClient() then return end` and all work solo, which is
  what proves that guard is the right one for server-authority code. See
  [[server-files-need-isclient-guard]].

Related: [[pz-lua-diagnostics-setup]], [[server-files-need-isclient-guard]].
