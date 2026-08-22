# TwoManCrew Evidence Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **STATUS: written, NOT TESTED. 2026-08-23, mod version `0.12.0`.**
>
> **This code has never been executed.** No Project Zomboid session has loaded
> it. Nothing below is known to work.
>
> What actually ran: nothing yet. When the tasks below are done, the gates that
> will have run are `npm run check`, `lua-language-server --check=.` and
> `npx prettier --check`. None of that executes a line of the mod. It is
> proofreading, not testing — it cannot catch a wrong method name, a nil at
> runtime, a wrong event, or a UI that draws garbage.
>
> Every in-game check is OPEN.

**Goal:** Ship a build that prints what four unproven engine reads actually
return inside a real save, so the water, crops, perimeter and power tracks are
designed against a log rather than against source reading.

**Architecture:** One new server-only Lua file runs a bounded probe pass on the
`EveryTenMinutes` event, six passes then stop. Every read is wrapped in `pcall`,
because half of what the probe measures is whether the global exists at all. One
Node script change turns the resulting log lines into a verdict table.

**Tech Stack:** Lua 5.1 (Kahlua) inside Project Zomboid Build 42.20.3, Node build
scripts (`check-lua.mjs`, `diagnose.mjs`, `deploy.mjs`), `lua-language-server`
from the VS Code Lua extension.

---

## Why this plan is only the probe

The design document
(`docs/superpowers/specs/2026-08-23-declarative-tier-model-design.md`) covers
seven steps. Only the first is planned here, on purpose.

The spec states that nothing else is finalised before the probe log exists, and
the repo's own rule is instrumentation first when a fact only exists in game.
Three TwoManCrew builds were once shipped on code-reading alone and all three
were wrong. Writing implementation tasks for the power track now would repeat
exactly that.

The three-layer port and the four tracks get their own plans once the log is
read.

## Context for the implementer

You are working in a Project Zomboid Build 42 mod. Read these before starting.

**The game cannot run in this environment.** No check available here loads
Project Zomboid. `npm run check` parses Lua and nothing more. Never report any
part of this as tested; the status is `Unverified` until a game session has
loaded it.

**The language is Lua 5.1 (Kahlua).** No `goto`, no `table.unpack` (use
`unpack`), no integer division, no bitwise operators. `pcall` IS available and
confirmed working in game, which this plan depends on heavily.

**`server/` files load on multiplayer clients too.** Every file in `server/`
must open with `if isClient() then return end` after its `require` lines. This
is not optional and its absence is invisible in singleplayer.

**Work happens directly on `master`.** No branches, no worktrees, no pull
requests. Commit as work completes and push to `origin master`.

**Both `mod.info` copies must stay identical:**

```text
two-man-crew/Contents/mods/TwoManCrew/mod.info
two-man-crew/Contents/mods/TwoManCrew/42/mod.info
```

**The install may be deliberately pinned behind the repo** to match the other
player in a co-op save. Never deploy without asking, and never "sync" the
install to the repo unasked.

## File Structure

- **Create** `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua`
  Server-only. Owns every probe read and every print. Self-limiting to six
  passes. This is the only new Lua file.
- **Modify** `two-man-crew/diagnose.mjs`
  Adds a probe section that reads the `TwoManCrew[probe]` lines out of the
  newest log and prints them as a verdict table.
- **Modify** `two-man-crew/Contents/mods/TwoManCrew/mod.info` and
  `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`
  `modversion` bump, both files, same commit.

No existing Lua file is touched. That is deliberate: the probe must not be able
to break a working feature, so it shares no code path with one.

---

### Task 1: Invoke the test-driven-development skill

This repo forbids writing a probe off your own bat. The rule is recorded in
`.claude/memory/no-verification-scaffolding.md` and exists because two
improvised probes here were thrown away, one of them as "useless".

- [ ] **Step 1: Invoke the skill**

Invoke `superpowers:test-driven-development` before creating any file in this
plan.

- [ ] **Step 2: Record why red-green degenerates here**

The skill's red-green cycle assumes a runner. There is none: the fengari harness
was deleted on 2026-08-22 and engine globals exist only inside the running game.

The honest substitute, and the one this plan uses:

- The probe's "red" is the log line printing `ERROR: ...` or `false`.
- The probe's "green" is the log line printing a real count or coordinate.
- Both are read from `~/Zomboid/Logs/`, not from a local command.

State this in the turn where the skill is invoked. Do not invent a mock harness.

---

### Task 2: Create the probe file skeleton

**Files:**

