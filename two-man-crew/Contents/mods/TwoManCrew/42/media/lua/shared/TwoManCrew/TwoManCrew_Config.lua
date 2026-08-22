-- TwoManCrew_Config.lua
-- Shared constants and pure helpers for all Two-Man Crew features.
-- No event registration, no state, no side effects. Safe to require from
-- client, server, or shared code.

TwoManCrew = TwoManCrew or {}

-- Command module string used by every sendClientCommand/sendServerCommand call.
TwoManCrew.MODULE = "twomancrew"

-- Default proximity radius (tiles) that defines "crewed up". Features should
-- read this rather than hardcoding their own radius.
TwoManCrew.CREW_RADIUS = 12

-- Per-feature tuning. Keep numbers conservative; these are starting points,
-- not balanced values. Times are in seconds unless noted otherwise.
TwoManCrew.FellingBonus = {
	XP_AMOUNT = 3,          -- Woodwork XP awarded per qualifying tree fell while crewed
	COOLDOWN_SECONDS = 30,  -- minimum gap between bonus awards, per player
}

TwoManCrew.MastersMark = {
	XP_AMOUNT = 2,           -- bonus XP awarded to the apprentice on a witnessed high-skill action
	MIN_SKILL_GAP = 3,       -- perk level difference required between mentor and apprentice
	COOLDOWN_SECONDS = 60,   -- minimum gap between marks, per player
}

TwoManCrew.SharedApprenticeship = {
	XP_SHARE_FRACTION = 0.25, -- fraction of the primary actor's XP mirrored to the partner
	COOLDOWN_SECONDS = 20,    -- minimum gap between shared XP awards, per player
	BASE_XP = 3,              -- XP the trickle is scaled from; own value, not another feature's
	MIN_SKILL_GAP = 3,        -- levels the mentor must lead by before the apprentice learns
}

TwoManCrew.CrewTally = {
	UPDATE_INTERVAL_SECONDS = 5, -- how often the tally UI/state is allowed to refresh
}

TwoManCrew.WatchMyBack = {
	CHASING_ZOMBIE_THRESHOLD = 1, -- getNumChasingZombies() at/above this triggers a warning
	WARNING_COOLDOWN_SECONDS = 15, -- minimum gap between warnings sent to the partner
}

TwoManCrew.TwoManCarry = {
	MAX_CARRY_WEIGHT = 40,  -- combined weight (in-game weight units) two players may carry together
	INTERACT_RANGE = 2,     -- tiles apart the pair may drift before the carry breaks
	XP_AMOUNT = 2,          -- Strength XP for hauling heavy beside a partner
	COOLDOWN_SECONDS = 60,  -- minimum gap between carry rewards, per player
}

TwoManCrew.SiteRadius = {
	RADIUS_TILES = 10,        -- work-site radius used to credit both crew members
	CHECK_INTERVAL_SECONDS = 10, -- how often site membership is re-evaluated
	XP_AMOUNT = 2,            -- Woodwork XP for finishing work beside a partner
}

TwoManCrew.ShiftChange = {
	XP_AMOUNT = 2,            -- Fitness XP for sharing the night watch with a partner
	SHIFT_LENGTH_HOURS = 2,   -- in-game hours before a "shift change" reminder fires
	REMINDER_COOLDOWN_SECONDS = 300, -- minimum real-seconds gap between reminders
}

TwoManCrew.CrewJournal = {
	MAX_ENTRIES = 50,        -- cap on stored journal entries per crew, oldest trimmed first
	ENTRY_COOLDOWN_SECONDS = 10, -- minimum gap between auto-logged entries
}

TwoManCrew.DistressCall = {
	COOLDOWN_SECONDS = 45,   -- minimum gap between distress calls, per player
	RANGE_TILES = 30,        -- how far a distress call can reach beyond crew radius
}

-- WHY THIS EXISTS: every other restoration condition tested the ABSENCE of
-- damage - an unbroken window, a doorway that still has its door, no corpse
-- inside. A house nobody had touched satisfied all of them on day one, so
-- claiming a block completed tiers with no work done. Playtested 0.10.6.
--
-- Barricades are the fix because the map never spawns one. The only things that
-- create a barricade are the player's own timed action (ISBarricadeAction) and
-- a debug-only trailer scenario. So requiring planks is a direct measure of
-- crew labour rather than of luck about how the house spawned.
TwoManCrew.Restoration = {
	-- Planks required on each ground-floor opening. Vanilla's own "fully
	-- boarded" test is 4 (client/DebugUIs/DebugContextMenu.lua:372); 2 is a
	-- deliberately gentler starting bar, since the step from zero to any
	-- barricade is where the difficulty actually comes from.
	MIN_PLANKS = 2,

	-- A metal sheet or metal bars count instead of planks. Both are strictly
	-- more work than boards, so refusing them would punish the better job.
	ACCEPT_METAL = true,
}

