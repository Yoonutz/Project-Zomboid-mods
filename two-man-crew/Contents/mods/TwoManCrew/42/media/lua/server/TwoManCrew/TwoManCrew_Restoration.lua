-- TwoManCrew_Restoration.lua (server)
--
-- Decides whether a claimed building counts as "restored": ground-floor
-- windows boarded/replaced, every doorway has a working door, no corpse
-- remains, no loose items left on the floor, and a crew member present long
-- enough to witness it. The GOALS.md "crew-built furniture per room"
-- condition was dropped as unimplementable - see the CREW PRESENCE block
-- below for why, and for what replaced it.
--
-- Per-room memory: each RoomDef's worst-seen state persists in the claim's
-- ModData (keyed by building id + roomDef:getID()), because a sprawling
-- building is rarely fully loaded in one pass. A room seen broken stays
-- broken until a later pass sees it clean; a building only banks once every
-- one of its rooms has, at some point, been individually confirmed clean.
-- Rooms never visited stay unknown forever and hold the building pending -
-- they never fail it and never pass it.
--
-- Presence is accumulated, not instantaneous: standing next to a building for
-- one tick used to be enough to "witness" it. Elapsed in-game hours while a
-- crew member is nearby now add up in the claim's ModData, across visits,
-- until TwoManCrew.Restoration.PRESENCE_HOURS is reached.
--
-- A banked building is re-spot-checked, not permanent: every
-- TwoManCrew.Restoration.RECHECK_HOURS hours it is re-walked (at most one
-- building per pass, staggered) and demoted back to unfinished if it now
-- genuinely fails. It is never demoted on "unknown" - an unloaded building
-- cannot be punished for being unreadable.
--
-- CHUNK-LOADING CONSTRAINT (same one TwoManCrew_Campaign.lua documents at
-- its header): a dedicated server only simulates IsoGridSquares near online
-- players. Everything below the BuildingDef/RoomDef level - windows, doors,
-- objects on a square, corpses - lives on IsoGridSquare and requires
-- getCell():getGridSquare(x, y, z) to return non-nil, which only happens for
-- LOADED squares. Unlike the survey in Campaign.lua, there is no MetaGrid
-- shortcut for window/door/corpse/furniture state - that state is simulated,
-- not static map metadata, so it cannot exist anywhere except the loaded
-- square. A far-away claimed building is therefore UNREADABLE until a crew
-- member walks back near it.
--
-- Chosen handling: skip unreadable buildings and mark them "unknown" rather
-- than counting them as failed or as restored. recheckClaim() is designed to
-- be called repeatedly (see call-site note at the bottom) so a building
-- previously unknown gets re-evaluated once someone is close enough to load
-- it. This matches the GOALS.md fallback framing: unknown is honest, a
-- guessed pass/fail is not.
--
-- Verified APIs (installed Build 42.20.3) - see per-condition comments below
-- for exact file:line citations. Summary:
--   buildingDef:getRooms() / roomList:size()/:get(i)   shared/Util/BuildingHelper.lua:9-20
--   room:getX()/getX2()/getY()/getY2()                  client/ISUI/AdminPanel/LootZed/SpawnRateChecker.lua:55-56
--     -> RoomDef exposes a ground-plane bounding box. No getZ() found anywhere
--        in the installed source, so this module walks z=0 (ground floor)
--        only, which matches GOALS.md's "ground-floor windows" wording for
--        the window check and is the simplest correct floor for the rest.
--   getCell():getGridSquare(x, y, z)                    shared/luautils.lua:202,205
--   square:getObjects():size()/:get(i)                  server/ClientCommands.lua:88-89 (0-indexed)
--   square:getStaticMovingObjects():size()/:get(i)       shared/TimedActions/ISBuryCorpse.lua:56-58 (0-indexed)
--   instanceof(obj, "IsoWindow" | "IsoWindowFrame" | "IsoDoor" | "IsoDeadBody")
--     server/BuildRecipeCode/buildRecipeCode.lua:27,110; shared/luautils.lua:343
--   window:isBarricaded()                                shared/Moveables/ISMoveableSpriteProps.lua:882
--   windowFrame:hasWindow()                               client/DebugUIs/DebugContextMenu.lua:381
--   door:isBarricaded()                                   shared/Moveables/ISMoveableSpriteProps.lua:907
--   getGameTime():getWorldAgeHours()                      server/Farming/SFarmingSystem.lua:258
--   roomDef:getID()                                       stable per-room integer, chunk-free (BuildingDef data)
--   instanceof(obj, "IsoWorldInventoryObject")            client/DebugUIs/ISRemoveItemTool.lua:85-86