- Create: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua`

- [ ] **Step 1: Write the file**

```lua
-- TwoManCrew_Probe.lua (server)
--
-- A bounded, read-only probe. It prints what a set of engine reads actually
-- return inside a running save, because this repo cannot run Project Zomboid
-- and every conclusion drawn from source alone is a hypothesis. Three builds
-- were once shipped on such hypotheses and all three were wrong.
--
-- It changes nothing. It awards nothing, writes no ModData, sends no command,
-- and touches no other TwoManCrew module. A probe that can break a working
-- feature is worse than no probe.
--
-- WHY EVERY READ IS pcall'd: half of what this measures is whether a global
-- exists at all. An unprotected call to a missing one aborts the whole pass,
-- which would teach us nothing about the reads that come after it. pcall is
-- confirmed working in Kahlua - see .claude/memory/pz-runs-lua-5-1-kahlua.md.
--
-- It stops itself after MAX_PASSES so a forgotten probe cannot spam a log
-- forever.

require "TwoManCrew/TwoManCrew_Config"

-- server/ files load on multiplayer CLIENTS too. Without this guard the probe
-- would run on both machines and double every line in the log.
if isClient() then return end

local MAX_PASSES = 6
local passes = 0

local function say(fact, value)
	print("TwoManCrew[probe] " .. tostring(fact) .. " = " .. tostring(value))
end

local function try(fact, fn)
	local ok, result = pcall(fn)
	if ok then
		say(fact, result)
	else
		say(fact, "ERROR: " .. tostring(result))
	end
end

local function runPass()
	passes = passes + 1
	say("pass", passes .. "/" .. MAX_PASSES)
end

local function onTenMinutes()
	if passes >= MAX_PASSES then return end
	runPass()
end

Events.EveryTenMinutes.Add(onTenMinutes)

print("TwoManCrew[probe] TwoManCrew_Probe.lua LOADED")
```

- [ ] **Step 2: Run the parse check**

Run from `two-man-crew/`:

```bash
npm run check
```

Expected: it lists every Lua file and reports no parse errors. The new file
appears in the list.

- [ ] **Step 3: Run the scope-aware check**

Run from the repo root, not from a mod subfolder, or `.luarc.json` is not picked
up:

```bash
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: no NEW diagnostics. The pre-existing atan2 and duplicate-set-field
warnings are expected and must never be "fixed".

- [ ] **Step 4: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua"
git commit -m "feat: add a bounded, read-only probe that prints what the engine returns"
```

---

### Task 3: Probe the two Lua global object systems

These are the water and crops evidence paths. Both are registered
`SGlobalObjectSystem` subclasses, so both expose `.instance` and the
`getLuaObjectCount` / `getLuaObjectByIndex` pair the existing trough check
already uses.

Verified in the installed Build 42.20.3 source:

```text
SGlobalObjectSystem.RegisterSystemClass(SRainBarrelSystem)
  server/RainBarrel/SRainBarrelSystem.lua:66
SGlobalObjectSystem.RegisterSystemClass(SFarmingSystem)
  server/Farming/SFarmingSystem.lua:580
luaClass.instance = luaClass:new()
  server/Map/SGlobalObjectSystem.lua:241,246
getLuaObjectCount() / getLuaObjectByIndex(index)
  server/Map/SGlobalObjectSystem.lua:40,44
```

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua`

- [ ] **Step 1: Add the system probe above `runPass`**

Insert this immediately after the `try` function:

```lua
-- Probes one registered Lua global object system by name. Reports three
-- separate facts rather than one, because they can fail independently: the
-- global may be missing, the instance may be nil before the system starts,
-- and the object list may simply be empty.
local function probeLuaSystem(globalName, fieldNames)
	try(globalName .. ".global", function()
		return _G[globalName] ~= nil
	end)

	try(globalName .. ".instance", function()
		return _G[globalName] ~= nil and _G[globalName].instance ~= nil
	end)

	try(globalName .. ".count", function()
		return _G[globalName].instance:getLuaObjectCount()
	end)

	try(globalName .. ".first", function()
		local system = _G[globalName].instance
		if system:getLuaObjectCount() == 0 then return "none present" end

		local o = system:getLuaObjectByIndex(0)
		local parts = { "x=" .. tostring(o.x) .. " y=" .. tostring(o.y) .. " z=" .. tostring(o.z) }
		for i = 1, #fieldNames do
			local key = fieldNames[i]
			parts[#parts + 1] = key .. "=" .. tostring(o[key])
		end
		return table.concat(parts, " ")
	end)
end
```

