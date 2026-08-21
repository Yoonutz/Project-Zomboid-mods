-- TwoManCrew_FellingBonus.lua (client)
-- Detects a locally completed tree-felling action, checks a crew partner is
-- nearby, and asks the server to award the bonus. Never grants XP or items
-- itself - the server is authoritative.

require "TimedActions/ISChopTreeAction"

-- Wrap the vanilla perform() so we run after ISTimedActionQueue's own
-- bookkeeping. perform() fires on completion (including forced completion
-- when the tree dies) and is not gated by isClient(), unlike the felling
-- check inside animEvent() at shared/TimedActions/ISChopTreeAction.lua:81,
-- which only runs "if not isClient()". getObjectIndex() == -1 is the
-- vanilla-verified signal that the tree object has been felled, used
-- identically at client/ISUI/ISWorldObjectContextMenu.lua:839.
local original_ISChopTreeAction_perform = ISChopTreeAction.perform

function ISChopTreeAction:perform()
	local tree = self.tree
	local character = self.character

	original_ISChopTreeAction_perform(self)

	-- isServer(), not "not isClient()": isClient() is FALSE in singleplayer
	-- (vanilla's own singleplayer test is `not isClient() and not isServer()`,
	-- shared/TimedActions/ISEatFoodAction.lua:136), so the old guard returned
	-- early on every solo game and silently disabled this feature there. The
	-- real intent is "skip the client half on a dedicated server", which is
	-- exactly isServer().
	if isServer() then return end
	if not tree or not character then return end
	if not instanceof(character, "IsoPlayer") then return end
	if not character:isLocalPlayer() then return end

	-- Tree object is gone from the square only once felling actually completed.
	if tree:getObjectIndex() ~= -1 then return end

	local partner = TwoManCrew.getPartner(character)
	if not partner then return end -- alone: silent no-op per SPEC

	sendClientCommand(character, TwoManCrew.MODULE, "fellingBonus", {})
end
