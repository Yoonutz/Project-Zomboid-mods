---
name: pz-chunk-free-evidence-sources
description: "Registered SGlobalObjectSystem classes (trough, rain barrel, farming, campfire, trap) read map-wide without loading ground; generators are NOT one of them and live in the Java-side SGlobalObjects registry, only ever called from client debug tooling"
metadata:
  node_type: memory
  type: project
---

Chunk loading is the constraint that shapes every TwoManCrew campaign check: a dedicated
server only simulates squares near online players, so `getCell():getGridSquare(x, y, z)`
returns `nil` for anything else. There are exactly two ways around it, and knowing which
applies decides whether a tier can be checked map-wide or only where somebody is standing.

**Way one, the MetaGrid** — buildings and rooms, keyed by x/y alone. Already used by
`TwoManCrew_Campaign.lua`.

**Way two, registered Lua global object systems.** Their positions and state live in system
ModData rather than on the square, so they read map-wide. Verified in the installed Build
42.20.3 source, the complete list of `SGlobalObjectSystem.RegisterSystemClass` calls:

```text
SCampfireSystem       server/Camping/SCampfireSystem.lua:171
SFarmingSystem        server/Farming/SFarmingSystem.lua:580
SFeedingTroughSystem  server/FeedingTrough/SFeedingTroughSystem.lua:55
SRainBarrelSystem     server/RainBarrel/SRainBarrelSystem.lua:66
STrapSystem           server/Traps/STrapSystem.lua:130
```

Each exposes `.instance` (set at `server/Map/SGlobalObjectSystem.lua:241,246`) and the
`getLuaObjectCount()` / `getLuaObjectByIndex(index)` pair (`:40,44`), which is exactly the
pattern the existing L1 trough check already uses. Rain barrels and crops are therefore
readable the same way, no new engine surface needed.

**What is NOT on that list: generators.** They live in the Java-side registry instead,
reached as `SGlobalObjects.getSystemCount()` / `getSystemByIndex(i)`, then
`system:getObjectCount()` / `getObjectByIndex(i)` / `getObjectAt(x, y, z)`, then
`system:getModData():getIsoObjectAt(x, y, z)` for the `IsoObject` that answers
`isActivated()`, `getCondition()` and `getFuel()`.

**Why:** every call site of `SGlobalObjects` in the installed tree is client-side debug
tooling (`client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectStateUI.lua:252,253,266,267,283`
and `DebugGlobalObjectState_PropertiesPanel.lua:161,175,177`). So whether a `server/` file
can reach it is unproven, and `getIsoObjectAt` returning an `IsoObject` suggests running
state is a loaded-ground read even if position is not. Treating that as settled would be
another build reasoned from source, which is how three wrong builds shipped here.

**How to apply:**

- Structure to check map-wide → is there a registered system for it? If yes, use
  `.instance` and the Lua object list, never a square scan.
- No system for it (hutches, generators, walls) → the check is presence-only, and its
  verdict for unloaded ground is _unknown_, never _absent_.
- Before building anything on `SGlobalObjects`, ship the probe in
  `docs/superpowers/plans/2026-08-23-evidence-probe.md` and read the log.

Related: [[pz-instrument-before-fixing-runtime-faults]],
[[pz-vanilla-source-is-the-api-reference]], [[pz-journal-campaign-is-task-cards]].
