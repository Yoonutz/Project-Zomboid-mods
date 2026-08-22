-- TwoManCrew_DistressCall.lua
-- One keypress sends the caller's position to their crew partner as an
-- on-screen alert with direction and distance.
--
-- Keybinding mechanism: B42 has no public "register a new named mod
-- keybind" API verified in the installed source - shared/keyBinding.lua's
-- `keyBinding` table drives the built-in options screen and is populated
-- entirely by vanilla entries (verified: shared/keyBinding.lua:8-374).
-- The verified, safe mod pattern is a direct Events.OnKeyStartPressed
-- listener compared against a literal Keyboard.KEY_* constant, exactly as
-- vanilla code itself does (verified: client/ISUI/ISUIHandler.lua:35
-- `ISUIHandler.onKeyStartPressed = function(key)`, registered at :102
-- `Events.OnKeyStartPressed.Add(ISUIHandler.onKeyStartPressed)`; the
-- fired `key` is a raw keycode compared with vanilla's own
-- `Keyboard.KEY_F8` at client/ISUI/Maps/Editor/WorldMapEditor.lua:209).
--
-- Default key: F9. Checked against every `bind.key = Keyboard.KEY_*`
-- entry in shared/keyBinding.lua (the full vanilla bindable-key list) and
-- against every Keyboard.KEY_* literal comparison anywhere else in the
-- installed lua tree - F9 does not appear in either. F8 was ruled out
-- because it is read by the world map editor debug screen (see above);
-- F9 has zero hits anywhere in the source tree.

require "TwoManCrew/TwoManCrew_Config"

local cfg = TwoManCrew.DistressCall

-- Client-only key, deliberately NOT the server's "DistressCall_Send".
-- On a listen-server host (and anywhere client and server Lua share one state)
-- both halves read the same player:getModData() table, so reusing one key made
-- the client's own optimistic cooldown block the server handler that runs
-- immediately after - the partner was never alerted. The server keeps its own
-- key and stays authoritative; this one only stops a keypress burst locally.
local COOLDOWN_KEY = "DistressCall_SendLocal"

local DISTRESS_KEY = Keyboard.KEY_F9

local function onKeyStartPressed(key)
	if key ~= DISTRESS_KEY then return end
	if isServer() then return end

	local player = getPlayer()
	if not player then return end

	-- Say something rather than nothing. This used to return silently, so a
	-- crew with no partner in range experienced F9 as a dead key with no
	-- indication whether the mod was even loaded.
	if TwoManCrew.getPartner(player, cfg.RANGE_TILES) == nil then
		HaloTextHelper.addBadText(player, "No crew partner in range.")
		return
	end

	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, cfg.COOLDOWN_SECONDS) then
		HaloTextHelper.addText(player, "Distress call still on cooldown.")
		return
	end

	-- Client starts its own cooldown optimistically so a burst of keypresses
	-- before the server round-trip can't queue multiple sends. The server
	-- re-validates the cooldown independently and is authoritative.
	TwoManCrew.startCooldown(player, COOLDOWN_KEY, cfg.COOLDOWN_SECONDS)

	sendClientCommand(player, TwoManCrew.MODULE, "distressCall", {
		x = player:getX(),
		y = player:getY(),
		z = player:getZ(),
	})

	HaloTextHelper.addText(player, "Distress call sent.")
end
Events.OnKeyStartPressed.Add(onKeyStartPressed)

-- Converts a caller-to-receiver offset into an 8-point compass direction,
-- in world/screen tile-space where +x is east and +y is south (matches
-- the dx/-dy convention already verified in vanilla at
-- client/Foraging/ISBaseIcon.lua:210: math.atan2(dx, -dy)).
local function directionLabel(dx, dy)
	local angle = math.atan2(dx, -dy) -- radians, 0 = north, clockwise positive
	local degrees = angle * (180 / math.pi)
	if degrees < 0 then degrees = degrees + 360 end

	local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	local index = math.floor((degrees / 45) + 0.5) % 8
	return DIRS[index + 1]
end

-- Server relays a partner's distress call to this client, already
-- range-checked. Renders direction + distance so the receiver does not
-- need to read raw coordinates.
local function OnServerCommand(module, command, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "distressCallAlert" then return end
	if not args then return end

	local player = getPlayer()
	if not player then return end

	local dx = args.x - player:getX()
	local dy = args.y - player:getY()
	local distance = math.sqrt(dx * dx + dy * dy)
	local dir = directionLabel(dx, dy)

	HaloTextHelper.addBadText(player, "Distress call: " .. dir .. ", " .. tostring(math.floor(distance + 0.5)) .. " tiles!")
	player:Say("My partner needs help!")
end
Events.OnServerCommand.Add(OnServerCommand)
