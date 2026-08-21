-- TwoManCrew_SiteRadius.lua (client)
-- Detects a locally completed build (ISBuildAction) or craft (ISCraftAction)
-- and, if a crew partner is within the site radius, asks the server for a
-- work-site bonus. The server is authoritative; client never awards XP.
--
-- Two hooks, matching the two vanilla completion paths verified in SPEC.md:
--  - ISBuildAction:perform() (client/BuildingObjects/TimedActions/
--    ISBuildAction.lua:201) runs the real construction. It is NOT
--    client-only: server/BuildingObjects/ISBuildingObject.lua:199
--    constructs its own ISBuildAction and drives it server-side too (the
--    isClient() branch at ISBuildAction.lua:215 exists precisely because
--    this same function body executes in both contexts), so this file's
--    wrap fires on dedicated servers as well as single-player/listen hosts.
--  - ISCraftAction:complete() (shared/TimedActions/ISCraftAction.lua:92) is
--    the craft-completion hook also used by TwoManCrew_MastersMark.lua
--    (client). Both wrap it independently, saving/calling their own prior
--    original, so the two never overwrite each other - same "wrap, call
--    through" convention as TwoManCrew_FellingBonus.lua.

require "TimedActions/ISCraftAction"
require "BuildingObjects/TimedActions/ISBuildAction"

local function requestSiteBonus(character, x, y, z)
	if not character then return end
	if not isClient() then return end
	if not instanceof(character, "IsoPlayer") then return end
	if not character:isLocalPlayer() then return end

	local partner = TwoManCrew.getPartner(character)
	if not partner then return end -- alone: silent no-op per SPEC

	if partner:DistTo(x, y) > TwoManCrew.SiteRadius.RADIUS_TILES then return end

	sendClientCommand(character, TwoManCrew.MODULE, "siteRadiusBonus", {})
end

-- Building.
local original_ISBuildAction_perform = ISBuildAction.perform

function ISBuildAction:perform()
	local character = self.character
	local x, y, z = self.x, self.y, self.z

	original_ISBuildAction_perform(self)

	requestSiteBonus(character, x, y, z)
end

-- Crafting.
local original_ISCraftAction_complete = ISCraftAction.complete

function ISCraftAction:complete()
	local character = self.character

	local result = original_ISCraftAction_complete(self)

	if character then
		requestSiteBonus(character, character:getX(), character:getY(), character:getZ())
	end

	return result
end
