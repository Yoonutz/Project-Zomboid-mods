-- TwoManCrew_TierReport.lua (server)
-- Handles client requests to read campaign tier progress (the five building
-- tiers and four livestock stages from GOALS.md). Server-owned: calls the one
-- public accessor TwoManCrew.Server.getTierProgress() and forwards whatever it
-- returns, verbatim, to the requesting player.
--
-- Deliberately defensive: TwoManCrew_Tiers.lua (which defines
-- getTierProgress()) is owned and written by another agent in parallel, and
-- its final field names were not visible while this file was written. This
-- responder never assumes a shape - it forwards the table as-is and only
-- guards against the function being entirely absent (mod load order, or not
-- yet merged), so a missing/partial Tiers module degrades to "no data" for
-- the client rather than a server-side error.
--
-- Commands handled (module = TwoManCrew.MODULE, verified pattern:
-- server/Camping/camping_tent.lua:183 for OnClientCommand shape,
-- client/ISUI/ISWorldObjectContextMenu.lua:908 for the player-targeted
-- sendServerCommand(player, module, command, args) reply - same pattern as
-- TwoManCrew_CrewReport.lua and TwoManCrew_Campaign.lua):
--   "requestTierProgress" (client -> server, no args needed)
--     -> "tierProgress" (server -> requesting player only)
--        args = {
--          ok = boolean,         -- false when getTierProgress() is unavailable
--          progress = table,     -- whatever TwoManCrew.Server.getTierProgress()
--                                -- returned, forwarded unchanged; nil if ok is false
--        }

if isClient() then return end

require "TwoManCrew/TwoManCrew_Config"

local function onClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if not player then return end
	if command ~= "requestTierProgress" then return end

	local progress = nil
	local ok = false

	-- TwoManCrew.Server.getTierProgress is defined in TwoManCrew_Tiers.lua,
	-- a sibling module owned by another agent. Guard on both the table and
	-- the function existing so load order or an unmerged Tiers module never
	-- throws here.
	if TwoManCrew.Server and type(TwoManCrew.Server.getTierProgress) == "function" then
		local success, result = pcall(TwoManCrew.Server.getTierProgress)
		if success then
			progress = result
			ok = true
		end
	end

	TwoManCrew.replyToPlayer(player, "tierProgress", {
		ok = ok,
		progress = progress,
	})
end

Events.OnClientCommand.Add(onClientCommand)

TwoManCrew.registerLocalHandler("requestTierProgress", function(player, args)
	onClientCommand(TwoManCrew.MODULE, "requestTierProgress", player, args)
end)
