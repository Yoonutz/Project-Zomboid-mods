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
