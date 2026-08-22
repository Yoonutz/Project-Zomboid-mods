-- TwoManCrew_Campaign.lua (client)
--
-- Asks the server to assign the crew a claim, and reports the answer. The
-- client never chooses the block - the server surveys and decides, so both
-- players get the same campaign and neither can reroll for an easier one.
--
-- Verified APIs (installed Build 42.20.3):
--   sendClientCommand(player, module, command, args)
--     client/Context/Inventory/InvContextMedia.lua:36
--   Events.OnServerCommand.Add(fn)  fn(module, command, args)
--     client/Farming/CFarmingSystem.lua:21
--   HaloTextHelper.addText / addBadText
--     client/Foraging/forageClient.lua:73, client/ISUI/ISInventoryPage.lua:1927
--   Events.OnKeyStartPressed.Add(fn)
--     client/ISUI/ISUIHandler.lua:102

require "TwoManCrew/TwoManCrew_Config"

TwoManCrew.Client = TwoManCrew.Client or {}

-- Last claim summary the server sent back, so the crew panel can show progress
-- without asking again.
TwoManCrew.Client.claimSummary = nil

function TwoManCrew.Client.requestClaim(player)
	player = player or getPlayer()
	if not player then return end

	sendClientCommand(player, TwoManCrew.MODULE, "requestClaim", {})

	-- Acknowledge the press immediately. The survey is a server round trip, so
	-- without this the button looks dead whenever the reply is slow or never
	-- arrives - which is exactly how a host running an older build, or no
	-- build at all, presents itself. Silence is the one outcome that tells the
	-- crew nothing; onServerCommand replaces this with the real verdict.
	HaloTextHelper.addText(player, "Surveying the block...")
end

local function onServerCommand(module, command, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "claimAssigned" then return end

	local player = getPlayer()
	if not player or not args then return end

	if not args.ok then
		HaloTextHelper.addBadText(player, "No claim: " .. tostring(args.reason))
		return
	end

	TwoManCrew.Client.claimSummary = {
		count = args.count,
		totalUnits = args.totalUnits,
		restored = args.restored or 0,
	}

	if args.reason == "already assigned" then
		HaloTextHelper.addText(player, "Claim already set - " .. args.count .. " buildings")
	else
		HaloTextHelper.addText(player, "Claim assigned: " .. args.count .. " buildings")
		player:Say("This is our block. Let's rebuild it.")
	end
end

Events.OnServerCommand.Add(onServerCommand)
