-- TwoManCrew_ShiftChange.lua (server)
-- Working through the night alone should cost more than working with a
-- partner. Every SHIFT_LENGTH_HOURS of night-time that passes while a
-- player has a crew partner nearby, both of them get a small "shift
-- change" XP nudge - relief from a teammate keeps a survivor sharper.
-- A lone player at night simply never accrues this bonus: no stat of
-- theirs is ever touched, so solo play degrades to a pure no-op rather
-- than a punishment. Entirely server-side - no client detection is needed
-- since night hours and crew proximity are both server-computable already.
--
-- Night hours: 0 <= hour < 5 (00:00-05:00), the deep graveyard stretch.
-- Picked narrow on purpose so normal evening play (dusk chores, base
-- prep before a 22:00-23:00 bedtime) never brushes the check - this
-- targets only survivors still working the literal night shift.
--
-- Low-frequency event: Events.EveryTenMinutes.Add(fn), the same
-- registration form used server-side at
-- server/Farming/SFarmingSystem.lua:586 and server/Traps/STrapSystem.lua:134.
-- Ten-minute resolution is more than enough precision for an hours-long
-- shift length and avoids the per-tick cost of OnPlayerUpdate entirely.
--
-- Mechanism chosen: withheld XP bonus via player:getXp():AddXP(...), the
-- exact call already verified and used by
-- server/TwoManCrew/TwoManCrew_FellingBonus.lua for its crew bonus. No
-- moodle or body-damage API needed, so nothing new has to be verified
-- against the SPEC's absent-API list, and nothing is ever subtracted from
-- a solo player - the bonus is only ever added for a paired one.

require "TwoManCrew/TwoManCrew_Config"

if isClient() then return end

local cfg = TwoManCrew.ShiftChange
local NIGHT_START_HOUR = 0
local NIGHT_END_HOUR = 5 -- exclusive

local SHIFT_KEY = "ShiftChange"

-- True during the deep-night working stretch. Verified:
-- getGameTime():getHour() at server/Traps/STrapGlobalObject.lua:535.
local function isNightHour()
	local hour = getGameTime():getHour()
	return hour >= NIGHT_START_HOUR and hour < NIGHT_END_HOUR
end

-- Cooldown-gated shift bonus, shared with TwoManCrew.onCooldown/
-- startCooldown so the "elapsed SHIFT_LENGTH_HOURS" requirement reuses the
-- same worldAgeHours-based storage every other feature already uses,
-- rather than a second timestamp scheme.
local SHIFT_LENGTH_SECONDS = TwoManCrew.ShiftChange.SHIFT_LENGTH_HOURS * 3600

local function awardShiftChangeBonus(player, partner)
	local amount = TwoManCrew.FellingBonus and TwoManCrew.ShiftChange.XP_AMOUNT or 3

	player:getXp():AddXP(Perks.Fitness, amount, false, false, false, false)
	partner:getXp():AddXP(Perks.Fitness, amount, false, false, false, false)

	TwoManCrew.startCooldown(player, SHIFT_KEY, SHIFT_LENGTH_SECONDS)
	TwoManCrew.startCooldown(partner, SHIFT_KEY, SHIFT_LENGTH_SECONDS)

	-- Shared crew scoreboard. Guarded: CrewState is a separate server file and
	-- load order across mod files is not guaranteed.
	if TwoManCrew.Server and TwoManCrew.Server.addTally then
		TwoManCrew.Server.addTally("nightShifts", 1, player)
		TwoManCrew.Server.addJournal("shared the night watch", player)
	end

	-- Plain literal, not a translation key: this mod ships no Translate/
	-- files, matching the precedent set in TwoManCrew_FellingBonus.lua.
	HaloTextHelper.addText(player, "Shift change - crew holds steady.")
	HaloTextHelper.addText(partner, "Shift change - crew holds steady.")
end

local function EveryTenMinutes()
	if not isNightHour() then return end

	-- Track who has already been credited this pass. Without this the loop
	-- would rely on awardShiftChangeBonus starting the cooldown on BOTH
	-- players to stop the partner being processed again on their own
	-- iteration - true today, but an invisible coupling that a later edit to
	-- the award function would silently break into a double award.
	local awarded = {}

	for _, player in ipairs(TwoManCrew.getAllPlayers()) do
		if not awarded[player] and not TwoManCrew.onCooldown(player, SHIFT_KEY, SHIFT_LENGTH_SECONDS) then
			local partner = TwoManCrew.getPartner(player)
			-- Alone: silent no-op per SPEC. No cooldown is started, so a
			-- solo player who later finds a partner is never penalized
			-- for the time spent alone.
			if partner then
				awarded[player] = true
				awarded[partner] = true
				awardShiftChangeBonus(player, partner)
			end
		end
	end
end

Events.EveryTenMinutes.Add(EveryTenMinutes)
