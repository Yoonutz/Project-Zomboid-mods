-- TwoManCrew_Restoration.lua (server)
--
-- Decides whether a claimed building counts as "restored": ground-floor
-- windows boarded/replaced, every doorway has a working door, no corpse
-- remains, and a crew member present to witness it. The GOALS.md "crew-built
-- furniture per room" condition was dropped as unimplementable - see the
-- CREW PRESENCE block below for why, and for what replaced it.
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

require "TwoManCrew/TwoManCrew_Config"
require "TwoManCrew/TwoManCrew_CrewState"

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

-- CREW PRESENCE: a rule in its own right, not a fallback.
--
-- This used to stand in for "each room contains crew-built furniture". That
-- goal was dropped: the engine offers no way to tell crew-built furniture from
-- map-spawned furniture (no isPlayerBuilt marker exists anywhere in the
-- installed Lua source, and the Build 42 entity build path does not stamp
-- ModData - see ISBuildIsoEntity.lua, which never calls setModData).
--
-- Rather than delete the check along with the goal, the crew-presence half is
-- kept deliberately: a building counts as restored only while a crew member is
-- standing near it. Restoration is something the crew witnesses, not something
-- that happens off-screen. Implemented as crewPresentNear() below.

-- ---------------------------------------------------------------------------
-- Building-level check
-- ---------------------------------------------------------------------------

-- Walks a building's ground floor (z = 0) rooms and evaluates the three real
-- checks (windows, doors, corpses). Returns:
--   status:  "restored" | "not_restored" | "unknown"
--   detail:  { windowsOk, doorsOk, noCorpses, roomsSeen, roomsTotal,
--              squaresSeen, fullyCovered }
-- "unknown" means not enough of the building's ground floor is loaded to
-- trust a verdict either way - never guessed as pass or fail.
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
	local roomsSeen = 0
	local squaresSeen = 0

	for i = 0, roomCount - 1 do
		local room = rooms:get(i)
		if room then
			local x1, x2 = room:getX(), room:getX2()
			local y1, y2 = room:getY(), room:getY2()
			if x1 and x2 and y1 and y2 then
				local roomHadLoadedSquare = false
				for x = x1, x2 do
					for y = y1, y2 do
						local square = cell:getGridSquare(x, y, 0)
						if isLoaded(square) then
							roomHadLoadedSquare = true
							squaresSeen = squaresSeen + 1
							if not squareWindowsRestored(square) then
								windowsOk = false
							end
							if not squareDoorsRestored(square) then
								doorsOk = false
							end
							if squareHasCorpse(square) then
								noCorpses = false
							end
						end
					end
				end
				if roomHadLoadedSquare then
					roomsSeen = roomsSeen + 1
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

	-- Partial load: some rooms seen, not all. Still report what was found,
	-- but do not claim full coverage - callers can decide whether partial
	-- evidence is good enough (recheckClaim keeps it pending either way,
	-- since a hidden broken window in an unseen room would be missed).
	local fullyCovered = (roomsSeen == roomCount)

	local detail = {
		windowsOk = windowsOk,
		doorsOk = doorsOk,
		noCorpses = noCorpses,
		roomsSeen = roomsSeen,
		roomsTotal = roomCount,
		squaresSeen = squaresSeen,
		fullyCovered = fullyCovered,
	}

	if not fullyCovered then
		return "unknown", detail
	end

	if windowsOk and doorsOk and noCorpses then
		return "candidate_restored", detail
	end

	return "not_restored", detail
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
--   restored:bool  - true only when every condition passed AND a crew member
--                     was present. false covers both "checked and failed" and
--                     "not yet checkable" so callers get a safe default;
--                     check detail.status for the real reason.
--   detail:table   - { status = "restored"|"not_restored"|"unknown",
--                       windowsOk, doorsOk, noCorpses, crewPresent,
--                       roomsSeen, roomsTotal, fullyCovered, reason }
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

	local status, detail = checkBuildingSquares(def)

	if status == "unknown" then
		detail.status = "unknown"
		return false, detail
	end

	-- Crew presence: a building only counts while someone is there to see it.
	local crewPresent = crewPresentNear(buildingEntry.x, buildingEntry.y)
	detail.crewPresent = crewPresent

	if status == "candidate_restored" and crewPresent then
		detail.status = "restored"
		return true, detail
	end

	if status == "candidate_restored" and not crewPresent then
		-- Windows, doors and corpses all pass, but nobody is there. Hold at
		-- unknown rather than failing a building that is otherwise finished -
		-- walking back to it must be able to complete it.
		detail.status = "unknown"
		-- Short on purpose: the client renders this on the building's own row.
		detail.reason = "nobody here - stand inside it"
		return false, detail
	end

	detail.status = "not_restored"
	return false, detail
end

-- Rescans every building in the crew's claim and updates
-- state.claim.restored[buildingId] = true for each one that now passes.
-- Never clears a previously-true entry: once restored, a building stays
-- counted even if a later zombie wanders in and a corpse reappears -
-- GOALS.md's tier design counts restoration as an achievement, not a
-- live-held state (only tier 5's "hold the block" condition is about
-- persistence, and that is a separate nights-survived counter, not this
-- one). Buildings still "unknown" are left untouched so a later call can
-- pick them up once loaded.
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
--     windowsOk, doorsOk, noCorpses, crewPresent,  -- may be nil when unknown
--     roomsSeen, roomsTotal, reason }
function TwoManCrew.Server.getClaimDetail()
	local state = TwoManCrew.Server.getState()
	local claim = state.claim
	if not claim or not claim.buildings then return {} end

	claim.restored = claim.restored or {}

	local report = {}
	for _, entry in ipairs(claim.buildings) do
		local row = {
			id = entry.id,
			units = entry.units,
			x = entry.x,
			y = entry.y,
		}

		if claim.restored[entry.id] then
			-- Already banked. Restoration is an achievement, not a live-held
			-- state, so do not re-walk it and do not let a wandering corpse
			-- un-restore it - matching recheckClaim's contract.
			row.status = "restored"
			row.alreadyDone = true
		else
			local _, detail = TwoManCrew.Server.checkBuildingRestored(entry)
			row.alreadyDone = false
			row.status = detail.status or "unknown"
			row.windowsOk = detail.windowsOk
			row.doorsOk = detail.doorsOk
			row.noCorpses = detail.noCorpses
			row.crewPresent = detail.crewPresent
			row.roomsSeen = detail.roomsSeen
			row.roomsTotal = detail.roomsTotal
			row.reason = detail.reason
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

		TwoManCrew.replyToPlayer(player, "restorationChecked", {
			ok = claim ~= nil,
			restored = restoredCount,
			total = claim and #claim.buildings or 0,
		})
		return
	end

	if command == "requestClaimDetail" then
		-- Rescan first, so the detail shown is current rather than a snapshot
		-- of whenever the last tick ran.
		TwoManCrew.Server.recheckClaim()
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
