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

		-- ONE-based: getLuaObjectByIndex does getObjectByIndex(index-1)
		-- internally (server/Map/SGlobalObjectSystem.lua:44), so index 1 is
		-- the first object. Passing 0 asks Java for -1 and throws.
		local o = system:getLuaObjectByIndex(1)
		local parts = { "x=" .. tostring(o.x) .. " y=" .. tostring(o.y) .. " z=" .. tostring(o.z) }
		for i = 1, #fieldNames do
			local key = fieldNames[i]
			parts[#parts + 1] = key .. "=" .. tostring(o[key])
		end
		return table.concat(parts, " ")
	end)
end

-- Probes the Java-side global object registry, which is where generators live.
-- SGlobalObjects is NOT one of the Lua SGlobalObjectSystem registrations, and
-- every call site in the installed tree is client-side debug tooling, so the
-- first fact below is the one that decides whether a power track is possible
-- at all.
--
-- These accessors are the RAW Java ones and are ZERO-based, unlike
-- SGlobalObjectSystem:getLuaObjectByIndex, which subtracts one for you.
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
	--
	-- Each object is inspected inside its OWN pcall. One bad object must not
	-- abort the scan and turn a real generator into "none found" - a probe that
	-- reports a false negative is worse than one that reports an error.
	try("SGlobalObjects.generator", function()
		local skipped = 0
		for i = 1, SGlobalObjects.getSystemCount() do
			local system = SGlobalObjects.getSystemByIndex(i - 1)
			for j = 1, system:getObjectCount() do
				local ok, found = pcall(function()
					local globalObject = system:getObjectByIndex(j - 1)
					local x, y, z = globalObject:getX(), globalObject:getY(), globalObject:getZ()
					local isoObject = system:getModData():getIsoObjectAt(x, y, z)
					if isoObject and instanceof(isoObject, "IsoGenerator") then
						return "pos x=" .. tostring(x) .. " y=" .. tostring(y) .. " z=" .. tostring(z)
							.. " activated=" .. tostring(isoObject:isActivated())
							.. " fuel=" .. tostring(isoObject:getFuel())
					end
					return nil
				end)
				if ok and found then
					return found .. " (skipped " .. skipped .. " unreadable)"
				end
				if not ok then skipped = skipped + 1 end
			end
		end
		return "no generator found in any system (skipped " .. skipped .. " unreadable)"
	end)
end

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

	probeRegistry()
end

local function onTenMinutes()
	if passes >= MAX_PASSES then return end
	runPass()
end

Events.EveryTenMinutes.Add(onTenMinutes)

print("TwoManCrew[probe] TwoManCrew_Probe.lua LOADED")
