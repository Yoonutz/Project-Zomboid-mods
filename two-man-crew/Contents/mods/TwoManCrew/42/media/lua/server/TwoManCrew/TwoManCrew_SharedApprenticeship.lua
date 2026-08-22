-- TwoManCrew_SharedApprenticeship.lua (server)
-- Handles the client's "sharedApprenticeship" hint. Re-derives, server-side,
-- which tracked perk (if any) the requesting player is behind their nearest
-- partner on by at least the configured gap, and grants a small trickle of
-- XP in that perk. The client never awards XP; this is the sole award path.
--
-- Perk constants verified in installed B42.20.3 source (same sites as the
-- client half): Perks.Woodwork (shared/Moveables/ISMoveableDefinitions.lua:311),
-- Perks.Strength (shared/Fishing/FishingRod.lua:15), Perks.Axe
-- (server/XpSystem/XpUpdate.lua:88), Perks.Carving
-- (server/XpSystem/XPSystem_SkillBook.lua:28), Perks.Maintenance
-- (server/XpSystem/XPSystem_SkillBook.lua:191).
-- player:getXp():AddXP(perk, amount, false, false, false, false) verified:
-- client/ISUI/PlayerStats/ISPlayerStatsUI.lua:525.

require "TwoManCrew/TwoManCrew_Config"

-- PZ loads server/ on multiplayer clients too. Without this the file runs there,
-- where the guarded server files have bailed out. isClient() is false in
-- singleplayer, so this does not disable anything offline.
if isClient() then return end

local TRACKED_PERKS = {
	Perks.Woodwork,
	Perks.Axe,
	Perks.Carving,
	Perks.Strength,
	Perks.Maintenance,
}

local COOLDOWN_KEY = "SharedApprenticeship"

-- Trickle amount is a fraction of a single vanilla-sized XP grant, not a
-- fraction of the mentor's actual XP total (the server has no cheap way to
-- read "XP just earned by another player this tick"). XP_SHARE_FRACTION is
-- applied against FellingBonus.XP_AMOUNT as a stand-in baseline so the
-- trickle stays deliberately small relative to an existing tuned award.
local function trickleAmount()
	return TwoManCrew.SharedApprenticeship.BASE_XP * TwoManCrew.SharedApprenticeship.XP_SHARE_FRACTION
end

-- Returns the tracked perk with the largest mentor-over-apprentice gap that
-- still meets the minimum, or nil if none qualifies. Re-derived independently
-- of whatever the client observed.
local function findQualifyingPerk(player, partner, minGap)
	local bestPerk, bestGap = nil, minGap - 1

	for i = 1, #TRACKED_PERKS do
		local perk = TRACKED_PERKS[i]
		local gap = partner:getPerkLevel(perk) - player:getPerkLevel(perk)
		if gap >= minGap and gap > bestGap then
			bestPerk, bestGap = perk, gap
		end
	end

	return bestPerk
end

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "sharedApprenticeship" then return end
	if not player then return end

	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, TwoManCrew.SharedApprenticeship.COOLDOWN_SECONDS) then
		return
	end

	-- Re-validate proximity server-side; never trust the client's claim.
	local partner = TwoManCrew.getPartner(player)
	if not partner then return end

	local minGap = TwoManCrew.SharedApprenticeship.MIN_SKILL_GAP
	local perk = findQualifyingPerk(player, partner, minGap)
	if not perk then return end

	player:getXp():AddXP(perk, trickleAmount(), false, false, false, false)

	TwoManCrew.startCooldown(player, COOLDOWN_KEY, TwoManCrew.SharedApprenticeship.COOLDOWN_SECONDS)

	HaloTextHelper.addText(player, "Learning by watching...")
end
Events.OnClientCommand.Add(OnClientCommand)