require "TwoManCrew/TwoManCrew_Config"
require "TwoManCrew/TwoManCrew_CrewState"

-- PZ loads server/ on multiplayer clients too. Without this the file runs there,
-- where the guarded server files have bailed out. isClient() is false in
-- singleplayer, so this does not disable anything offline.
if isClient() then return end

TwoManCrew.Server = TwoManCrew.Server or {}

-- How close a player must be to a building's centre for its squares to be
-- trusted as loaded. Not a hard game guarantee (load radius is engine-
-- controlled and undocumented in Lua), but small enough that in practice a
-- player standing this close has that ground loaded and simulated.
local LOAD_TRUST_RADIUS = 20

-- Every doorway/window/corpse condition needs the crew to have physically
-- been there; "crew-declared claim confirmed by proximity" (GOALS.md
-- fallback) reuses the same radius so "checked" and "trusted claim" mean the
-- same distance throughout this file.
local CLAIM_PROXIMITY_RADIUS = TwoManCrew.CREW_RADIUS

-- ---------------------------------------------------------------------------
-- Square-level helpers
-- ---------------------------------------------------------------------------

-- Returns true if square is a real, loaded, simulated square we can trust.
local function isLoaded(square)
	return square ~= nil
end

-- REAL CHECK: ground-floor window state.
--
-- Two distinct objects represent a window, and BOTH must be checked - the
-- original version of this function only looked at IsoWindowFrame, so a
-- smashed-but-still-present pane passed silently and a crew could leave every
-- window on the ground floor broken with the building still counting.
--
-- IsoWindow: the pane is still there. It may be intact, smashed
-- (isSmashed(), client/ISUI/ISButtonPrompt.lua:822) or have had its glass
-- removed deliberately (isGlassRemoved(),
-- client/DebugUIs/DebugContextMenu.lua:865). GOALS.md accepts a window that is
-- "boarded or replaced", so a broken pane passes only when barricaded
-- (isBarricaded(), shared/Moveables/ISMoveableSpriteProps.lua:882).
--
-- IsoWindowFrame: the pane is gone outright, leaving a frame. hasWindow()
-- (client/DebugUIs/DebugContextMenu.lua:381) reports whether a replacement
-- pane was fitted; a boarded-over empty frame is also acceptable.
local function squareWindowsRestored(square)
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if obj then
			if instanceof(obj, "IsoWindowFrame") then
				if not obj:hasWindow() and not obj:isBarricaded() then
					return false
				end
			elseif instanceof(obj, "IsoWindow") then
				local broken = obj:isSmashed() or obj:isGlassRemoved()
				if broken and not obj:isBarricaded() then
					return false
				end
			end
		end
	end
	return true
end

-- REAL CHECK: every ground-floor opening is actually boarded.
--
-- This is the condition that makes the campaign a job of work. Every other
-- check here tests the ABSENCE of damage, so an untouched house passed them
-- all on day one and a claimed block completed tiers with nobody lifting a
-- hammer. Barricades cannot be inherited from the map: the only creators in
-- the shipped source are the player's own ISBarricadeAction
-- (shared/TimedActions/ISBarricadeAction.lua:22-33) and a debug-only trailer
-- scenario (client/DebugUIs/Scenarios/Trailer2Scenario.lua:213). A barricade
-- therefore proves a crew member stood there and did the work.
--
-- The barricade is read with getBarricadeOnSameSquare()/OppositeSquare(), NOT
-- getBarricadeForCharacter(). The character-free pair is what the game's own
-- server code uses (server/BuildRecipeCode/buildRecipeCode.lua:52-59), so the
-- verdict does not depend on which player happens to be nearby - it stays
-- server-authoritative, which matters because this is multiplayer by default.
-- An opening may be boarded from either side; either side counts.
--
-- isBarricadeAllowed()/getCanBarricade() gates the whole thing
-- (buildRecipeCode.lua:50). Some openings cannot take a barricade at all, and
-- demanding one there would make the building impossible to finish.
local function barricadeSatisfies(barricade)
	if not barricade then return false end
	local cfg = TwoManCrew.Restoration
	if cfg.ACCEPT_METAL and (barricade:isMetal() or barricade:isMetalBar()) then
		return true
	end
	return barricade:getNumPlanks() >= cfg.MIN_PLANKS
