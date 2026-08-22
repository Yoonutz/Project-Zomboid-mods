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

-- True between sending a claim request and receiving its reply. Used to stop
-- a second press piling another "Surveying..." on top of the first: repeated
-- presses were reported as the button "spamming" that line, because each one
-- printed it again while the first request was still outstanding.
TwoManCrew.Client.claimPending = false

function TwoManCrew.Client.requestClaim(player)
	player = player or getPlayer()
	if not player then return end

	if TwoManCrew.Client.claimPending then
		HaloTextHelper.addText(player, "Still surveying - wait for the answer")
		return
	end

	print("TwoManCrew[client]: sending requestClaim on module '" ..
		tostring(TwoManCrew.MODULE) .. "'")
	sendClientCommand(player, TwoManCrew.MODULE, "requestClaim", {})
	TwoManCrew.Client.claimPending = true

	-- Acknowledge the press immediately. The survey is a server round trip, so
	-- without this the button looks dead whenever the reply is slow or never
	-- arrives - which is exactly how a host running an older build, or no
	-- build at all, presents itself. Silence is the one outcome that tells the
	-- crew nothing; onServerCommand replaces this with the real verdict.
	HaloTextHelper.addText(player, "Surveying the block...")

	-- Give up waiting after ten seconds and say so. A request that is never
	-- answered used to leave the optimistic line as the final word, which
	-- reads as a broken button rather than a failure. The timer is cancelled
	-- by the reply handler; if it fires, the reply genuinely never arrived.
	local expectAt = getTimestampMs() + 10000
	local function onTick()
		if not TwoManCrew.Client.claimPending then
			Events.OnTick.Remove(onTick)
			return
		end
		if getTimestampMs() < expectAt then return end

		Events.OnTick.Remove(onTick)
		TwoManCrew.Client.claimPending = false

		local p = getPlayer()
		if p then
			HaloTextHelper.addBadText(p, "No answer from the server - claim failed")
		end
		TwoManCrew.Client.lastClaimRefusal = "no answer from the server"
	end

	Events.OnTick.Add(onTick)
end

local function onServerCommand(module, command, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "claimAssigned" then return end

	-- The answer arrived: release the guard and cancel the timeout, whatever
	-- the verdict turns out to be.
	TwoManCrew.Client.claimPending = false

	local player = getPlayer()
	if not player or not args then return end

	if not args.ok then
		local reason = tostring(args.reason)
		HaloTextHelper.addBadText(player, "No claim: " .. reason)

		-- Halo text floats up and fades in a couple of seconds, straight into
		-- whatever the player was looking at. That is fine for a success, but
		-- a refusal is the one message that has to survive being missed - the
		-- reported symptom was "it only says surveying and that's it", which
		-- is exactly what a fading refusal looks like. Say() puts it in the
		-- chat log where it can be re-read, and the journal window picks up
		-- the same reason on its next repaint.
		player:Say("No claim here - " .. reason)
		TwoManCrew.Client.lastClaimRefusal = reason
		return
	end

	TwoManCrew.Client.lastClaimRefusal = nil

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
