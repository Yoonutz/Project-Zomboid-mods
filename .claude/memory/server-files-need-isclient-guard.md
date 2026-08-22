---
name: server-files-need-isclient-guard
description: "Every file under a mod's server/ folder needs `if isClient() then return end`, or it loads on multiplayer clients and calls into functions that bailed out"
metadata:
  node_type: memory
  type: project
  originSessionId: 6f7f4399-c35e-43f1-8a81-ff299ee33083
  modified: 2026-08-22T08:26:05.773Z
---

Every file in a mod's `media/lua/server/` folder must start with
`if isClient() then return end` (after its `require` lines). PZ loads the
`server/` folder on multiplayer CLIENTS too - the folder name is a convention,
not an engine-enforced boundary.

TwoManCrew shipped `TwoManCrew_Campaign.lua` without that guard while the other
eight server files had it. On a multiplayer client the campaign file therefore
loaded, but `TwoManCrew_CrewState.lua` had bailed out, so
`TwoManCrew.Server.getState()` did not exist. The first "Claim a block" press
called a nil value and the button appeared dead. Fixed in 0.1.8.

**Why:** the failure is invisible in singleplayer, where `isClient()` is false
and every file loads, so the whole feature tests clean and only breaks for the
remote player. A guard that is present in 8 of 9 files reads as deliberate, so
nothing flags the ninth.

**How to apply:** when adding any file to `server/`, copy the guard along with
the `require` block. When a client-side feature mysteriously does nothing,
check the guard set for an odd one out before debugging the feature itself.

`isClient()` is false in singleplayer, so the guard does NOT disable a feature
offline - it only skips the file on a remote client. Vanilla uses this exact
pattern in 33 core server files, including `server/ClientCommands.lua`,
`server/Farming/SFarmingSystem.lua`, and `server/Map/SGlobalObjectSystem.lua`,
all of which work in singleplayer. Do not "fix" a working feature by removing
this guard.

Note `isClient()` and `isServer()` are NOT opposites: both are false in
singleplayer, and `isServer()` is false on a co-op/listen host too. See
[[pz-vanilla-source-is-the-api-reference]] for grepping the installed source to
confirm which guard vanilla uses for a given case.
