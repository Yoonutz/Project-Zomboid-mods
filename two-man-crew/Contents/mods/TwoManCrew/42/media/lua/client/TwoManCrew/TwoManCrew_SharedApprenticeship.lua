-- TwoManCrew_SharedApprenticeship.lua (client)
-- Detects that the local player is the less-skilled half of a nearby crew
-- pair in one of the tracked trade perks and asks the server to consider a
-- trickle XP award. The server re-checks both perk levels and the cooldown
-- before granting anything - this client half never calls AddXP.
--
-- Perk constants verified in installed B42.20.3 source:
--   Perks.Woodwork    - shared/Moveables/ISMoveableDefinitions.lua:311
--   Perks.Strength     - shared/Fishing/FishingRod.lua:15
--   Perks.Axe          - server/XpSystem/XpUpdate.lua:88
--   Perks.Carving      - server/XpSystem/XPSystem_SkillBook.lua:28
--   Perks.Maintenance  - server/XpSystem/XPSystem_SkillBook.lua:191
-- player:getPerkLevel(Perks.X) verified: client/Farming/CFarmingSystem.lua:32.

require "TwoManCrew/TwoManCrew_Config"

-- Trade perks eligible for the trickle. Same list server-side; kept in both
-- files (not Config, which is constants/helpers only) since each half
-- iterates it independently.
local TRACKED_PERKS = {
	Perks.Woodwork,
	Perks.Axe,
	Perks.Carving,
	Perks.Strength,
	Perks.Maintenance,
}

-- OnPlayerUpdate fires every tick per player. Real work only runs once every
-- CHECK_INTERVAL_TICKS ticks; no table allocation happens on the skipped
-- ticks or when the player is alone.
local CHECK_INTERVAL_TICKS = 30
local tickCounter = 0

local function OnPlayerUpdate(player)
	if not player then return end
	if isServer() then return end

	tickCounter = tickCounter + 1
	if tickCounter < CHECK_INTERVAL_TICKS then return end
	tickCounter = 0

	-- No isAlone() guard here: it is getPartner(player) == nil internally, so
	-- calling both ran the whole player scan twice per check on an
	-- OnPlayerUpdate path. The nil check below is the same test, once.
	local partner = TwoManCrew.getPartner(player)
	if not partner then return end

	local minGap = TwoManCrew.SharedApprenticeship.MIN_SKILL_GAP

	-- Look for any tracked perk where the partner is clearly ahead of this
	-- player. First qualifying perk wins; the server independently re-derives
	-- whichever perk it wants to credit rather than trusting a chosen perk
	-- from the client.
	for i = 1, #TRACKED_PERKS do
		local perk = TRACKED_PERKS[i]
		local myLevel = player:getPerkLevel(perk)
		local partnerLevel = partner:getPerkLevel(perk)

		if partnerLevel - myLevel >= minGap then
			sendClientCommand(player, TwoManCrew.MODULE, "sharedApprenticeship", {})
			return
		end
	end
end
Events.OnPlayerUpdate.Add(OnPlayerUpdate)
