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

	-- Search the full advertised distress range, not CREW_RADIUS. Previously
	-- this used the default 12-tile getPartner, so RANGE_TILES (30) was checked
	-- afterwards against a partner who was already guaranteed to be within 12 -
	-- the wider range could never apply, and a call only worked when the partner
	-- was already beside you.
	local partner = TwoManCrew.getPartner(player, cfg.RANGE_TILES)
	if not partner then return end

	-- Re-check against the CLIENT-SUPPLIED position, which is the only thing
	-- here the client controls. getPartner above already guarantees the
	-- partner is within RANGE_TILES of the caller's server-side position, so
	-- this is not the range check any more - it rejects a spoofed args.x/y
	-- that would otherwise let a distant caller alert someone out of range.
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