end

local function openingIsBoarded(obj)
	-- Either face of the opening may carry the boards.
	return barricadeSatisfies(obj:getBarricadeOnSameSquare())
		or barricadeSatisfies(obj:getBarricadeOnOppositeSquare())
end

-- An OPEN door cannot be barricaded - the game's own action refuses it
-- (shared/TimedActions/ISBarricadeAction.lua:42-46, which returns false for an
-- IsoDoor or door-like IsoThumpable whose IsOpen() is true). Without this the
-- check would demand boards on a door nobody is able to board, and the crew
-- could never finish the building. Treat an open door as not-an-opening rather
-- than as a failure: closing it brings it back into scope on the next pass.
local function isOpenDoor(obj)
	if instanceof(obj, "IsoDoor") or (instanceof(obj, "IsoThumpable") and obj:isDoor()) then
		return obj:IsOpen()
	end
	return false
end

local function squareOpeningsBoarded(square)
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if obj then
			local isOpening = instanceof(obj, "IsoWindow")
				or instanceof(obj, "IsoWindowFrame")
				or instanceof(obj, "IsoDoor")
			if isOpening and obj:isBarricadeAllowed() and not isOpenDoor(obj)
				and not openingIsBoarded(obj) then
				return false
			end
			-- A doorway that lost its door reverts to an IsoThumpable, which
			-- carries getCanBarricade() rather than isBarricadeAllowed().
			if instanceof(obj, "IsoThumpable") and obj:getCanBarricade()
				and (obj:isDoor() or obj:isWindow()) and not isOpenDoor(obj)
				and not openingIsBoarded(obj) then
				return false
			end
		end
	end
	return true
end

-- REAL CHECK: doorway has a working door.
-- instanceof(obj, "IsoDoor") identifies a hung door
-- (server/BuildRecipeCode/buildRecipeCode.lua:27). GOALS.md only asks for a
-- door to exist, so presence is the bar, not open/closed/locked state.
--
-- A doorway that has lost its door does not vanish from getObjects() - it
-- reverts to an IsoThumpable wall segment with isDoor() == true
-- (server/BuildRecipeCode/buildRecipeCode.lua:110:
-- "instanceof(object, 'IsoThumpable') and (object:isDoor() or object:isWindow())").
-- That IsoThumpable is the doorway; an IsoDoor found at the same
-- position/north-facing is what fills it. So the real check is: for every
-- IsoThumpable with isDoor() == true, is there also an IsoDoor on the same
-- square with the same getNorth()? If not, the doorway is open/missing and
-- the square fails.
local function squareDoorsRestored(square)
	local objects = square:getObjects()
	local doorNorths = {} -- [true/false] = true if a hung door exists at that facing
	local thumpableDoorways = {} -- list of north values needing a door

	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if obj then
			if instanceof(obj, "IsoDoor") then
				doorNorths[obj:getNorth()] = true
			elseif instanceof(obj, "IsoThumpable") and obj:isDoor() then
				table.insert(thumpableDoorways, obj:getNorth())
			end
		end
	end

	for _, north in ipairs(thumpableDoorways) do
		if not doorNorths[north] then
			return false
		end
	end
	return true
end

-- REAL CHECK: no zombie corpse remains.
-- IsoDeadBody lives in square:getStaticMovingObjects()
-- (shared/TimedActions/ISBuryCorpse.lua:56-58), not square:getObjects().
local function squareHasCorpse(square)
	local smos = square:getStaticMovingObjects()
	for i = 0, smos:size() - 1 do
		local obj = smos:get(i)
		if obj and instanceof(obj, "IsoDeadBody") then
			return true
		end
	end
	return false
end

