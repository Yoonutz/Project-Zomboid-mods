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

-- Returns a Lua array of other IsoPlayer objects within radius tiles of
-- player, excluding player. Safe to call every tick: allocates a table only
-- when at least one other player exists in range.
-- Verified: IsoPlayer.getPlayers() returns a Java-backed list (:size()/:get(i),
-- 0-indexed) per client/ISUI/PlayerData/ISPlayerData.lua:186-187 and
-- server/Seasons/season.lua:124-125. player:DistTo(x, y) takes numeric
-- coordinates per client/Farming/CFarmingSystem.lua:47.
function TwoManCrew.getNearbyCrew(player, radius)
	if not player then return nil end
	radius = radius or TwoManCrew.CREW_RADIUS

	local players = IsoPlayer.getPlayers()
	if not players then return nil end

	local px, py = player:getX(), player:getY()
	local crew = nil

	for i = 0, players:size() - 1 do
		local other = players:get(i)
		if other and other ~= player then
			if other:DistTo(px, py) <= radius then
				if not crew then crew = {} end
				crew[#crew + 1] = other
			end
		end
	end

	return crew
end

-- Returns the single nearest other player within crew radius, or nil.
function TwoManCrew.getPartner(player)
	if not player then return nil end

	local players = IsoPlayer.getPlayers()
	if not players then return nil end

	local px, py = player:getX(), player:getY()
	local nearest, nearestDist = nil, nil

	for i = 0, players:size() - 1 do
		local other = players:get(i)
		if other and other ~= player then
			local dist = other:DistTo(px, py)
			if dist <= TwoManCrew.CREW_RADIUS then
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
