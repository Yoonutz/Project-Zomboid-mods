# Declarative tier model, and three new campaign tracks

> **STATUS: design approved, NOT IMPLEMENTED. 2026-08-23, repo version `0.3.1`.**
>
> **This code has never been executed.** No Project Zomboid session has loaded it.
> Nothing below is known to work.
>
> What actually ran while writing this document: source reading of the installed
> Build 42.20.3 Lua tree, and source reading of two Steam Workshop quest mods.
> None of that executes a line of the mod. It is proofreading, not testing — it
> cannot catch a wrong method name, a nil at runtime, a wrong event, or a UI that
> draws garbage.
>
> Every in-game check is OPEN.

## Context for the implementer

Read this section before touching a file. The constraints below cannot be guessed
from reading the code.

**What the mod is.** TwoManCrew is a two-player co-op mod for Project Zomboid
Build 42. Two survivors work as a crew: a Lumberjack and a Carpenter. Features
reward proximity and shared labour. The campaign layer asks the crew to claim one
ruined town block and restore it, tracked as nine tiers across two tracks
(five building tiers, four livestock stages). Multiplayer is the assumption, not
an afterthought: code paths differ between the host and a remote client, and a bug
invisible in singleplayer can still be real.

**The constraint that will be violated.** Chunk loading. A dedicated server only
simulates `IsoGridSquare` objects near online players, so
`getCell():getGridSquare(x, y, z)` returns `nil` for anything outside that window.
A building far from a player is _unreadable_, not unrestored. The three-state
verdict (`pass` / `fail` / `unknown`) is load-bearing and must never be collapsed
to a boolean. This design exists partly to make that verdict structural rather
than a convention each check remembers separately.

**Where chunk-free data comes from.** Two sources, both already used by this mod:

- The MetaGrid, for buildings and rooms. Keyed by x/y alone, no square load.
- Server-side global object systems, for troughs and — new in this design — rain
  barrels and crops. Their positions and state live in system ModData, not on the
  square.

**How verification works here.** There is no unit-test harness for engine code,
because it calls globals (`getCell`, `getWorld`, `IsoPlayer`, `instanceof`) that
exist only inside the running game. The fengari UI harness was deleted by
decision on 2026-08-22. Do not invent a mock harness mid-plan.

The real gates are:

- `npm run check` from `two-man-crew/` — parses every Lua file. Proofreading only.
- `lua-language-server --check=.` from the repo root — the only scope-aware check,
  so it is the only one that catches a variable a deletion stranded.
- A Project Zomboid session. Nothing else proves behaviour.

**Which sub-skill implements this.** `superpowers:executing-plans`, because the
tasks share files heavily. If parallel agents are used at any point, partition
them by file and never by task number, per
`.claude/memory/parallel-agents-by-file-ownership.md`.

## The problem

Tier evaluation lives in `TwoManCrew_Tiers.lua`: 962 lines, of which 428 are code
and 457 are comments citing the verified engine API for every call. The comment
density is deliberate repo policy and is not the problem.

The problem is threefold.

1. **Adding a tier means editing a branch.** `evaluateBuildingTier` and
   `evaluateLivestockStage` are `if tier == N` ladders. A new track means a new
   ladder and a new set of accessors alongside it.
2. **Evidence is gathered per pass, not per need.** The animal census, the trough
   scan and the hutch scan all run on every pass regardless of which tiers are
   still unreached. New tracks would each add another world scan to that pass.
3. **The three-state verdict is a convention, not a type.** Some checks return
   `nil` for "cannot tell" and let the caller decide; others return `false` for
   both "no" and "cannot tell". `evaluateBuildingTier` returns a plain boolean,
   so an unreadable claim and a failed claim are indistinguishable at that
   boundary.

A separate, smaller problem motivated the review: `GOALS.md` states that tier 5
gains an extra condition, that the claimed block supports living animals. The code
does not implement it. `GOALS.md` also documents eleven progress counters, of
which only `pensBuilt` and `hutchesBuilt` exist.

## The design

### Layer 1: Tier

A tier is data. It carries an id, the track it belongs to, a display name, a
description, and an ordered list of tasks. Tiers are declared in a new shared
file and registered into a table, not written as branches.

A tier's persisted state stays exactly what it is today: a single reached flag
under `state.tiers`, sparse-safe, flipped false to true exactly once per save.
The existing idempotency rule is unchanged — an already-true tier is never
re-evaluated, so the flip itself gates the announcement and the journal write.

### Layer 2: Task

A task is data. It carries an id, a display name, the id of the condition that
answers it, and a parameter table for that condition.

Tasks are the unit the Journal can show. A tier with three tasks can render three
lines with independent marks, instead of one all-or-nothing line. This is what
makes "Tier 2 is blocked because the three restored houses are not adjacent"
expressible without a hand-written `buildingRemaining` string per tier.

Task state is derived, not persisted. It is recomputed each pass from the same
evidence the tier verdict uses. Only tier reached flags persist, which keeps the
save schema additive and keeps old saves loading cleanly.

### Layer 3: Condition

