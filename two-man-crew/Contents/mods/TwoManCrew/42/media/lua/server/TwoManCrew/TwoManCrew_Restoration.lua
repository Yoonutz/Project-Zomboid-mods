-- TwoManCrew_Restoration.lua (server)
--
-- Decides whether a claimed building counts as "restored", per the four
-- conditions in GOALS.md: ground-floor windows boarded/replaced, every
-- doorway has a working door, each room holds crew-built furniture, no
-- corpse remains. See the per-condition notes below for which of these are
-- real game-state checks and which fall back to a crew-declared claim.
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
-- IsoWindow: an intact window pane, possibly barricaded. isBarricaded()
-- (shared/Moveables/ISMoveableSpriteProps.lua:882) is the only verified
-- state check found for a window - no isBroken()/isDestroyed() was found on
-- IsoWindow in the searched source, so an un-barricaded IsoWindow is treated
-- as already fine (an intact pane, boarding optional) rather than guessed at
-- as broken glass. This is intentionally conservative: it can under-detect
-- a broken-but-not-yet-boarded window, never over-fail one.
-- IsoWindowFrame: the pane is gone outright, leaving a frame.
-- hasWindow() (client/DebugUIs/DebugContextMenu.lua:381) tells us whether a
-- replacement pane exists; if not, isBarricaded() still covers a boarded-over
-- frame as an acceptable restoration per GOALS.md ("boarded or replaced").
-- A frame with neither counts as an unrestored window and fails the square.
local function squareWindowsRestored(square)
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if obj then
			if instanceof(obj, "IsoWindowFrame") then
				if not obj:hasWindow() and not obj:isBarricaded() then
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

-- FELL BACK: crew-built furniture per room.
-- No isPlayerBuilt()/BUILT_BY marker or comparable ModData convention was
-- found anywhere in the installed Lua source for constructed IsoObjects
-- (searched server/BuildingObjects/*.lua, shared/Moveables/*.lua). Vanilla's
-- own build code does not tag what it places as player-made versus
-- map-spawned; the two are the same object type with no distinguishing
-- field. TwoManCrew's own build actions (none exist yet in this mod) would
-- have to stamp their own ModData key at construction time for this to
-- become a real check - out of scope for a checker-only module. Falls back
-- fully to the GOALS.md fallback: a crew-declared claim, confirmed only by
-- proximity (the claiming player must be standing inside the building).
-- Implemented as furnishedDeclared() below rather than a per-square scan.

-- ---------------------------------------------------------------------------
-- Building-level check
-- ---------------------------------------------------------------------------

-- Walks a building's ground floor (z = 0) rooms and evaluates the three real
-- checks (windows, doors, corpses). Returns:
--   status:  "restored" | "not_restored" | "unknown"
--   detail:  { windowsOk, doorsOk, noCorpses, roomsSeen, roomsTotal,
--              furnishedDeclared }
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

-- FELL BACK check, standalone: is any crew member currently standing inside
-- the claimed building? Used as the "confirmed by proximity" half of the
-- furniture fallback - without an isPlayerBuilt marker, the mod cannot tell
-- crew-built furniture from map-spawned furniture, so "furnished" degrades
-- to a proximity-witnessed claim the crew must be present to make.
local function crewPresentNear(bx, by)
	local players = IsoPlayer.getPlayers()
	if not players then return false end

	for i = 0, players:size() - 1 do
		local p = players:get(i)
		if p and p:DistTo(bx, by) <= CLAIM_PROXIMITY_RADIUS then
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
--   restored:bool  - true only when every checkable condition passed AND a
--                     crew member was present to stand in for the furniture
--                     fallback. false covers both "checked and failed" and
--                     "not yet checkable" so callers get a safe default;
--                     check detail.status for the real reason.
--   detail:table   - { status = "restored"|"not_restored"|"unknown",
--                       windowsOk, doorsOk, noCorpses, furnishedDeclared,
--                       roomsSeen, roomsTotal, fullyCovered }
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

	-- Furniture: fallback only. A crew member must currently be standing
	-- near the building for the claim to count at all - this is the
	-- "confirmed by proximity" half of the GOALS.md fallback text.
	local furnishedDeclared = crewPresentNear(buildingEntry.x, buildingEntry.y)
	detail.furnishedDeclared = furnishedDeclared

	if status == "candidate_restored" and furnishedDeclared then
		detail.status = "restored"
		return true, detail
	end

	if status == "candidate_restored" and not furnishedDeclared then
		-- Windows/doors/corpses all pass, but nobody was present to stand in
		-- for the furniture fallback - hold at unknown rather than failing a
		-- building that is otherwise done.
		detail.status = "unknown"
		detail.reason = "windows/doors/corpses passed but no crew present to confirm furnishing"
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

-- Handles an on-demand client request to rescan the claim (e.g. "/crew
-- check" from the client side). Mirrors the requestClaim handler shape in
-- TwoManCrew_Campaign.lua.
local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "requestRestorationCheck" then return end
	if not player then return end

	local restoredCount = TwoManCrew.Server.recheckClaim()
	local claim = TwoManCrew.Server.getClaim()

	sendServerCommand(player, TwoManCrew.MODULE, "restorationChecked", {
		ok = claim ~= nil,
		restored = restoredCount,
		total = claim and #claim.buildings or 0,
	})
end

Events.OnClientCommand.Add(OnClientCommand)