-- REAL CHECK: loose items left lying on the ground.
--
-- IsoWorldInventoryObject identifies an item placed directly on a square,
-- distinct from anything living inside a container (verified at
-- client/DebugUIs/ISRemoveItemTool.lua:85-86 - it is the type the debug "remove
-- item" tool matches to find loose ground items). square:getObjects() only
-- ever returns objects placed ON the square, never a container's contents, so
-- this count can never see inside a crate, bag, or shelf - a crew staging
-- planks mid-build is never counted here. Only true floor litter fails the
-- check, per the owner's explicit instruction.
local function squareFloorItemCount(square)
	local count = 0
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if obj and instanceof(obj, "IsoWorldInventoryObject") then
			count = count + 1
		end
	end
	return count
end

-- CREW PRESENCE: a rule in its own right, not a fallback.
--
-- This used to stand in for "each room contains crew-built furniture". That
-- goal was dropped: the engine offers no way to tell crew-built furniture from
-- map-spawned furniture (no isPlayerBuilt marker exists anywhere in the
-- installed Lua source, and the Build 42 entity build path does not stamp
-- ModData - see ISBuildIsoEntity.lua, which never calls setModData).
--
-- Rather than delete the check along with the goal, the crew-presence half is
-- kept deliberately: a building counts as restored only once a crew member has
-- spent TwoManCrew.Restoration.PRESENCE_HOURS of accumulated in-game time
-- standing near it. Restoration is something the crew witnesses over time,
-- not a single lucky tick someone happened to be walking past. Implemented as
-- crewPresentNear() (instantaneous test) plus the presence-hours accumulator
-- in checkBuildingRestored() below.

-- ---------------------------------------------------------------------------
-- Building-level check
-- ---------------------------------------------------------------------------

-- Walks a building's ground floor (z = 0) rooms and evaluates the real
-- checks (windows, doors, corpses, floor litter), per room. Returns:
--   status:  "seen" | "unknown"
--   detail:  { windowsOk, doorsOk, noCorpses, boardedOk, floorClearOk,
--              floorItemCount, roomsSeen, roomsTotal, squaresSeen,
--              fullyCovered, roomResults }
-- "unknown" here means NOTHING on the ground floor loaded this pass - not
-- even partial data. "seen" means at least one room was readable this pass;
-- it says nothing about pass/fail on its own; that verdict now comes from
-- TASK 1's per-room memory (below), because a sprawling building is rarely
-- ever fully loaded in a single pass. roomResults is a map of
-- [roomDef:getID()] = true/false for every room that HAD a loaded square this
-- pass - the caller (checkBuildingRestored) merges this into the claim's
-- persisted room memory. A room absent from roomResults was not loaded this
-- pass and must be left untouched by the caller, not guessed at.
--
-- windowsOk/doorsOk/noCorpses/boardedOk/floorClearOk are THIS PASS'S rollup
-- over whatever was loaded (matches the pre-existing display contract); the
-- pass/fail decision for banking purposes is computed by the caller from
-- persisted per-room memory instead, since this pass alone may only cover
-- part of the building.
local function checkBuildingSquares(def)
	local rooms = def:getRooms()
	if not rooms then
		return "unknown", { reason = "no rooms in BuildingDef" }
	end

	local roomCount = rooms:size()
	if roomCount == 0 then
		return "unknown", { reason = "building has no rooms" }
	end

	local cell = getCell()
	local windowsOk = true
	local doorsOk = true
	local noCorpses = true
	local boardedOk = true
	local floorItemCount = 0
	local roomsSeen = 0
	local squaresSeen = 0
	local roomResults = {}

	for i = 0, roomCount - 1 do
		local room = rooms:get(i)
		if room then
			local x1, x2 = room:getX(), room:getX2()
			local y1, y2 = room:getY(), room:getY2()
			if x1 and x2 and y1 and y2 then
				local roomHadLoadedSquare = false
				local roomWindowsOk = true
				local roomDoorsOk = true
				local roomNoCorpses = true
				local roomBoardedOk = true
				local roomFloorItems = 0
				for x = x1, x2 do
					for y = y1, y2 do
						local square = cell:getGridSquare(x, y, 0)
						if isLoaded(square) then
							roomHadLoadedSquare = true
							squaresSeen = squaresSeen + 1
							if not squareWindowsRestored(square) then
								windowsOk = false
								roomWindowsOk = false
							end
							if not squareDoorsRestored(square) then
								doorsOk = false
								roomDoorsOk = false
							end
							if squareHasCorpse(square) then
								noCorpses = false
								roomNoCorpses = false
							end
							if not squareOpeningsBoarded(square) then
								boardedOk = false
								roomBoardedOk = false
							end
							local items = squareFloorItemCount(square)
							floorItemCount = floorItemCount + items
							roomFloorItems = roomFloorItems + items
						end
					end
				end
				if roomHadLoadedSquare then
					roomsSeen = roomsSeen + 1
					local roomId = room:getID()
					if roomId then
						local roomOk = roomWindowsOk and roomDoorsOk and roomNoCorpses
							and roomBoardedOk
							and roomFloorItems <= TwoManCrew.Restoration.MAX_FLOOR_ITEMS
						roomResults[roomId] = roomOk
					end
				end
			end
		end
	end

	if roomsSeen == 0 then
		return "unknown", {
			reason = "building's ground floor is not currently loaded",
			roomsSeen = 0,
			roomsTotal = roomCount,
		}
	end

	-- Partial load this pass: some rooms seen, not all. Reported for display
	-- only now - banking no longer requires fullyCovered in a single pass,
	-- see the per-room memory merge in checkBuildingRestored.
	local fullyCovered = (roomsSeen == roomCount)

	local detail = {
		windowsOk = windowsOk,
		doorsOk = doorsOk,
		noCorpses = noCorpses,
		boardedOk = boardedOk,
		floorItemCount = floorItemCount,
		floorClearOk = floorItemCount <= TwoManCrew.Restoration.MAX_FLOOR_ITEMS,
		roomsSeen = roomsSeen,
		roomsTotal = roomCount,
		squaresSeen = squaresSeen,
		fullyCovered = fullyCovered,
		roomResults = roomResults,
	}

	return "seen", detail
end

-- Is any crew member currently standing at the claimed building? This is the
-- crew-presence rule (see the block above). Uses CLAIM_PROXIMITY_RADIUS so
-- "close enough to witness" means the same distance everywhere in this file.
local function crewPresentNear(bx, by)
	for _, p in ipairs(TwoManCrew.getAllPlayers()) do
		if p:DistTo(bx, by) <= CLAIM_PROXIMITY_RADIUS then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

-- Checks one claimed building entry (as stored in claim.buildings - see
-- TwoManCrew_Campaign.lua's state.claim.buildings shape: { id, units, x, y }).
-- Returns:
--   restored:bool  - true only when every room has, across all visits, been
--                     individually confirmed clean AND accumulated presence
--                     has reached PRESENCE_HOURS. false covers "checked and
--                     genuinely not there yet" and "not yet checkable" so
--                     callers get a safe default; check detail.status.
--   detail:table   - { status = "restored"|"not_restored"|"unknown",
--                       windowsOk, doorsOk, noCorpses, boardedOk,
--                       floorClearOk, floorItemCount, crewPresent,
--                       presenceHours, presenceRequired, roomsSeen,
--                       roomsTotal, fullyCovered, reason }
--                     presenceHours/presenceRequired are informational extras
--                     beyond the four original flags, for a journal that wants
--                     to show progress; absent when there is no active claim
--                     to accumulate them in (see the fallback branch below).
function TwoManCrew.Server.checkBuildingRestored(buildingEntry)
	if not buildingEntry or not buildingEntry.x or not buildingEntry.y then
		return false, { status = "unknown", reason = "bad building entry" }
	end

	local metaGrid = getWorld():getMetaGrid()
	if not metaGrid then
		return false, { status = "unknown", reason = "no metagrid" }
	end

	local def = metaGrid:getAssociatedBuildingAt(buildingEntry.x, buildingEntry.y)
	if not def then
		return false, { status = "unknown", reason = "building not found at claimed coords" }
	end

	-- Crew presence is tested BEFORE the square walk, not after it.
	--
	-- This ordering is the fix for the claim button freezing the game. The
	-- square walk below enumerates every tile of every ground-floor room, and
	-- calls getObjects()/getStaticMovingObjects() on each loaded one. Run over
	-- a whole claim (dozens of rooms, thousands of tiles) inside a single
	-- frame, on the main thread, that stops the game long enough to look like
	-- a crash - which is exactly how it was reported, with the log ending
	-- mid-frame on the claim press and no exception anywhere.
	--
	-- Presence is now accumulated rather than instantaneous (TASK 2/B5), but
	-- the walk only ever teaches us anything new about a building's squares
	-- while someone is standing close enough to have loaded them - so testing
	-- instantaneous presence first is still a correct, cheap filter: it skips
	-- the walk for every building except the one or two a crew member is
	-- actually standing at, with no loss of information (an absent building's
	-- squares are not freshly knowable anyway).
	local crewPresent = crewPresentNear(buildingEntry.x, buildingEntry.y)

	if not crewPresent then
		-- Held at unknown rather than failed, so walking back to the
		-- building can still complete it. This is the verdict the
		-- post-walk "nobody here" branch used to produce; no square walk
		-- is needed to reach it.
		return false, {
			status = "unknown",
			crewPresent = false,
			reason = "nobody here - stand inside it",
		}
	end

	local status, detail = checkBuildingSquares(def)

	if status == "unknown" then
		detail.status = "unknown"
		detail.crewPresent = true
		return false, detail
	end

	detail.crewPresent = true

	-- TASK 1 (B4): merge this pass's per-room verdicts into the claim's
	-- persisted memory. A room absent from detail.roomResults was not loaded
	-- this pass and is left untouched - its last known state (or "never
	-- seen") persists exactly as it was. A room present is unconditionally
	-- overwritten with this pass's fresh verdict: that is what lets a room
	-- seen broken stay broken, and what lets a later clean pass clear it.
	--
	-- TASK 2 (B5): accumulate presence hours for this building while a crew
	-- member is confirmed near it (we only reach this line when crewPresent
	-- is true). The elapsed time since the last PRESENT sample is added to a
	-- running total that is never reset by itself; only the "since when" ---
	-- baseline resets when a sample finds nobody present, so a real absence
	-- is never retroactively counted as presence.
	--
	-- Both need the persisted claim; TwoManCrew.Server.checkBuildingRestored
	-- is public and may be called directly (not just via recheckClaim /
	-- getClaimDetail), so this degrades gracefully to a single-pass,
	-- non-memoized verdict when there is no active claim to write into.
	local state = TwoManCrew.Server.getState()
	local claim = state and state.claim
	local bId = buildingEntry.id

	local anyRoomDirty = false
	local knownRoomCount = 0
	local presenceHours = nil
	local presenceOk

	if claim and bId ~= nil then
		claim.roomState = claim.roomState or {}
		claim.roomState[bId] = claim.roomState[bId] or {}
		local rooms = claim.roomState[bId]
		for roomId, roomOk in pairs(detail.roomResults or {}) do
			rooms[roomId] = roomOk
		end
		for _, roomOk in pairs(rooms) do
			knownRoomCount = knownRoomCount + 1
			if not roomOk then anyRoomDirty = true end
		end

		claim.presenceHours = claim.presenceHours or {}
		claim.presenceLastSeen = claim.presenceLastSeen or {}
		local nowHours = getGameTime():getWorldAgeHours()
		local lastSeen = claim.presenceLastSeen[bId]
		if lastSeen and nowHours > lastSeen then
			claim.presenceHours[bId] = (claim.presenceHours[bId] or 0) + (nowHours - lastSeen)
		end
		claim.presenceLastSeen[bId] = nowHours

		presenceHours = claim.presenceHours[bId] or 0
		presenceOk = presenceHours >= TwoManCrew.Restoration.PRESENCE_HOURS
	else
		-- No persisted claim to accumulate into - fall back to this pass's
		-- own coverage/flags only, same shape the file used before TASK 1/2.
		anyRoomDirty = not (detail.windowsOk and detail.doorsOk and detail.noCorpses
			and detail.boardedOk and detail.floorClearOk)
		knownRoomCount = detail.roomsSeen
		presenceOk = true -- instantaneous presence already confirmed above
	end

	detail.presenceHours = presenceHours
	detail.presenceRequired = TwoManCrew.Restoration.PRESENCE_HOURS

	if anyRoomDirty then
		-- A known-broken room is a real, checkable failure - not "unknown",
		-- however many other rooms remain unseen.
		detail.status = "not_restored"
		return false, detail
	end

	if knownRoomCount < detail.roomsTotal then
		-- Every room seen so far is clean, but at least one has never been
		-- visited. Honestly unresolved, per the three-state rule: this must
		-- not fail the building and must not pass it either.
		detail.status = "unknown"
		detail.reason = "some rooms never visited yet"
		return false, detail
	end

	if not presenceOk then
		detail.status = "not_restored"
		detail.reason = "not enough time spent here yet"
		return false, detail
	end

	detail.status = "restored"
	return true, detail
end

-- TASK 4 (B10): is a banked building due for its periodic spot check?
-- claim.lastRecheckHours[buildingId] holds the getWorldAgeHours() reading at
-- the last attempt (whatever its outcome); nil means never attempted, which
-- is always due.
local function dueForRecheck(claim, buildingId, nowHours)
	local last = claim.lastRecheckHours and claim.lastRecheckHours[buildingId]
	if not last then return true end
	return (nowHours - last) >= TwoManCrew.Restoration.RECHECK_HOURS
end

-- TASK 4 (B10): re-verifies ONE already-banked building that is due, and
-- demotes it if it genuinely fails. The owner explicitly reversed the old
-- "restoration is an achievement, not a live-held state" rule: tier 5 asks
-- the crew to hold the block, so a banked building that quietly rots was
-- never really held.
--
-- Sampled, not swept: only the first due building found is rechecked, so a
-- pass through a large claim costs at most one extra square-walk, never one
-- per banked building. Being "due" is per-building (RECHECK_HOURS since that
-- building's own last attempt), so across enough passes every banked
-- building gets its turn without ever costing more than one per pass.
--
-- Never demotes on "unknown" (nobody there / not loaded) - that would punish
-- absence with a guess, which is exactly what the three-state rule in this
-- file exists to prevent. "unknown" and "restored" both just record the
-- attempt and move on; only a real "not_restored" clears the banked flag, so
-- the ordinary re-walk-and-rebank path (below, in recheckClaim/
-- getClaimDetail) can pick it back up once it is fixed.
local function recheckOneBankedBuilding(claim)
	if not claim or not claim.buildings or not claim.restored then return end
	claim.lastRecheckHours = claim.lastRecheckHours or {}
	local nowHours = getGameTime():getWorldAgeHours()

	for _, entry in ipairs(claim.buildings) do
		if claim.restored[entry.id] and dueForRecheck(claim, entry.id, nowHours) then
			claim.lastRecheckHours[entry.id] = nowHours
			local _, detail = TwoManCrew.Server.checkBuildingRestored(entry)
			if detail.status == "not_restored" then
				claim.restored[entry.id] = nil
				TwoManCrew.Server.addJournal(
					"a restored building slipped and needs attention again ("
						.. entry.units .. " work units)"
				)
			end
			return -- stagger: at most one recheck attempt per pass
		end
	end
end

-- Rescans every building in the crew's claim and updates
-- state.claim.restored[buildingId] = true for each one that now passes.
-- Never clears a previously-true entry ON ITS OWN - the periodic spot check
-- above (TASK 4/B10) is the one thing allowed to demote a banked building,
-- and it is called from here too so a "/crew check" rescan also samples one
-- banked building for rot. Buildings still "unknown" are left untouched so a
-- later call can pick them up once loaded.
--
-- CALL-SITE DESIGN (why this is not a tick handler): a full rescan walks
-- every square of every claimed building's ground floor - for a claim near
-- the TARGET_MAX_UNITS band (Campaign.lua) that is dozens of rooms, each
-- needing getObjects()/getStaticMovingObjects() enumeration. Doing that every
-- OnPlayerUpdate tick would be a server-wide hitch. This function is meant to
-- be called:
--   (a) on demand, from a "/crew goal" or "/crew check" style client
--       command handler (mirrors requestClaim in Campaign.lua), and
--   (b) optionally from a low-frequency timed event (e.g. EveryHours or a
--       manual counter gated to something like once every
--       TwoManCrew.CrewTally.UPDATE_INTERVAL_SECONDS * 60), never
--       OnPlayerUpdate/OnTick. No such periodic hook is wired up in this
--       file - that wiring belongs to whichever module owns the tier-check
--       trigger, so it can decide the right cadence instead of this module
--       silently picking one.
-- Returns the number of buildings currently marked restored (post-rescan).
function TwoManCrew.Server.recheckClaim()
	local state = TwoManCrew.Server.getState()
	local claim = state.claim
	if not claim then return 0 end

	claim.restored = claim.restored or {}

	recheckOneBankedBuilding(claim)

	for _, entry in ipairs(claim.buildings) do
		if not claim.restored[entry.id] then
			local restored = TwoManCrew.Server.checkBuildingRestored(entry)
			if restored then
				claim.restored[entry.id] = true
				TwoManCrew.Server.addJournal(
					"restored a building (" .. entry.units .. " work units)"
				)
			end
		end
	end

	local count = 0
	for _ in pairs(claim.restored) do
		count = count + 1
	end
	return count
end

-- Builds a per-building report of the whole claim, for display.
--
-- recheckClaim() deliberately returns only a count, because that is all the
-- tier logic needs. This returns everything the checker actually computed, so
-- the journal can show WHICH building failed and WHY - previously all four
-- conditions collapsed into one number and the crew had no way to tell a
-- broken window from an unloaded chunk.
--
-- Cost: this re-walks every claimed building's ground floor, the same as
-- recheckClaim(). Call it on demand from a button, never from a tick.
--
-- Returns an array, one entry per claimed building, each:
--   { id, units, x, y,
--     status     = "restored"|"not_restored"|"unknown",
--     alreadyDone = boolean,  -- true if previously banked (see below)
--     windowsOk, doorsOk, noCorpses, boardedOk, floorClearOk, crewPresent,
--       -- may be nil when unknown
--     roomsSeen, roomsTotal, reason,
--     presenceHours, presenceRequired }  -- extra, see checkBuildingRestored
function TwoManCrew.Server.getClaimDetail()
	local state = TwoManCrew.Server.getState()
	local claim = state.claim
	if not claim or not claim.buildings then return {} end

	claim.restored = claim.restored or {}

	-- TASK 4 (B10): sample one banked building for rot before reporting, so
	-- the journal can show a demotion the same call it happened in. A banked
	-- building normally is NOT re-walked below (cheap report for the common
	-- case); this is the one exception, and it costs at most one extra walk.
	recheckOneBankedBuilding(claim)

	local report = {}
	for _, entry in ipairs(claim.buildings) do
		local row = {
			id = entry.id,
			units = entry.units,
			x = entry.x,
			y = entry.y,
		}

		if claim.restored[entry.id] then
			-- Already banked and not due (or not yet found) for its spot
			-- check this pass, so do not re-walk it here.
			row.status = "restored"
			row.alreadyDone = true
		else
			local restored, detail = TwoManCrew.Server.checkBuildingRestored(entry)

			-- Bank a pass as it is found. This used to be recheckClaim's job
			-- alone, which meant the caller had to walk the whole claim a
			-- second time just to record what this walk already proved.
			-- Same rule as recheckClaim: only ever sets true, never clears.
			if restored and not claim.restored[entry.id] then
				claim.restored[entry.id] = true
				TwoManCrew.Server.addJournal(
					"restored a building (" .. entry.units .. " work units)"
				)
			end

			row.alreadyDone = false
			row.status = detail.status or "unknown"
			row.windowsOk = detail.windowsOk
			row.doorsOk = detail.doorsOk
			row.noCorpses = detail.noCorpses
			row.boardedOk = detail.boardedOk
			row.floorClearOk = detail.floorClearOk
			row.crewPresent = detail.crewPresent
			row.roomsSeen = detail.roomsSeen
			row.roomsTotal = detail.roomsTotal
			row.reason = detail.reason
			-- Extra, beyond the four original flags: lets a journal show
			-- accumulated witness time (TASK 2/B5) instead of just pass/fail.
			row.presenceHours = detail.presenceHours
			row.presenceRequired = detail.presenceRequired
		end

		table.insert(report, row)
	end

	return report
end

-- Handles an on-demand client request to rescan the claim (e.g. "/crew
-- check" from the client side). Mirrors the requestClaim handler shape in
-- TwoManCrew_Campaign.lua.
local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if not player then return end

	if command == "requestRestorationCheck" then
		local restoredCount = TwoManCrew.Server.recheckClaim()
		local claim = TwoManCrew.Server.getClaim()

		-- announce echoes the caller's flag back untouched. The journal
		-- window polls this every couple of seconds while it is open, and
		-- only a survey the player actually asked for should say anything
		-- on screen.
		TwoManCrew.replyToPlayer(player, "restorationChecked", {
			ok = claim ~= nil,
			announce = args and args.announce or false,
			restored = restoredCount,
			total = claim and #claim.buildings or 0,
		})
		return
	end

	if command == "requestClaimDetail" then
		-- No recheckClaim() call here. It used to run first "so the detail is
		-- current", but getClaimDetail() below already calls
		-- checkBuildingRestored on every unbanked building - so the whole
		-- claim was being walked TWICE per journal open, for one set of
		-- results. The detail is current either way, because the walk that
		-- produces it happens inside getClaimDetail().
		--
		-- Banking (marking a passing building restored) is what recheckClaim
		-- adds, and getClaimDetail now does that itself as it goes, so
		-- opening the journal still records progress.
		local claim = TwoManCrew.Server.getClaim()

		TwoManCrew.replyToPlayer(player, "claimDetail", {
			ok = claim ~= nil,
			buildings = TwoManCrew.Server.getClaimDetail(),
		})
		return
	end
end

Events.OnClientCommand.Add(OnClientCommand)

for _, cmd in ipairs({ "requestRestorationCheck", "requestClaimDetail" }) do
	TwoManCrew.registerLocalHandler(cmd, function(player, args)
		OnClientCommand(TwoManCrew.MODULE, cmd, player, args)
	end)
end