A condition is the only code layer. It is a function registered under an id,
called as `condition(context, params)`, returning one of three verdicts:

- `pass` — the condition is met, proven from observed game state.
- `fail` — the condition is not met, proven from observed game state.
- `unknown` — the game could not be read. Unloaded ground, a missing global object
  system, or a claim recorded before footprints existed.

`unknown` is never treated as `fail`. A tier containing any `unknown` task is
reported as unknown, not as failed, and does not flip its reached flag.

Conditions are pure with respect to the world: they read the context and their
params and return a verdict. They do not scan the world themselves. That is what
makes them cheap enough for nine plus tiers to share one pass.

### The context

Evidence is gathered once per evaluation pass and handed to every condition. The
context is built lazily per evidence kind: a scan runs only if some unreached
tier's tasks actually ask for it.

Evidence kinds in this design:

- claim geometry (bounds and per-building footprints, from the existing claim)
- restoration counts and adjacency (existing)
- animal census (existing)
- trough scan (existing)
- hutch scan (existing)
- rain barrel scan (new)
- crop scan (new)
- generator scan (new, pending probe)
- perimeter survey (new)

Lazy gathering is the mechanism that keeps three new tracks from tripling the cost
of the `EveryTenMinutes` pass. Once the water tier is reached, its scan stops
running for the rest of the campaign.

### Public surface

`TwoManCrew.Server.getTierProgress()` keeps its current shape, because the client
UI depends on it. It gains one additive field: a per-tier task list with each
task's name and verdict. Existing consumers that ignore the new field keep
working unchanged.

## The five tracks

### Track A: the tier 5 animal gap

Tier 5 gains a task requiring the claimed block to support living animals, as
`GOALS.md` already specifies. Reuses `censusNearbyAnimals()`, which already runs
in the same pass. No new engine surface.

Because the census is a proximity count on simulated ground, its verdict is
`unknown` when no crew member is on the block, never `fail`.

### Track B: water

A new track asking the crew to make the block self-sufficient in water.

Evidence comes from the rain barrel global object system, which is registered the
same way the feeding trough system is. That means barrel positions and water
levels are readable map-wide without loading the ground, exactly like the existing
L1 trough check.

Verified against the installed Build 42.20.3 source:

```text
SGlobalObjectSystem.RegisterSystemClass(SRainBarrelSystem)
  server/RainBarrel/SRainBarrelSystem.lua:66

system:getLuaObjectCount() / system:getLuaObjectByIndex(i)
  server/Map/SGlobalObjectSystem.lua:40,44

luaObject fields, set in initNew and stateFromIsoObject:
  exterior, taintedWater, waterAmount, waterMax
  server/RainBarrel/SRainBarrelGlobalObject.lua
```

`waterAmount` and `waterMax` make a stocked test possible, which matters: the L1
trough exploit was exactly a structure that counted the moment it was built and
then sat empty. Water tiers ask for collected water, not for a barrel.

`taintedWater` is available and is deliberately not used as a gate in this design.
Rain water is tainted by default in the base game, so requiring untainted water
would silently require a filtration step the design never states.

The tiers, with starting thresholds. These are opening values to be tuned in play,
in the same spirit as the existing tier constants, not balanced numbers:

| Tier | Name         | Tasks                                                 |
| ---- | ------------ | ----------------------------------------------------- |
| W1   | First Barrel | one rain barrel stands inside the claim bounds        |
| W2   | The Cistern  | barrels on the claim hold at least 400 units of water |

### Track C: crops

A new track asking the crew to feed itself from the block.

Evidence comes from the farming global object system, registered the same way.
Crop positions and state are readable map-wide.

Verified against the installed Build 42.20.3 source:

```text
SGlobalObjectSystem.RegisterSystemClass(SFarmingSystem)
  server/Farming/SFarmingSystem.lua:580

SPlantGlobalObject:isAlive()      server/Farming/SPlantGlobalObject.lua:123
SPlantGlobalObject:canHarvest()   server/Farming/SPlantGlobalObject.lua:201

luaObject.state values seen in source:
  "seeded", "harvested", "dead", "rotten", "destroyed"
  server/Farming/SPlantGlobalObject.lua:649,662,686,700,708,719

luaObject.exterior, .health, .waterLvl, .typeOfSeed
  server/Farming/SFarmingSystem.lua:156,186,194,207
```

The plough state is explicitly excluded from counting as a crop:
`SFarmingSystem.lua:149` skips objects whose state is `"plow"`, and this design
follows that. A ploughed square is not a planted one.

The tiers, with starting thresholds, to be tuned in play:

| Tier | Name               | Tasks                                                    |
| ---- | ------------------ | -------------------------------------------------------- |
| F1   | First Furrow       | one living crop stands inside the claim bounds           |
| F2   | The Kitchen Garden | eight living crops on the claim, one of them harvestable |

### Track D: power

A new track asking the crew to light the block.

This is the one track that source reading cannot settle. Generators are not a Lua
global object system. They live in the Java-side registry, which the installed
Lua tree touches only from client debug tooling:

