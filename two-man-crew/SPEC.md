# Two-Man Crew - build contract

Shared contract for all feature modules. Every agent building a feature MUST follow
this file exactly. Verified against the installed Build 42.20.3 source in
`D:\Games\Steam\steamapps\common\ProjectZomboid\media\lua`.

## Architecture: dedicated server first

The server is authoritative. Clients detect and request; the server decides and writes.

- **Client Lua** (`42/media/lua/client/TwoManCrew/`) - reads local state, renders feedback,
  sends requests. Never writes shared or rewarded state.
- **Server Lua** (`42/media/lua/server/TwoManCrew/`) - validates every request, owns all
  persistent state, awards all XP and items.
- **Shared Lua** (`42/media/lua/shared/TwoManCrew/`) - constants and pure helpers only.
  No event registration, no state.

Never trust a client-supplied value the server can compute itself. Re-check distance,
skill level, and cooldowns server-side even when the client already did.

## Verified API contract

Signatures below were read from vanilla source. Do not use anything not listed here
without verifying it first in that same source tree.

```lua
-- messaging (verified: client/Context/Inventory/InvContextMedia.lua,
--            client/ISUI/ISWorldObjectContextMenu.lua)
sendClientCommand(playerObj, "twomancrew", "<command>", { key = value })
sendServerCommand(playerObj, "twomancrew", "<command>", { key = value })

-- handlers (verified: server/Camping/camping_tent.lua:183,
--           client/Farming/CFarmingSystem.lua:21)
local function OnClientCommand(module, command, player, args) end
Events.OnClientCommand.Add(OnClientCommand)   -- server side
local function OnServerCommand(module, command, args) end
Events.OnServerCommand.Add(OnServerCommand)   -- client side

-- environment (verified: client/BuildingObjects/TimedActions/ISBuildAction.lua:110,
--              client/DebugUIs/DebugMenu/ISDebugMenu.lua:311)
isServer()      -- true on a dedicated server
isClient()      -- true on a multiplayer client

-- players and proximity (verified: client/Farming/CFarmingSystem.lua:47)
getPlayer()
getSpecificPlayer(i)
player:DistTo(x, y)                    -- vanilla guards with: > 6 then return
player:getX()  player:getY()  player:getZ()
player:getSquare()

-- IsoPlayer.getPlayers() returns a JAVA list, not a Lua array. Never use ipairs on it.
-- Iterate 0-indexed with :size() and :get(i)
-- (verified: client/ISUI/PlayerData/ISPlayerData.lua:186-187)
local players = IsoPlayer.getPlayers()
for i = 0, players:size() - 1 do
    local other = players:get(i)
end

-- skills and XP (verified: client/Farming/CFarmingSystem.lua:32,
--                client/ISUI/PlayerStats/ISPlayerStatsUI.lua:525)
player:getPerkLevel(Perks.Woodwork)
player:getXp():AddXP(Perks.Woodwork, amount, false, false, false, false)

-- danger state (verified: enumerated from getStats() call sites)
player:getStats():getNumChasingZombies()
player:getStats():getNumVeryCloseZombies()
player:getStats():getNumVisibleZombies()

-- feedback (verified: client/Foraging/forageClient.lua:73,
--           client/ServerCommands.lua:182)
HaloTextHelper.addText(player, text)
HaloTextHelper.addBadText(player, text)
player:Say(text)

-- persistence (verified: client/Foraging/forageClient.lua:7)
ModData.getOrCreate("TwoManCrew")       -- shared, server-owned; needs the wrapper
item:getModData()                       -- per-item; returns a plain table directly
player:getModData()                     -- per-player; returns a plain table directly
-- (per-player form verified: client/LastStand/LastStandSetup.lua:77-89)

-- time (verified: server/Farming/SFarmingSystem.lua:90,
--       server/Traps/STrapGlobalObject.lua:535)
getGameTime():getDay()
getGameTime():getHour()

-- Preferred for all cooldown maths: one monotonic float, no day-rollover handling
-- (verified: server/Farming/SFarmingSystem.lua:258, server/radio/ISWeatherChannel.lua:153)
getGameTime():getWorldAgeHours()
```

**Known absent in B42 - do not use:** `getStats():getEndurance()`,
`getStats():getFatigue()`. They do not exist in this build. A profession getter on
`getDescriptor()` could not be verified either, so gate on `getPerkLevel` instead of
profession name.

## Conventions

- Namespace every file path and global under `TwoManCrew` to avoid collisions.
- One file per feature, named after it: `TwoManCrew_WatchMyBack.lua`.
- Module string for all commands is exactly `twomancrew` (lowercase).
- Shared constants live in `shared/TwoManCrew/TwoManCrew_Config.lua`.
- Crew radius default: **12 tiles**. Read it from config, never hardcode in a feature.
- Guard every handler: `if not player then return end` before use.
- `OnPlayerUpdate` runs every tick. Exit early; never allocate tables inside it.
- Comments explain intent, not syntax. Match the density of the vanilla files.

## Definition of done, per feature

- [ ] Client and server halves both present where the feature needs them
- [ ] Server re-validates distance and skill; client never awards anything
- [ ] Degrades silently to a no-op when the player is alone
- [ ] No use of any function absent from the verified list above
- [ ] Passes `npm run check` — parses under luaparse, server guards present, no dangling calls, mod.info copies agree

## Not done here

No in-game testing is possible in this workspace. Every module is a syntax-level
claim until loaded in Project Zomboid and checked against `~/Zomboid/Logs/`.
