-- TwoManCrew_TierReport.lua (client)
-- Requests campaign tier progress from the server and stashes the reply for
-- the journal window's Campaign tab to render. No local state is
-- authoritative here; this module only holds what the server last sent.
--
-- Deliberately tolerant of shape: TwoManCrew_Tiers.lua (server) is owned by
-- another agent and its exact field names were not visible while this file
-- was written. TwoManCrew.Client.lastTierProgress is passed straight through
-- to the renderer, which must treat every field as optional.
--
-- Verified: sendClientCommand(playerObj, module, command, args) at
-- client/Context/Inventory/InvContextMedia.lua:36; OnServerCommand handler
-- shape at client/Farming/CFarmingSystem.lua:21 - same pattern as
-- TwoManCrew_CrewReport.lua and TwoManCrew_Campaign.lua (client).

if isServer() then return end

TwoManCrew = TwoManCrew or {}
TwoManCrew.Client = TwoManCrew.Client or {}

-- Last tier-progress reply from the server. nil until the first reply, or if
-- the server-side Tiers module is not yet available (see args.ok below).
TwoManCrew.Client.lastTierProgress = nil

-- True once a reply has actually arrived (as opposed to lastTierProgress
-- being nil because nothing was ever requested). Lets the renderer show
-- "waiting" instead of "unavailable" before the first round trip completes.
TwoManCrew.Client.tierProgressReceived = false

function TwoManCrew.Client.requestTierProgress(player)
	player = player or getPlayer()
	if not player then return end

	sendClientCommand(player, TwoManCrew.MODULE, "requestTierProgress", {})
end

local function onServerCommand(module, command, args)
	if module ~= TwoManCrew.MODULE then return end
	if not args then return end

	-- Reply to the journal window's "Check progress" button. The server
	-- rescanned the claim; report the result and pull fresh tier progress so
	-- the campaign view reflects the rescan rather than the last timer tick.
	if command == "restorationChecked" then
		local player = getPlayer()
		if not player then return end

		if not args.ok then
			HaloTextHelper.addBadText(player, "No claim to check yet.")
			return
		end

		HaloTextHelper.addText(player, "Restored: " .. tostring(args.restored) .. " of " .. tostring(args.total))

		if TwoManCrew.Client.requestTierProgress then
			TwoManCrew.Client.requestTierProgress(player)
		end
		return
	end

	if command ~= "tierProgress" then return end

	TwoManCrew.Client.tierProgressReceived = true

	-- args.progress may be nil (server-side getTierProgress() unavailable or
	-- args.ok false) or any shape the Tiers module chose. Store it verbatim;
	-- the renderer is responsible for tolerating missing fields.
	TwoManCrew.Client.lastTierProgress = args.ok and args.progress or nil
end

Events.OnServerCommand.Add(onServerCommand)