- [ ] **Step 2: Call it from `runPass`**

Replace the body of `runPass` with:

```lua
local function runPass()
	passes = passes + 1
	say("pass", passes .. "/" .. MAX_PASSES)

	-- Water. Fields verified in server/RainBarrel/SRainBarrelGlobalObject.lua,
	-- set in initNew and stateFromIsoObject.
	probeLuaSystem("SRainBarrelSystem", { "waterAmount", "waterMax", "exterior", "taintedWater" })

	-- Crops. Fields verified in server/Farming/SFarmingSystem.lua:156,186,194,207.
	-- The "plow" state is not a crop: SFarmingSystem.lua:149 skips it, and so
	-- must anything built on this.
	probeLuaSystem("SFarmingSystem", { "state", "typeOfSeed", "health", "waterLvl", "exterior" })
end
```

- [ ] **Step 3: Run the parse check**

Run from `two-man-crew/`:

```bash
npm run check
```

Expected: no parse errors.

- [ ] **Step 4: Run the scope-aware check**

Run from the repo root:

```bash
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: no new diagnostics. If `SRainBarrelSystem` or `SFarmingSystem` is
reported as an undefined global, add it to `types/pz.lua` as a `---@meta` stub
with a signature taken from the installed game source. Do not silence the
warning any other way.

- [ ] **Step 5: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua" types/pz.lua
git commit -m "feat: probe the rain barrel and farming object systems"
```

---

### Task 4: Probe the Java-side global object registry

This is the power track's evidence path, and the one the design document refuses
to finalise without a log. Every call site found in the installed tree is
client-side debug tooling, so whether a `server/` file can reach it is unknown.

Verified call sites, all client-side:

