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

-- Last per-building claim detail from the server, as an array of rows (see
-- TwoManCrew.Server.getClaimDetail for the row shape). nil until the first
-- reply arrives.
TwoManCrew.Client.lastClaimDetail = nil

-- True once a claimDetail reply has arrived, so the renderer can distinguish
-- "waiting for the server" from "the server says there is no claim".
TwoManCrew.Client.claimDetailReceived = false

function TwoManCrew.Client.requestTierProgress(player)
	player = player or getPlayer()
	if not player then return end

	TwoManCrew.requestFromServer(player, "requestTierProgress", {})
end

-- Asks the server for the per-building breakdown of the claim. Separate from
-- requestTierProgress because the server rescans the claim to answer this,
-- which is far more expensive than reading stored tier state.
function TwoManCrew.Client.requestClaimDetail(player)
	player = player or getPlayer()
	if not player then return end

	TwoManCrew.requestFromServer(player, "requestClaimDetail", {})
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

		-- Silent unless the player asked. The journal window re-surveys on a
		-- timer while it is open, and every one of those replies used to
		-- raise a halo line, so an open window meant a permanent
		-- "Restored: 0 of 5" scrolling over the character.
		if not args.ok then
			if args.announce then
				HaloTextHelper.addBadText(player, "No claim to check yet.")
			end
			return
		end

		if args.announce then
			HaloTextHelper.addText(player,
				"Restored: " .. tostring(args.restored) .. " of " .. tostring(args.total))
		end

		if TwoManCrew.Client.requestTierProgress then
			TwoManCrew.Client.requestTierProgress(player)
		end
		if TwoManCrew.Client.requestClaimDetail then
			TwoManCrew.Client.requestClaimDetail(player)
		end
		return
	end

	if command == "claimDetail" then
		TwoManCrew.Client.claimDetailReceived = true
		-- args.buildings may be nil when the server has no claim. Stored
		-- verbatim; the renderer tolerates a missing or empty list.
		TwoManCrew.Client.lastClaimDetail = args.ok and args.buildings or nil
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
