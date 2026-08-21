-- TwoManCrew_Campaign.lua (server)
--
-- Surveys the ground around the crew and ASSIGNS a claim, rather than letting
-- the players pick. The whole point is that the assignment is sized: a block
-- with a hundred houses is a job, not a campaign, and it would never end.
--
-- The survey walks a grid of sample points around the crew, resolves each to a
-- building, scores that building by how much work restoring it represents, and
-- keeps the set whose TOTAL score lands inside a target band. Too small is
-- trivial, too large never finishes.
--
-- CHUNK-LOADING FIX: a dedicated server only simulates IsoGridSquares near
-- online players. getCell():getGridSquare() returns nil for anything outside
-- that loaded window, so a wide blind sample grid (the original 90-tile /
-- 961-point version) would have silently seen only the handful of points
-- nearest the player and returned near-empty results everywhere else. The fix
-- is to read buildings from the MetaGrid instead: it is world metadata, keyed
-- by x/y alone, and does not require the square to be loaded/simulated.
--
-- Verified APIs (installed Build 42.20.3):
--   getWorld():getMetaGrid()                    client/DebugUIs/DebugChunkState/DebugChunkState_SquarePanel.lua:108,120
--   metaGrid:getAssociatedBuildingAt(x, y)       client/DebugUIs/DebugChunkState/DebugChunkState_SquarePanel.lua:120
--     -> returns a BuildingDef directly (same object square:getBuilding():getDef()
--        would give), independent of chunk load state; nil where there is no building.
--   buildingDef:getIDString()                    client/DebugUIs/DebugChunkState/DebugChunkState_SquarePanel.lua:118,122
--     -> stable per-building key; BuildingDef has no getID(), only IsoBuilding does.
--   buildingDef:getRooms()                       shared/Util/BuildingHelper.lua:9,50
--     (confirmed via instanceof(building, "BuildingDef") guard at BuildingHelper.lua:6)
--   roomList:size() / :get(i)                    shared/Util/BuildingHelper.lua:11-20 (0-indexed)
--   room:getW() / room:getH()                    shared/Util/BuildingHelper.lua:16 (RoomDef, from getRooms())
--   ZombRand(n)                                  shared/Util/BuildingHelper.lua:17,55
--     -> used directly as a 0-indexed list index with no +1, confirming 0..n-1
--   getGameTime():getWorldAgeHours()              server/Farming/SFarmingSystem.lua:258
--
-- square:getBuilding():getID() (IsoBuilding) is real too (SquarePanel.lua:99)
-- but is NOT used here: it needs a loaded square, defeating the whole fix.

require "TwoManCrew/TwoManCrew_Config"

TwoManCrew.Server = TwoManCrew.Server or {}

-- Work units. One "unit" is roughly one room's worth of restoration: board the
-- windows, hang the door, furnish it, clear the dead out.
--
-- The band is the whole design. Its lower edge keeps the campaign from being a
-- weekend chore; its upper edge is what stops the hundred-house problem.
local TARGET_MIN_UNITS = 18
local TARGET_MAX_UNITS = 34

-- A single building bigger than this is rejected outright, however good the
-- block total looks. One cathedral should not swallow the campaign.
local MAX_UNITS_PER_BUILDING = 12

-- How far out to look, and how coarsely. Sampling every tile would be absurd;
-- buildings are far larger than the step, so a coarse grid still finds them.
-- Radius is in tiles. At step 10 this is an 19x19 = 361-point MetaGrid walk,
-- not 961 - MetaGrid reads are metadata lookups (no square load/simulation),
-- but the loop still runs on the main server thread, so keep it modest.
local SEARCH_RADIUS = 90
local SAMPLE_STEP = 10

-- Scores one building by its room count and room sizes. Bigger rooms cost more
-- to furnish, so a warehouse is not priced like a broom cupboard.
--
-- Takes a BuildingDef directly (what metaGrid:getAssociatedBuildingAt(x, y)
-- returns), not an IsoBuilding - see the chunk-loading note at the top of
-- this file for why the survey no longer resolves squares first.
local function scoreBuilding(def)
	if not def then return 0 end

	local rooms = def:getRooms()
	if not rooms then return 0 end

	local count = rooms:size()
	if count == 0 then return 0 end

	local units = 0
	for i = 0, count - 1 do
		local room = rooms:get(i)
		if room then
			local area = (room:getW() or 0) * (room:getH() or 0)
			-- One unit for the room itself, plus one more for every large
			-- span of floor inside it.
			units = units + 1 + math.floor(area / 40)
		end
	end

	return units
end

