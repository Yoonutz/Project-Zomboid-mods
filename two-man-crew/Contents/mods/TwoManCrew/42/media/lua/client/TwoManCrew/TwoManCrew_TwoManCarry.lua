-- TwoManCrew_TwoManCarry.lua (client)
-- Detects that the local player is heavily loaded (vanilla HEAVY_LOAD
-- moodle) while a crew partner is close enough to be sharing the physical
-- effort, and asks the server to consider a bonus. No client-side easing of
-- movement or capacity is applied here: no verified setter for run speed,
-- carry capacity, or moodle level exists anywhere in the installed B42.20.3
-- source (checked: getRunSpeedModifier is a getter only, used for debug
-- display at client/DebugUIs/ISRunningDebugUI.lua:121, with no paired
-- setter found; no getMoodles():set*/add* mutator call site exists either).
-- Rewarding the shared-effort moment with Strength XP is the mechanic that
-- stays entirely inside verified read/reward APIs.
--
-- MoodleType.HEAVY_LOAD and the getMoodleLevel(...) > 2 "heavily loaded"
-- threshold are verified at client/ISUI/ISFitnessUI.lua:219 (identical
-- pattern used there to disable the fitness action while overloaded).

require "TwoManCrew/TwoManCrew_Config"

-- OnPlayerUpdate fires every tick per player. Real work only runs once every
-- CHECK_INTERVAL_TICKS ticks; no table allocation on skipped ticks or while
-- alone/not heavily loaded.
local CHECK_INTERVAL_TICKS = 30
local tickCounter = 0

local HEAVY_LOAD_THRESHOLD = 2 -- matches the vanilla ISFitnessUI.lua:219 gate

local function OnPlayerUpdate(player)
	if not player then return end
	if isServer() then return end

	tickCounter = tickCounter + 1
	if tickCounter < CHECK_INTERVAL_TICKS then return end
	tickCounter = 0

	if TwoManCrew.isAlone(player) then return end -- alone: silent no-op per SPEC

	local moodles = player:getMoodles()
	if not moodles then return end
	if moodles:getMoodleLevel(MoodleType.HEAVY_LOAD) <= HEAVY_LOAD_THRESHOLD then return end

	local partner = TwoManCrew.getPartner(player)
	if not partner then return end

	-- Partner must also be within the tighter carry-interaction range, not
	-- just the wider crew radius, to count as "actively helping carry".
	if player:DistTo(partner:getX(), partner:getY()) > TwoManCrew.TwoManCarry.INTERACT_RANGE then
		return
	end

	sendClientCommand(player, TwoManCrew.MODULE, "twoManCarry", {})
end
Events.OnPlayerUpdate.Add(OnPlayerUpdate)