```text
SGlobalObjects.getSystemCount() / getSystemByIndex(i)
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectStateUI.lua:252,253

system:getObjectCount() / getObjectByIndex(i) / getObjectAt(x,y,z)
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectStateUI.lua:266,267,283

system:getModData():getIsoObjectAt(x, y, z)
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectState_PropertiesPanel.lua:161,175

isoObject:isActivated() / getCondition() / getFuel()
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectState_PropertiesPanel.lua:177,178,179

instanceof(obj, "IsoGenerator")
  client/DebugUIs/DebugContextMenu.lua:415
```

Two facts are unproven and must come from the probe, not from reasoning:

1. Whether `SGlobalObjects` is reachable from a `server/` file at all. Every call
   site found is client-side.
2. Whether a generator's running state is readable off loaded ground.
   `getIsoObjectAt` returns an `IsoObject`, which suggests it is not, in which
   case position is map-wide but `isActivated()` is a loaded-ground read.

If fact 1 comes back false, the power track falls back to square scanning near the
crew, the same limitation L3 hutches already carry, and its verdict is `unknown`
whenever nobody is on the block. If fact 1 comes back true and fact 2 false, the
track splits: "a generator stands on the block" is map-wide, "it is running and
fuelled" is a presence check.

The track is not designed further until the probe reports.

### Track E: perimeter

A new track asking the crew to seal the block's edge.

`GOALS.md` says no block-boundary sweep exists, and that remains true: there is no
API that hands back a claim's outline. What does exist is a per-square wall test,
verified in server-side code rather than debug tooling:

```text
square:getProperties():has(IsoFlagType.WallN)
square:getProperties():has(IsoFlagType.WallW)
square:getProperties():has(IsoFlagType.collideN)
square:getProperties():has(IsoFlagType.collideW)
square:getProperties():has(IsoFlagType.DoorWallN)
square:getProperties():has(IsoFlagType.HoppableN)
  server/BuildingObjects/ISBuildIsoEntity.lua:195,198
```

So the perimeter is checkable one square at a time, on loaded ground only. The
design turns that limit into the mechanic rather than hiding it: the perimeter
tier is a survey the crew walks. Each boundary square is sampled when a crew
member is near enough for it to be loaded, and the result is banked with the
world-age hour it was observed.

An unsampled boundary square is `unknown`, never `fail`. The tier reports how much
of the outline has been surveyed, so a partial walk reads as partial rather than
as failure. This mirrors the existing restoration rule that a crew member must be
present to witness a building.

The tiers, with starting thresholds, to be tuned in play:

| Tier | Name             | Tasks                                                  |
| ---- | ---------------- | ------------------------------------------------------ |
| D1   | The Survey       | every boundary square sampled at least once            |
| D2   | The Sealed Block | every sampled boundary square carries a wall or a gate |

D1 exists because the survey itself is work, and because a tier the crew cannot
see progress on is the fault this whole redesign started from.

Banked samples expire on the same principle as `RECHECK_HOURS`: a boundary
surveyed long ago is re-asked, so a torn-down wall eventually shows.

## What is deliberately not in this design

- **No dependency on any third-party quest mod.** Both engines inspected key their
  progress to one player and have no shared-progress concept, so neither can serve
  a two-player crew state. One additionally requires a Java-side mod for its
  multiplayer path.
- **No copied code.** Both inspected mods are all-rights-reserved by their own file
  headers. Patterns only.
- **No condition scripting language.** One inspected engine encodes commands as
  semicolon-and-colon separated strings. Lua tables and registered functions do
  the same job without a parser, and Kahlua gives no reason to prefer strings.
- **No version-mismatch handshake.** It was considered and dropped from this scope
  to keep the change reviewable. It stays worth doing: both players must run the
  same `modversion` and nothing detects when they do not. Recorded here so it is
  not lost.
- **No new progress counters.** Of the eleven counters `GOALS.md` documents, nine
  were never built. This design does not add them, because tier tasks now carry the same
  information in a form the UI already reads. `GOALS.md` gets corrected instead.

## Order of work

1. **Probe build.** Instrument the four unproven reads and ship it. One game
   session, one log. Nothing else in this design is finalised before that log
   exists.
2. **The three layers**, with the existing nine tiers ported unchanged. Behaviour
   identical, verified by comparing tier outcomes before and after on the same
   save.
3. **Track A**, the tier 5 animal gap. Smallest new behaviour, no new evidence
   kind.
4. **Tracks B and C**, water and crops. Same proven evidence path.
5. **Track E**, the perimeter survey.
6. **Track D**, power, shaped by what the probe reported.
7. **Correct `GOALS.md`** so the documented design and the built design agree.

Each of steps 2 to 6 bumps `modversion` in both `mod.info` copies in the same
commit, per the repo's versioning rule.

## What "done" means for each step

- [ ] `npm run check` passes — proofreading only, proves nothing about behaviour.
- [ ] `lua-language-server --check=.` from the repo root reports no new warnings.
- [ ] A Project Zomboid session loads the build without a Lua error in the log.
- [ ] The tier that step targets is observed changing state in game, with the log
      line or screenshot that shows it.

The fourth item is the only one that proves the feature. The first three are
gates, not evidence.
