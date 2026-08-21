-- TwoManCrew_WatchMyBack.lua (server)
-- Receives each client's self-reported danger state and, if a crew partner
-- is nearby and was last reported as NOT in danger, warns that partner's
-- client.
--
-- Only client/ call sites for getNumChasingZombies/getNumVeryCloseZombies/
-- getNumVisibleZombies were found in vanilla source, plus one server-side
-- function that explicitly bails with `if isServer() then return end`
-- before reading them (SadisticMusicDirector.lua:10-13). Other server
-- code does call playerObj:getStats() successfully for arbitrary players
-- server-side (SFarmingSystem.lua:339-341, XpUpdate.lua:14) but only for
-- simulated mood/endurance CharacterStat values, never the zombie-detection
-- counters, which are plausibly perception/vision-driven and client-local.
-- Absent a verified server-side read, the server never calls the danger
-- getters itself: it only trusts each client's own self-report of its own
-- state, cached per-player, and compares reports between crewmates.

require "TwoManCrew/TwoManCrew_Config"

local cfg = TwoManCrew.WatchMyBack
local WARNED_KEY = "WatchMyBack_Warned"

-- Namespaced per-player modData flag: true while that player last reported
-- itself as being in danger. Verified per-player modData form:
-- client/LastStand/LastStandSetup.lua:77-89 (same helper the SPEC cites).
local DANGER_FLAG_KEY = "TwoManCrew_WatchMyBack_InDanger"

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "watchMyBackDanger" then return end
	if not player then return end
	if not args then return end

	local reporterInDanger = (args.chasing or 0) >= cfg.CHASING_ZOMBIE_THRESHOLD
	local reporterModData = player:getModData()
	reporterModData[DANGER_FLAG_KEY] = reporterInDanger

	if not reporterInDanger then return end

	local crew = TwoManCrew.getNearbyCrew(player, TwoManCrew.CREW_RADIUS)
	if not crew then return end

	-- Per-endangered-player cooldown so a warning fires again only after it
	-- has had time to matter, not once per report from that player.
	if TwoManCrew.onCooldown(player, WARNED_KEY, cfg.WARNING_COOLDOWN_SECONDS) then
		return
	end
	TwoManCrew.startCooldown(player, WARNED_KEY, cfg.WARNING_COOLDOWN_SECONDS)

	for i = 1, #crew do
		local partner = crew[i]
		local partnerModData = partner:getModData()
		local partnerInDanger = partnerModData[DANGER_FLAG_KEY] == true

		if not partnerInDanger then
			sendServerCommand(partner, TwoManCrew.MODULE, "watchMyBackWarning", {})
		end
	end
end
Events.OnClientCommand.Add(OnClientCommand)