```text
SGlobalObjects.getSystemCount() / getSystemByIndex(i)
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectStateUI.lua:252,253
system:getObjectCount() / getObjectByIndex(i)
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectStateUI.lua:266,267
system:getModData():getIsoObjectAt(x, y, z)
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectState_PropertiesPanel.lua:161,175
isoObject:isActivated() / getCondition() / getFuel()
  client/DebugUIs/DebugGlobalObjectState/DebugGlobalObjectState_PropertiesPanel.lua:177,178,179
instanceof(obj, "IsoGenerator")
  client/DebugUIs/DebugContextMenu.lua:415
```

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua`

- [ ] **Step 1: Add the registry probe above `runPass`**

```lua
-- Probes the Java-side global object registry, which is where generators live.
-- SGlobalObjects is NOT one of the Lua SGlobalObjectSystem registrations, and
-- every call site in the installed tree is client-side debug tooling, so the
-- first fact below is the one that decides whether a power track is possible
-- at all.
local function probeRegistry()
	try("SGlobalObjects.global", function()
		return SGlobalObjects ~= nil
	end)

	try("SGlobalObjects.systemCount", function()
		return SGlobalObjects.getSystemCount()
	end)

	try("SGlobalObjects.systemNames", function()
		local names = {}
		for i = 1, SGlobalObjects.getSystemCount() do
			local system = SGlobalObjects.getSystemByIndex(i - 1)
			names[#names + 1] = tostring(system:getName()) .. ":" .. tostring(system:getObjectCount())
		end
		if #names == 0 then return "none" end
		return table.concat(names, ", ")
	end)

	-- Whether a generator's RUNNING state is readable off loaded ground is the
	-- second unknown. getIsoObjectAt returns an IsoObject, which suggests it is
	-- not, in which case position is map-wide but isActivated() is a presence
	-- check. This reports position and state separately so the log can tell
	-- those two apart instead of collapsing them.
	try("SGlobalObjects.generator", function()
		for i = 1, SGlobalObjects.getSystemCount() do
			local system = SGlobalObjects.getSystemByIndex(i - 1)
			for j = 1, system:getObjectCount() do
				local globalObject = system:getObjectByIndex(j - 1)
				local x, y, z = globalObject:getX(), globalObject:getY(), globalObject:getZ()
				local isoObject = system:getModData():getIsoObjectAt(x, y, z)
				if isoObject and instanceof(isoObject, "IsoGenerator") then
					return "pos x=" .. tostring(x) .. " y=" .. tostring(y) .. " z=" .. tostring(z)
						.. " activated=" .. tostring(isoObject:isActivated())
						.. " fuel=" .. tostring(isoObject:getFuel())
				end
			end
		end
		return "no generator found in any system"
	end)
end
```

- [ ] **Step 2: Call it from `runPass`**

Add this line at the end of `runPass`, after the two `probeLuaSystem` calls:

```lua
	probeRegistry()
```

- [ ] **Step 3: Run the parse check**

Run from `two-man-crew/`:

```bash
npm run check
```

Expected: no parse errors.

- [ ] **Step 4: Run the scope-aware check**

Run from the repo root:

```bash
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: no new diagnostics. `SGlobalObjects` will likely be reported as an
undefined global. Add it to `types/pz.lua`, since the probe's whole purpose is
to find out whether it exists at runtime — the stub records the shape, not a
claim that it is reachable.

- [ ] **Step 5: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua" types/pz.lua
git commit -m "feat: probe whether a server file can reach the global object registry"
```

---

### Task 5: Probe the per-square wall flags

This is the perimeter track's evidence path. Unlike the two above, the flags are
verified in server-side code rather than debug tooling, so what is unknown here
is not whether the API exists but how much of a claim's outline is loaded at any
moment.

Verified in the installed Build 42.20.3 source:

```text
square:getProperties():has(IsoFlagType.WallN)
square:getProperties():has(IsoFlagType.WallW)
square:getProperties():has(IsoFlagType.collideN)
square:getProperties():has(IsoFlagType.collideW)
square:getProperties():has(IsoFlagType.DoorWallN)
square:getProperties():has(IsoFlagType.HoppableN)
  server/BuildingObjects/ISBuildIsoEntity.lua:195,198
getCell():getGridSquare(x, y, z)
  server/Animal/ISPickDungCursor.lua:104
```

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua`

- [ ] **Step 1: Add the perimeter probe above `runPass`**

```lua
-- Walks a short line of squares outward from a crew member and reports how far
-- the loaded window actually extends, plus what the wall flags say on each
-- square that IS loaded.
--
-- The distinction this exists to measure: a nil square is UNREADABLE, not
-- wall-less. Any perimeter tier built on this must report unknown for a nil
-- square and must never count it as a failure.
local WALL_FLAGS = { "WallN", "WallW", "collideN", "collideW", "DoorWallN", "HoppableN" }
local PERIMETER_SAMPLES = 40

local function describeSquare(square)
	if not square then return "nil (unloaded)" end

	local props = square:getProperties()
	if not props then return "loaded, no properties" end

	local hits = {}
	for i = 1, #WALL_FLAGS do
		local flag = WALL_FLAGS[i]
		if props:has(IsoFlagType[flag]) then
			hits[#hits + 1] = flag
		end
	end

	if #hits == 0 then return "loaded, no wall flags" end
	return "loaded, " .. table.concat(hits, "+")
end

local function probePerimeter()
	local players = TwoManCrew.getAllPlayers()
	local player = players and players[1]

	try("perimeter.anchor", function()
		if not player then return "no player online" end
		return "x=" .. tostring(math.floor(player:getX()))
			.. " y=" .. tostring(math.floor(player:getY()))
			.. " z=" .. tostring(player:getZ())
	end)

	if not player then return end

	local px = math.floor(player:getX())
	local py = math.floor(player:getY())
	local pz = player:getZ()

	-- Report the furthest offset that still returns a square, and the flags
	-- found along the way. One line per sample would flood the log, so this
	-- summarises: how many were loaded, and the first three descriptions.
	try("perimeter.reach", function()
		local loaded = 0
		local samples = {}
		for step = 1, PERIMETER_SAMPLES do
			local square = getCell():getGridSquare(px + step, py, pz)
			if square then loaded = loaded + 1 end
			if step <= 3 then
				samples[#samples + 1] = "+" .. step .. ":" .. describeSquare(square)
			end
		end
		return loaded .. "/" .. PERIMETER_SAMPLES .. " loaded eastward; " .. table.concat(samples, " | ")
	end)
end
```

- [ ] **Step 2: Call it from `runPass`**

Add this line at the end of `runPass`, after `probeRegistry()`:

```lua
	probePerimeter()
```

- [ ] **Step 3: Run the parse check**

Run from `two-man-crew/`:

```bash
npm run check
```

Expected: no parse errors.

- [ ] **Step 4: Run the scope-aware check**

Run from the repo root:

```bash
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: no new diagnostics.

- [ ] **Step 5: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Probe.lua" types/pz.lua
git commit -m "feat: probe how far the loaded window reaches and what wall flags it finds"
```

---

### Task 6: Teach `diagnose.mjs` to read the probe

Without this, reading the probe means grepping a log by hand, which is exactly
the friction that made the last three diagnoses guesses.

**Files:**

- Modify: `two-man-crew/diagnose.mjs`

- [ ] **Step 1: Add the probe section**

Append this to the end of `diagnose.mjs`, after the existing chain output:

```javascript
// Probe output, added 2026-08-23. TwoManCrew_Probe.lua prints one
// "TwoManCrew[probe] fact = value" line per read. This groups them by fact and
// shows the LAST value seen, because later passes happen with the crew in
// different places and the last one is the most recent state of the world.
const probeLines = lines.filter((l) => l.includes("TwoManCrew[probe]"));

console.log("");
if (probeLines.length === 0) {
  console.log("No probe output in this log.");
  console.log("");
  console.log("Either this log predates the probe build, or the probe never");
  console.log(
    "ran. It fires on the game's ten-minute tick, so load a save and",
  );
  console.log("let roughly an in-game hour pass, then run this again.");
} else {
  const facts = new Map();
  for (const line of probeLines) {
    const match = line.match(/TwoManCrew\[probe\] (.+?) = (.*)$/);
    if (!match) continue;
    const [, fact, value] = match;
    if (!facts.has(fact)) facts.set(fact, []);
    facts.get(fact).push(value.trim());
  }

  console.log(`Probe facts (${probeLines.length} lines):`);
  for (const [fact, values] of facts) {
    const last = values[values.length - 1];
    const varied =
      new Set(values).size > 1
        ? `  (varied across ${values.length} passes)`
        : "";
    console.log(`  ${fact} = ${last}${varied}`);
  }
}
```

- [ ] **Step 2: Run it against the current log**

Run from `two-man-crew/`:

```bash
npm run diagnose
```

Expected: the existing chain output, then `No probe output in this log.` The
probe has not shipped yet, so that is the correct result and proves the new
section runs without throwing.

- [ ] **Step 3: Commit**

```bash
git add two-man-crew/diagnose.mjs
git commit -m "feat: report probe facts from the newest log instead of grepping by hand"
```

---

### Task 7: Bump the version, then ask before deploying

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Bump `modversion` in BOTH files**

Change `modversion=0.12.0` to `modversion=0.13.0` in each. Minor, not patch:
this adds new behaviour rather than fixing something.

The two files have drifted once already. Check both.

- [ ] **Step 2: Confirm they match**

```bash
diff "two-man-crew/Contents/mods/TwoManCrew/mod.info" "two-man-crew/Contents/mods/TwoManCrew/42/mod.info"
```

Expected: no output.

- [ ] **Step 3: Commit and push**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "chore: bump modversion for the probe build"
git push origin master
```

- [ ] **Step 4: Check the install, and STOP**

```bash
cd two-man-crew && node deploy.mjs --check
```

This writes nothing. Report what it says.

Do NOT run `node deploy.mjs`. The install is sometimes pinned behind the repo on
purpose, to match the other player in a co-op save, and deploying replaces the
mod folder underneath a live session. Ask first, every time.

- [ ] **Step 5: Ask for one game run**

Once the user has approved a deploy and it has happened, ask for one session:
load the save, walk the claimed block for roughly an in-game hour so several
passes fire in different places, then quit.

Then read the result:

```bash
cd two-man-crew && npm run diagnose
```

Check the log's timestamp against the install's before drawing any conclusion. A
log written before the deploy says nothing about the new build, and an old log
has twice nearly produced a false conclusion here.

---

## What "done" means for this plan

- [ ] `npm run check` passes — proofreading only, proves nothing about behaviour.
- [ ] `lua-language-server --check=.` reports no new warnings.
- [ ] Both `mod.info` files carry the same bumped `modversion`.
- [ ] `npm run diagnose` runs without throwing against the current log.
- [ ] A Project Zomboid session has loaded the build and the log contains
      `TwoManCrew_Probe.lua LOADED`.
- [ ] `npm run diagnose` prints a value for every probed fact, and that log is
      newer than the install.

The last two items are the only ones that prove anything. The first four are
gates.

## What comes next

The probe log answers four questions. Each one unblocks a piece of the design:

- Are the rain barrel and farming systems reachable and populated from a server
  file? Unblocks the water and crops tracks.
- Is `SGlobalObjects` reachable from a server file? Decides whether the power
  track is map-wide or a presence check, or whether it exists at all.
- How far does the loaded window reach around a player? Sizes the perimeter
  survey and its sampling interval.
- Do any of these reads throw in a real save? Rewrites whichever part of the
  design assumed they did not.

Once the log is read, two plans follow: the three-layer port with the existing
nine tiers unchanged, and then the new tracks.
