-- TwoManCrew_DistressCall.lua
-- Server-authoritative half of the distress call. Re-validates cooldown and
-- range independent of the client, finds the caller's nearest partner, and
-- relays the caller's position to that partner's client only.

require "TwoManCrew/TwoManCrew_Config"

local cfg = TwoManCrew.DistressCall
local COOLDOWN_KEY = "DistressCall_Send"

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "distressCall" then return end
	if not player then return end
	if not args then return end

	-- Re-check cooldown server-side; never trust the client already did.
	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, cfg.COOLDOWN_SECONDS) then
		return
	end

	local partner = TwoManCrew.getPartner(player)
	if not partner then return end

	-- Distress range is intentionally wider than crew radius (config
	-- comment: "how far a distress call can reach beyond crew radius"), so
	-- check it against the caller-supplied position, not CREW_RADIUS.
	local dist = partner:DistTo(args.x, args.y)
	if dist > cfg.RANGE_TILES then return end

	TwoManCrew.startCooldown(player, COOLDOWN_KEY, cfg.COOLDOWN_SECONDS)

	sendServerCommand(partner, TwoManCrew.MODULE, "distressCallAlert", {
		x = args.x,
		y = args.y,
		z = args.z,
	})
end
Events.OnClientCommand.Add(OnClientCommand)