-- Walks the sample grid and returns candidate buildings keyed by building id,
-- so the same building found from several sample points is counted once.
--
-- Reads buildings from the MetaGrid, not from live IsoGridSquares. A dedicated
-- server only keeps squares loaded/simulated near online players, so
-- getCell():getGridSquare() returns nil far from anyone and a survey built on
-- it would silently see only whatever sits in the tiny loaded window - not the
-- 90-tile area the constants imply. metaGrid:getAssociatedBuildingAt(x, y) is
-- world metadata keyed on x/y alone and answers the same regardless of what is
-- currently simulated, so the survey actually covers the stated radius.
-- No z parameter: metaGrid:getAssociatedBuildingAt(x, y) takes x/y only
-- (DebugChunkState_SquarePanel.lua:120) - a building footprint on the map is
-- ground-plane, not per-floor.
local function surveyBuildings(centreX, centreY)
	local metaGrid = getWorld():getMetaGrid()
	if not metaGrid then return {} end

	local found = {}
	local order = {}

	for dx = -SEARCH_RADIUS, SEARCH_RADIUS, SAMPLE_STEP do
		for dy = -SEARCH_RADIUS, SEARCH_RADIUS, SAMPLE_STEP do
			local def = metaGrid:getAssociatedBuildingAt(centreX + dx, centreY + dy)
			if def then
				local id = def:getIDString()
				if id and not found[id] then
					local units = scoreBuilding(def)
					if units > 0 and units <= MAX_UNITS_PER_BUILDING then
						found[id] = {
							id = id,
							units = units,
							x = centreX + dx,
							y = centreY + dy,
						}
						table.insert(order, found[id])
					end
				end
			end
		end
	end

	return order
end

-- Picks a subset whose total work lands inside the band. Buildings are taken in
-- a shuffled order so two crews on the same spot do not get identical claims,
-- and the walk stops as soon as adding one more would overshoot the ceiling.
local function chooseClaim(candidates)
	-- Fisher-Yates over a Lua array. ZombRand(n) yields 0..n-1.
	for i = #candidates, 2, -1 do
		local j = ZombRand(i) + 1
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	local claim = {}
	local total = 0

	for _, entry in ipairs(candidates) do
		if total + entry.units <= TARGET_MAX_UNITS then
			table.insert(claim, entry)
			total = total + entry.units
		end
		if total >= TARGET_MIN_UNITS then break end
	end

	return claim, total
end

-- True when the crew already holds a claim. The claim is set once and never
-- reassigned: a campaign you can reroll is a campaign with no stakes.
function TwoManCrew.Server.hasClaim()
	local state = TwoManCrew.Server.getState()
	return state.claim ~= nil
end

function TwoManCrew.Server.getClaim()
	local state = TwoManCrew.Server.getState()
	return state.claim
end

-- Surveys around the player and assigns a claim. Returns the claim table, or
-- nil plus a reason string when the ground is unsuitable.
function TwoManCrew.Server.assignClaim(player)
	if not player then return nil, "no player" end
	if TwoManCrew.Server.hasClaim() then
		return TwoManCrew.Server.getClaim(), "already assigned"
	end

	local candidates = surveyBuildings(player:getX(), player:getY())
	if #candidates == 0 then
		return nil, "no buildings in range - move into a town and try again"
	end

	local buildings, total = chooseClaim(candidates)
	if total < TARGET_MIN_UNITS then
		return nil, "not enough standing buildings here for a campaign"
	end

	local state = TwoManCrew.Server.getState()
	state.claim = {
		buildings = buildings,
		totalUnits = total,
		assignedAtHours = getGameTime():getWorldAgeHours(),
		restored = {},
	}

	TwoManCrew.Server.addJournal(
		"claimed " .. #buildings .. " buildings to rebuild (" .. total .. " work units)",
		player
	)

	return state.claim
end

-- Handles the client's request to be assigned a claim.
local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "requestClaim" then return end
	if not player then return end

	local claim, reason = TwoManCrew.Server.assignClaim(player)

	-- restored is what the journal window renders as "X of Y buildings
	-- restored". Without it the window reads summary.restored as nil and shows
	-- a permanent zero, so it is sent here rather than inferred client-side.
	local restored = 0
	if claim and claim.restored then
		for _ in pairs(claim.restored) do
			restored = restored + 1
		end
	end

	sendServerCommand(player, TwoManCrew.MODULE, "claimAssigned", {
		ok = claim ~= nil,
		reason = reason,
		count = claim and #claim.buildings or 0,
		totalUnits = claim and claim.totalUnits or 0,
		restored = restored,
	})
end

Events.OnClientCommand.Add(OnClientCommand)
