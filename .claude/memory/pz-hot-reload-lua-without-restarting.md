---
name: pz-hot-reload-lua-without-restarting
description: "reloadLuaFile() re-executes a mod Lua file in the running game, so UI iteration needs no restart - but it is only safe for files that register no events, and the window must be closed first or a ghost keeps rendering the old code"
metadata:
  node_type: memory
  type: reference
---

`reloadLuaFile(path)` is a real engine global that re-executes a Lua file in the running game.
The game's own debug tooling uses it (`client/DebugUIs/LuaFileBrowser.lua:100`,
`client/DebugUIs/SourceWindow.lua:28`, `server/metazones/metazoneHandler.lua:71`).

Mod files are reachable: `getLoadedLua(i)` over `getLoadedLuaCount()` enumerates every loaded
file including mods, which is how the debug browser builds its list
(`LuaFileBrowser.lua:59-70`). So the path never has to be guessed:

```lua
for i=0,getLoadedLuaCount()-1 do local p=getLoadedLua(i)
if string.contains(p,"TwoManCrew_JournalWindow") then reloadLuaFile(p) print("RELOADED "..p) end end
```

Paste that into the in-game Lua command line.

## The three limits, all load-bearing

**1. Close the window first.** The file re-executes
`TwoManCrewJournalWindow = ISCollapsableWindow:derive(...)`, which builds a _new_ class table
with `instance = nil`. Any window still open belongs to the OLD table and keeps rendering the
old code forever, while the next toggle opens a second one. Close, reload, reopen - in that
order.

**2. Only files that register nothing at load.** A file whose top level calls
`Events.X.Add(fn)` registers a SECOND handler on reload, and the old one is never removed. In
TwoManCrew, `TwoManCrew_JournalWindow.lua` registers nothing and is safe; `CrewPanel`,
`Campaign`, `CrewReport`, `TierReport`, `SharedApprenticeship`, `TwoManCarry`, `WatchMyBack`,
`DistressCall` and most `server/` files all register events and must NOT be hot-reloaded.
Restart the game for those.

**3. Lua only.** Textures, `mod.info`, and anything read at mod-load time are unaffected. A
version bump does not take effect.

**Why:** the workspace cannot run the game, so every UI change costs a full restart round trip
to see. For the one file that carries the whole journal UI, this turns that into a few seconds.
It does not weaken the reporting rule - a hot-reloaded change is still
[[pz-verification-is-ingame-only]] until it has been seen on screen.

Related: [[pz-verification-is-ingame-only]], [[pz-vanilla-source-is-the-api-reference]].
