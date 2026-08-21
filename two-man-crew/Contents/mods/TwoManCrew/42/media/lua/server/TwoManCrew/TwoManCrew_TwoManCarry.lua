-- TwoManCrew_TwoManCarry.lua (server)
-- Handles the client's "twoManCarry" hint. Re-validates server-side that the
-- requesting player is actually heavily loaded (HEAVY_LOAD moodle) and that
-- a partner is within TwoManCrew.TwoManCarry.INTERACT_RANGE before granting
-- a small Strength XP bonus for the shared effort. The client never awards
-- XP; this is the sole award path.
--
-- MoodleType.HEAVY_LOAD / getMoodleLevel(...) > 2 verified:
-- client/ISUI/ISFitnessUI.lua:219. Perks.Strength verified:
-- shared/Fishing/FishingRod.lua:15. AddXP signature verified:
-- client/ISUI/PlayerStats/ISPlayerStatsUI.lua:525.
--
-- No verified vanilla API mutates run speed, carry capacity, or moodle
-- level (checked in the client half's header comment), so this feature
-- rewards the shared-carry moment with XP rather than easing movement or
-- capacity - the only mechanic buildable entirely from verified APIs.

require "TwoManCrew/TwoManCrew_Config"

local COOLDOWN_KEY = "TwoManCarry"
local HEAVY_LOAD_THRESHOLD = 2 -- matches the vanilla ISFitnessUI.lua:219 gate

-- No dedicated XP/cooldown constants exist for TwoManCarry in Config (it
-- only defines MAX_CARRY_WEIGHT/INTERACT_RANGE), so this reuses the
-- MastersMark cooldown and a fraction of the FellingBonus XP baseline,
-- matching the reuse pattern SharedApprenticeship already applies rather
-- than inventing new unconfigured numbers.
local COOLDOWN_SECONDS = TwoManCrew.TwoManCarry.COOLDOWN_SECONDS
local function bonusAmount()
	return TwoManCrew.TwoManCarry.XP_AMOUNT
end

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "twoManCarry" then return end
	if not player then return end

	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, COOLDOWN_SECONDS) then
		return
	end

	local moodles = player:getMoodles()
	if not moodles then return end
	if moodles:getMoodleLevel(MoodleType.HEAVY_LOAD) <= HEAVY_LOAD_THRESHOLD then return end

	-- Re-validate proximity server-side; never trust the client's claim.
	local partner = TwoManCrew.getPartner(player)
	if not partner then return end
	if player:DistTo(partner:getX(), partner:getY()) > TwoManCrew.TwoManCarry.INTERACT_RANGE then
		return
	end

	player:getXp():AddXP(Perks.Strength, bonusAmount(), false, false, false, false)

	TwoManCrew.startCooldown(player, COOLDOWN_KEY, COOLDOWN_SECONDS)

	-- Shared crew scoreboard. Guarded: CrewState is a separate server file and
	-- load order across mod files is not guaranteed.
	if TwoManCrew.Server and TwoManCrew.Server.addTally then
		TwoManCrew.Server.addTally("heavyHauls", 1, player)
		TwoManCrew.Server.addJournal("hauled heavy beside the crew", player)
	end

	HaloTextHelper.addText(player, "Shared the load!")
end
Events.OnClientCommand.Add(OnClientCommand)
