-- TwoManCrew_CrewReport.lua
-- Handles client requests to read the shared crew tally and journal.
-- Server-owned: reads TwoManCrew_CrewState via its public accessors only,
-- never touches ModData directly. Replies to the requesting player alone
-- via sendServerCommand.
--
-- Commands handled (module = TwoManCrew.MODULE, verified pattern:
-- server/Camping/camping_tent.lua:183 for OnClientCommand shape,
-- client/ISUI/ISWorldObjectContextMenu.lua:908 for the player-targeted
-- sendServerCommand(player, module, command, args) reply):
--   "requestCrewReport" (client -> server, no args needed)
--     -> "crewReport" (server -> requesting player only)
--        args = { tally = {...}, journal = {...} }

if isClient() then return end

-- This file reads TwoManCrew.MODULE and calls TwoManCrew.Server.getTally(),
-- but declared neither dependency. It only ever worked by accident of load
-- order: PZ loads this folder alphabetically, so TwoManCrew_Campaign.lua
-- (which does require both) happened to run first and populate the globals.
-- Rename or add a file that sorts ahead of Campaign and the Refresh button
-- would have started erroring on a nil MODULE with nothing here explaining
-- why. Every other server module in this folder declares its requires; this
-- one now does too.
require "TwoManCrew/TwoManCrew_Config"
require "TwoManCrew/TwoManCrew_CrewState"

local function onClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if not player then return end

	if command == "requestCrewReport" then
		-- Read the state under pcall so a reply is always sent. If reading the
		-- shared ModData raised - a partially written save, a schema change -
		-- the error left this handler before sendServerCommand and the client
		-- sat waiting for a reply that never came. From the player's side that
		-- is a Refresh button that does nothing at all, with no error naming
		-- the cause, which is exactly how it was reported.
		local ok, tally, journal = pcall(function()
			return TwoManCrew.Server.getTally(), TwoManCrew.Server.getJournal()
		end)

		if not ok then
			print("TwoManCrew: crew report failed: " .. tostring(tally))
			sendServerCommand(player, TwoManCrew.MODULE, "crewReport", {
				tally = {},
				journal = {},
				failed = true,
			})
			return
		end

		sendServerCommand(player, TwoManCrew.MODULE, "crewReport", {
			tally = tally,
			journal = journal,
		})
	end
end

Events.OnClientCommand.Add(onClientCommand)
