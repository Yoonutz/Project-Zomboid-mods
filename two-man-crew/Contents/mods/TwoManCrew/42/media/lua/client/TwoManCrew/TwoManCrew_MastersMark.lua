-- TwoManCrew_MastersMark.lua (client)
-- Detects a locally completed craft (planks, carpentry components, any
-- CraftRecipe result) and, if the crafter's Woodwork is high enough, stamps
-- the produced item's own ModData with a quality mark and asks the server
-- to log the achievement. The mark itself is written here because the
-- crafted item is a brand-new client-side object with no server twin yet
-- (crafting is client-authoritative in vanilla: no server/*/ISCraftAction.lua
-- exists, verified by its absence under D:\...\ProjectZomboid\media\lua\server).
-- Anything shared (tally/journal/XP) still goes through the server.

require "TimedActions/ISCraftAction"

local MODDATA_KEY = "TwoManCrew_MastersMark"

-- ISCraftAction:complete() (shared/TimedActions/ISCraftAction.lua:92) is the
-- vanilla method that actually calls RecipeManager.PerformMakeItem and adds
-- the resulting item(s) to the character's inventory or the floor. It does
-- not expose the produced item list to callers, so for the duration of the
-- wrapped call we temporarily intercept Actions.addOrDropItem
-- (shared/ActionManager.lua:4), the plain Lua global function that receives
-- each produced item on the inventory-crafting branch (ISCraftAction.lua:111),
-- capture the items, then restore the original immediately. This never
-- changes what gets called, only observes it, matching the "wrap, call
-- through" style used in TwoManCrew_FellingBonus.lua (client).
--
-- Deviation: ISCraftAction.lua:109 has a second, from-floor branch that adds
-- items straight via self.container:AddItem on a Java ItemContainer. A Java
-- object's own method cannot be swapped per-instance the way a Lua global
-- can, so that branch is not observed and floor-crafted items go unmarked.
-- Silent no-op there, matching this mod's degrade-gracefully convention.
local original_ISCraftAction_complete = ISCraftAction.complete
local original_addOrDropItem = Actions.addOrDropItem

function ISCraftAction:complete()
	local captured = {}

	Actions.addOrDropItem = function(character, item)
		captured[#captured + 1] = item
		return original_addOrDropItem(character, item)
	end

	local ok, result = pcall(original_ISCraftAction_complete, self)

	Actions.addOrDropItem = original_addOrDropItem

	if not ok then error(result) end

	if not isClient() then return result end

	local character = self.character
	if not character or not instanceof(character, "IsoPlayer") then return result end
	if not character:isLocalPlayer() then return result end
	if #captured == 0 then return result end

	local woodwork = character:getPerkLevel(Perks.Woodwork)
	if woodwork < TwoManCrew.MastersMark.MIN_SKILL_GAP then return result end

	local partner = TwoManCrew.getPartner(character)
	if not partner then return result end -- alone: silent no-op per SPEC

	local markedCount = 0
	for i = 1, #captured do
		local item = captured[i]
		if item then
			local modData = item:getModData()
			if not modData[MODDATA_KEY] then
				modData[MODDATA_KEY] = {
					markedBy = character:getUsername(),
					woodwork = woodwork,
				}
				markedCount = markedCount + 1
			end
		end
	end

	if markedCount == 0 then return result end

	HaloTextHelper.addText(character, "Master's mark!")
	sendClientCommand(character, TwoManCrew.MODULE, "mastersMark", { count = markedCount })

	return result
end