-- Returns a plain Lua array of every player this machine can currently see.
--
-- THE BUG THIS REPLACES: every server-side and shared caller used
-- IsoPlayer.getPlayers(), which returns only players on the LOCAL machine
-- (split-screen). On a dedicated server the remote player is not in that list,
-- so getPartner() returned nil and every crew feature silently no-opped for the
-- second player.
--
-- Vanilla's own rule, verified: server code uses getOnlinePlayers()
-- (server/Foraging/forageServer.lua:463, server/XpSystem/XpUpdate.lua:300,
-- server/ClientCommands.lua:628). The single IsoPlayer.getPlayers() in the whole
-- vanilla server/ tree is inside a commented-out block
-- (server/Seasons/season.lua:121-124).
--
-- getOnlinePlayers() covers every multiplayer case, host and client alike.
-- Singleplayer has no online-player list at all, so it goes through
-- getSpecificPlayer instead - the same branch vanilla uses at
-- server/XpSystem/XpUpdate.lua:301-303. This repo has
-- already shipped one singleplayer regression from ignoring that case
-- (commit 4e8980c), so the branch is deliberate, not defensive noise.
function TwoManCrew.getAllPlayers()
	local result = {}

	-- Any multiplayer context, either side of the connection. NOT isServer()
	-- alone: that is false on a listen/co-op host and on every remote client,
	-- both of which would then fall through to the split-screen branch below
	-- and never see the other player - the exact bug this function exists to
	-- fix. getOnlinePlayers() is valid client-side too, verified at
	-- client/Chat/ISChat.lua:560 and client/DebugUIs/ISTriggerThunderUI.lua:13.
	-- Vanilla's own multiplayer test is this same pair
	-- (shared/NPCs/MainCreationMethods.lua:104).
	if isClient() or isServer() then
		local players = getOnlinePlayers()
		if players then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p then table.insert(result, p) end
			end
		end
		return result
	end

	local count = getNumActivePlayers()
	if count and count > 0 then
		for i = 0, count - 1 do
			local p = getSpecificPlayer(i)
			if p then table.insert(result, p) end
		end
	end

	-- Singleplayer with no split-screen still has exactly one player, and
	-- getNumActivePlayers() has been seen to report 0 during early load.
	if #result == 0 then
		local p = getPlayer()
		if p then table.insert(result, p) end
	end

	return result
end

-- Returns a Lua array of other IsoPlayer objects within radius tiles of
-- player, excluding player, or nil when nobody else is in range (callers rely
-- on the nil, not an empty table).
-- Verified: player:DistTo(x, y) takes numeric coordinates per
-- client/Farming/CFarmingSystem.lua:47.
function TwoManCrew.getNearbyCrew(player, radius)
	if not player then return nil end
	radius = radius or TwoManCrew.CREW_RADIUS

	local px, py = player:getX(), player:getY()
	local found = nil

	for _, other in ipairs(TwoManCrew.getAllPlayers()) do
		if other ~= player then
			if other:DistTo(px, py) <= radius then
				found = found or {}
				table.insert(found, other)
			end
		end
	end

	return found
end

-- Returns the single nearest other player within radius, or nil.
-- radius defaults to CREW_RADIUS so existing callers are unchanged; the
-- distress call passes its own wider range.
function TwoManCrew.getPartner(player, radius)
	if not player then return nil end
	radius = radius or TwoManCrew.CREW_RADIUS

	local px, py = player:getX(), player:getY()
	local nearest, nearestDist = nil, nil

	for _, other in ipairs(TwoManCrew.getAllPlayers()) do
		if other ~= player then
			local dist = other:DistTo(px, py)
			if dist <= radius then
				if not nearestDist or dist < nearestDist then
					nearest = other
					nearestDist = dist
				end
			end
		end
	end

	return nearest
end

-- True when no other player is within crew radius. Features use this to
-- degrade silently to a no-op.
function TwoManCrew.isAlone(player)
	if not player then return true end
	return TwoManCrew.getPartner(player) == nil
end

-- Cooldown storage lives under a namespaced sub-table in the player's own
-- modData so multiple features never collide on key names.
-- Verified: player:getModData() returns a plain per-player Lua table
-- directly (no getOrCreate needed) per client/LastStand/LastStandSetup.lua:77-89.
local COOLDOWN_KEY = "TwoManCrew_Cooldowns"

local function getCooldownTable(player)
	local modData = player:getModData()
	local cooldowns = modData[COOLDOWN_KEY]
	if not cooldowns then
		cooldowns = {}
		modData[COOLDOWN_KEY] = cooldowns
	end
	return cooldowns
end

-- Time source for cooldowns: getGameTime():getWorldAgeHours(), a single
-- monotonically increasing float (fractional in-game hours since world
-- start). Chosen over getDay()/getHour() because it needs no day-rollover
-- arithmetic to compare two timestamps or measure an elapsed span.
-- Verified present and used server-side (authoritative-safe) at
-- server/Farming/SFarmingSystem.lua:258, server/Traps/STrapGlobalObject.lua:449,
-- server/Vehicles/Vehicles.lua:124.
local SECONDS_PER_HOUR = 3600

-- True when key is still cooling down for player.
function TwoManCrew.onCooldown(player, key, seconds)
	if not player or not key then return false end

	local cooldowns = getCooldownTable(player)
	local startedAt = cooldowns[key]
	if not startedAt then return false end

	local nowHours = getGameTime():getWorldAgeHours()
	local elapsedSeconds = (nowHours - startedAt) * SECONDS_PER_HOUR
	return elapsedSeconds < seconds
end

-- Marks key as starting its cooldown now, for seconds duration (duration is
-- not stored; onCooldown is passed the same seconds value each call).
function TwoManCrew.startCooldown(player, key, seconds)
	if not player or not key then return end

	local cooldowns = getCooldownTable(player)
	cooldowns[key] = getGameTime():getWorldAgeHours()
end

-- Request/reply across the client-server split, singleplayer included.
--
-- ROOT CAUSE this exists to fix, found by instrumenting the live game
-- (2026-08-22): sendServerCommand does NOT reach the local player in
-- singleplayer. It is a network send, and solo there is no network client to
-- deliver to, so Events.OnServerCommand never fires. The log showed the chain
-- reaching the server fourteen times and replying zero times.
--
-- Vanilla never hits this because it never relies on that path solo. Every
-- shipped caller is multiplayer-only: forageServer.lua bails at line 1 with
-- `if not isServer() then return end`, and ClientCommands.lua's only reply
-- targets a player found via getPlayerByOnlineID, which is a multiplayer
-- lookup. Vanilla's client code makes the round trip conditional instead -
-- `if isClient() and _character then` at client/Foraging/forageClient.lua:40 -
-- and calls the logic directly when solo. This mirrors that.
--
-- isClient() and isServer() are BOTH false in singleplayer, which is what
-- makes a single check enough to tell the two worlds apart.

--- True when this game has a real network split - a multiplayer client or a
--- server. False in singleplayer, where both halves live in one process.
function TwoManCrew.isNetworked()
	return isClient() or isServer()
end

--- Server-side handlers register here so singleplayer can reach them without
--- a network hop. Keyed by command name.
TwoManCrew.LocalHandlers = TwoManCrew.LocalHandlers or {}

--- Registers a server handler for local (singleplayer) dispatch. Server files
--- call this next to their Events.OnClientCommand.Add, so the same function
--- serves both worlds and the two cannot drift apart.
function TwoManCrew.registerLocalHandler(command, fn)
	TwoManCrew.LocalHandlers[command] = fn
end

--- Sends a command to the server, or runs it directly when singleplayer.
--- Use this instead of sendClientCommand for anything expecting a REPLY.
--- Fire-and-forget commands are unaffected: they already work solo, because
--- OnClientCommand is dispatched locally - it is only the reply that is lost.
function TwoManCrew.requestFromServer(player, command, args)
	player = player or getPlayer()
	if not player then return end

	if TwoManCrew.isNetworked() then
		sendClientCommand(player, TwoManCrew.MODULE, command, args or {})
		return
	end

	local handler = TwoManCrew.LocalHandlers[command]
	if not handler then
		-- No local handler means the server file did not register one. Say so
		-- rather than failing silently, which is the behaviour that made this
		-- bug cost three wrong builds.
		print("TwoManCrew: no local handler for '" .. tostring(command) .. "'")
		return
	end

	handler(player, args or {})
end

--- Delivers a reply to the player. In multiplayer this is the normal network
--- send; in singleplayer it invokes the client's OnServerCommand handlers
--- directly, because sendServerCommand cannot reach a local player.
function TwoManCrew.replyToPlayer(player, command, args)
	if TwoManCrew.isNetworked() then
		sendServerCommand(player, TwoManCrew.MODULE, command, args or {})
		return
	end

	-- triggerEvent is the engine's own way to fire a registered event, so the
	-- client handlers stay untouched and identical in both worlds.
	-- Verified: triggerEvent(name, ...) has 85 call sites in the shipped
	-- source, e.g. client/DebugUIs/DebugMenu/General/ISDebugBlood.lua:74
	-- triggerEvent("OnClothingUpdated", playerObj) - the event name followed
	-- by that event's own argument list.
	triggerEvent("OnServerCommand", TwoManCrew.MODULE, command, args or {})
end
