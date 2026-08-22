-- TwoManCrew_Tiers.lua (server)
-- Tracks the five building tiers and four livestock stages from GOALS.md
-- against the crew's claim, and announces each one exactly once.
--
-- Server-only. Reads TwoManCrew_CrewState (getState/addJournal) and the claim
-- shape from TwoManCrew_Campaign (state.claim.buildings / state.claim.restored)
-- via their public accessors only - never touches ModData directly.
--
-- Calls into TwoManCrew_Restoration defensively (TwoManCrew.Server.recheckClaim /
-- checkBuildingRestored), since that module is written separately and mod file
-- load order is not guaranteed - see the "if TwoManCrew.Server.X then" guards
-- below, the same pattern TwoManCrew_ShiftChange.lua and TwoManCrew_FellingBonus.lua
-- use for TwoManCrew_CrewState.
--
-- Public surface (stable, the UI module depends on this shape):
--   TwoManCrew.Server.getTierProgress() ->
--     {
--       buildingTier = number,       -- highest building tier reached, 0 if none
--       buildingTierName = string,   -- name of buildingTier, "None" if 0
--       nextBuildingTier = number,   -- next unreached building tier, nil if all 5 done
--       nextBuildingTierName = string, -- nil if all 5 done
--       buildingRemaining = string,  -- one-line human description of what's left, or nil
--       livestockStage = number,     -- highest livestock stage reached, 0 if none
--       livestockStageName = string, -- name of livestockStage, "None" if 0
--       nextLivestockStage = number, -- next unreached stage, nil if all 4 done
--       nextLivestockStageName = string, -- nil if all 4 done
--       livestockRemaining = string, -- one-line human description of what's left, or nil
--       holdNightsDone / holdNightsNeeded   -- tier 5 hold countdown, nil until
--                                            -- every building is restored
--       herdNightsDone / herdNightsNeeded   -- L4 hold countdown, nil until a
--                                            -- baby animal is present
--       censusAnimals / censusBabies / censusHutches / censusTroughs
--                                            -- what the last census actually
--                                            -- saw, nil before it first runs
--     }
--
-- ModData addition (under the existing TwoManCrew.Server.getState() table):
--   state.tiers = {
--     buildings = { [1]=bool, [2]=bool, [3]=bool, [4]=bool, [5]=bool },
--     livestock = { [1]=bool, [2]=bool, [3]=bool, [4]=bool },
--   }
-- Both sub-tables are sparse-safe: a missing key reads as "not reached" (nil
-- is falsy), so a save from before this module existed schema-fills cleanly.
--
-- IDEMPOTENCY: every tier check reads its own persisted flag FIRST. An
-- already-true tier is never re-evaluated, so re-running the whole pass every
-- ten minutes can never re-announce or double-count. A tier flips false->true
-- exactly once per save; the flip itself is what gates the announcement and
-- the journal write, so there is no separate "already announced" bookkeeping
-- to fall out of sync with the flag.
--
-- Verified APIs (installed Build 42.20.3):
--   Events.EveryTenMinutes.Add(fn)          server/Farming/SFarmingSystem.lua:586,
--                                            server/TwoManCrew/TwoManCrew_ShiftChange.lua:94
--   HaloTextHelper.addText(player, text) called server-side directly -
--                                            server/TwoManCrew/TwoManCrew_FellingBonus.lua:28-29,
--                                            server/TwoManCrew/TwoManCrew_ShiftChange.lua:70-71
--                                            (in-mod precedent per the task brief; vanilla
--                                            server/XpSystem/XpUpdate.lua:197,286 confirms
--                                            HaloTextHelper is reachable server-side at all,
--                                            using addTextWithArrow/addGoodText there instead)
--   getGameTime():getNightsSurvived()        server/radio/ISWeatherChannel.lua:132
--   getGameTime():getWorldAgeHours()         server/Farming/SFarmingSystem.lua:258
--   instanceof(obj, "IsoAnimal")             client/DebugUIs/DebugContextMenu.lua:619
--   animal:isBaby()                          client/ISUI/Animal/ISAnimalUI.lua:161
--   TwoManCrew.getAllPlayers()               shared/TwoManCrew/TwoManCrew_Config.lua
--                                            (wraps getOnlinePlayers on a server and
--                                            getSpecificPlayer otherwise - see that
--                                            function's comment for the vanilla citations;
--                                            IsoPlayer.getPlayers() is NOT used, it cannot
--                                            see remote players)
--   player:DistTo(x, y)                      client/Farming/CFarmingSystem.lua:47
--   SFeedingTroughSystem.instance            server/FeedingTrough/BuildingObjects/ISFeedingTrough.lua:8
--                                            (derives SGlobalObjectSystem -
--                                            server/FeedingTrough/SFeedingTroughSystem.lua:5)
--   system:getLuaObjectCount()               server/Map/SGlobalObjectSystem.lua:40-42
--   system:getLuaObjectByIndex(i)            server/Map/SGlobalObjectSystem.lua:44-46
--                                            (returns globalObject:getModData())
--   luaObject.x / .y / .z on that ModData    server/Map/SGlobalObject.lua:75-77
--                                            (SGlobalObject:new stamps them from
--                                            globalObject:getX/getY/getZ; the same
--                                            fields are read back at
--                                            server/Map/SGlobalObjectSystem.lua:52)
--   getCell():getGridSquare(x, y, z)         server/Animal/ISPickDungCursor.lua:104
--   square:getMovingObjects()                server/BuildingObjects/ISHutch.lua:103
--   square:getObjects()                      server/Map/MapObjects/MOHutch.lua:42
--   instanceof(obj, "IsoHutch")              server/Map/MapObjects/MOHutch.lua:44
--   hutch:getAnimalInside()                  client/ISUI/Hutch/ISHutchMenu.lua:57,
--                                            client/ISUI/Animal/ISDesignationAnimalZoneUI.lua:286
--   obj.water on a trough ModData             server/FeedingTrough/SFeedingTroughGlobalObject.lua:17-19
--                                            (a NUMBER - the stocked water level)
--   obj.feedAmount on a trough ModData        server/FeedingTrough/SFeedingTroughGlobalObject.lua:38-40,
--                                            keys declared server/FeedingTrough/SFeedingTroughSystem.lua:19,22
--                                            (a TABLE keyed by feed type, NOT a number -
--                                            checking it as a number is the easy mistake here)
--
-- UNVERIFIED SERVER-SIDE, cited only in client UI (ISAnimalUI.lua:244), used
-- pcall'd below the same as isWild/isDead:
--   animal:getMother()
--   animal:isExistInTheWorld()
--
-- UNVERIFIED, fallback used per GOALS.md's own stated fallback clause:
-- no server-side precedent was found in the installed vanilla source for
-- enumerating every animal within an area or reading an animal zone's
-- contents (square:getMovingObjects() exists on IsoGridSquare but every
-- call site found - client/DebugUIs/DebugContextMenu.lua:535,909 - is
-- client-side debug tooling, never a server file, so it is not treated as a
-- confirmed server-safe pattern here). L2/L4 therefore fall back to counting
-- IsoAnimal instances standing within TwoManCrew.CREW_RADIUS of either crew
-- member at evaluation time - weaker than a true area census (an animal that
-- wanders off between EveryTenMinutes passes can un-count itself), but still
-- observed game state, not a self-report. This is exactly the fallback GOALS.md
-- names for L2/L4.
--
-- L1 and L3 are now REAL checks, not tallies, but they are real in two
-- different ways and the difference is load-bearing:
--
--   L1 (trough) reads SFeedingTroughSystem, a server-side global object system.
--   Global object state is map-wide and persistent, so a trough is detectable
--   anywhere on the claim whether or not the ground is loaded.
--
--   L3 (hutch) has no such system. The whole installed tree was searched and
--   no hutch global object system exists - vanilla itself finds hutches by
--   scanning squares (server/Map/MapObjects/MOHutch.lua:42-46). So a hutch is
--   findable only on LOADED ground, which means L3 can only be confirmed while
--   a crew member is near it. Do not "improve" this into a map-wide scan;
--   there is no API for one.
--
-- Both checks locate structures by comparing their world position against the
-- claim's bounding box, which is built from the per-building footprints
-- recorded at claim time. A claim whose buildings carry no footprint cannot
-- prove location, so those checks report "cannot tell" rather than "absent".

require "TwoManCrew/TwoManCrew_Config"

if isClient() then return end

TwoManCrew.Server = TwoManCrew.Server or {}

local BUILDING_TIER_NAMES = {
	[1] = "One House",
	[2] = "The Row",
	[3] = "Half the Block",
	[4] = "Every Door and Window",
	[5] = "The Rebuilt Town",
}

local LIVESTOCK_STAGE_NAMES = {
	[1] = "The Trough",
	[2] = "First Stock",
	[3] = "The Hutch",
	[4] = "The Herd",
}

-- Tier 5's extra "hold the block" requirement, and L4's "full season" proxy.
-- A real season length is not exposed as a single verified constant, so both
-- reuse the same nights-survived stretch already verified for hold-the-block
-- (getGameTime():getNightsSurvived(), server/radio/ISWeatherChannel.lua:132).
-- This is a deliberate, stated simplification: GOALS.md ties L4 to "a full
-- season" but supplies no verified in-game season-length getter, so the
-- module measures a fixed night count instead of guessing at one.
local TIER5_HOLD_NIGHTS = 7
local L4_HERD_HOLD_NIGHTS = 30

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

local function ensureTierSchema(state)
	state.tiers = state.tiers or {}
	state.tiers.buildings = state.tiers.buildings or {}
	state.tiers.livestock = state.tiers.livestock or {}
	-- Tracks the world-age-hours at which the block first had zero unrestored
	-- buildings, so the tier 5 "hold" window has a fixed start rather than
	-- restarting every time this function runs. nil until that moment.
	state.tiers.allRestoredSinceHours = state.tiers.allRestoredSinceHours or nil
	-- Same idea for the livestock L4 hold window.
	state.tiers.herdSinceHours = state.tiers.herdSinceHours or nil
	return state.tiers
end

-- ---------------------------------------------------------------------------
-- Claim geography
-- ---------------------------------------------------------------------------

-- Bounding box of the whole claim, from the per-building footprints recorded
-- at claim time (TwoManCrew_Campaign.lua). Used to ask "is this structure on
-- our block?" without needing the ground loaded.
--
-- Returns nil when no claim exists or no building carries a footprint - which
-- is the case for claims made before footprints were recorded. Callers must
-- treat nil as "cannot judge location" rather than as "not on the block".
local function claimBounds(claim)
	if not claim or not claim.buildings then return nil end

	local x1, y1, x2, y2
	for _, entry in ipairs(claim.buildings) do
		if entry.x1 and entry.y1 and entry.x2 and entry.y2 then
			if not x1 or entry.x1 < x1 then x1 = entry.x1 end
			if not y1 or entry.y1 < y1 then y1 = entry.y1 end
			if not x2 or entry.x2 > x2 then x2 = entry.x2 end
			if not y2 or entry.y2 > y2 then y2 = entry.y2 end
		end
	end

	if not x1 then return nil end

	-- Pens and hutches sit beside the buildings, not inside them, so the claim
	-- box is widened before asking whether a structure belongs to this crew.
	local margin = 20
	return x1 - margin, y1 - margin, x2 + margin, y2 + margin
end

-- Counts feeding troughs standing on (or just beside) the claimed block.
--
-- Reads SFeedingTroughSystem, a server-side global object system
-- (server/FeedingTrough/SFeedingTroughSystem.lua:5 derives SGlobalObjectSystem;
-- the singleton is used at
-- server/FeedingTrough/BuildingObjects/ISFeedingTrough.lua:8), enumerated via
-- getLuaObjectCount/getLuaObjectByIndex (server/Map/SGlobalObjectSystem.lua:40-46).
-- Global object state is map-wide and persistent, so unlike a square scan this
-- sees troughs nobody is standing near.
--
-- getLuaObjectByIndex returns globalObject:getModData()
-- (server/Map/SGlobalObjectSystem.lua:45), and SGlobalObject:new stamps x/y/z
-- onto that very table from globalObject:getX/getY/getZ
-- (server/Map/SGlobalObject.lua:75-77). Vanilla reads the same fields back at
-- server/Map/SGlobalObjectSystem.lua:52, so obj.x / obj.y are the verified
-- field names, not an assumption.
--
-- Returns nil when the system is unavailable or the claim has no footprints,
-- so the caller can tell "none built" from "cannot tell".
local function countTroughsOnClaim(claim)
	if not SFeedingTroughSystem or not SFeedingTroughSystem.instance then
		return nil
	end

	local x1, y1, x2, y2 = claimBounds(claim)
	if not x1 then return nil end

	local system = SFeedingTroughSystem.instance
	local ok, count = pcall(function()
		local total = 0
		for i = 1, system:getLuaObjectCount() do
			local obj = system:getLuaObjectByIndex(i)
			if obj and obj.x and obj.y then
				if obj.x >= x1 and obj.x <= x2 and obj.y >= y1 and obj.y <= y2 then
					total = total + 1
				end
			end
		end
		return total
	end)

	if not ok then return nil end
	return count
end

-- Counts feeding troughs on the claim that are actually STOCKED - water above
-- zero, or at least one feed type loaded. A trough that was built once and
-- never filled should not satisfy "The Trough" forever on a single carpentry
-- act.
--
-- Deliberately a SEPARATE count from countTroughsOnClaim rather than that
-- function filtered in place: L2 ("First Stock") needs "a trough exists" and
-- L1 ("The Trough") needs "a trough is stocked", and those are different
-- claims about the same object. Collapsing them into one count would make
-- whichever caller runs second silently inherit the other's meaning.
--
-- Reuses the same enumeration and bounding-box test as countTroughsOnClaim -
-- same system, same claim geometry - so this is not a second walk of the
-- object list's logic, only an extra stocked test per matching object.
--
-- obj.water is a NUMBER; obj.feedAmount is a TABLE keyed by feed type, NOT a
-- number - see the file header citations. "Stocked" means the table has at
-- least one entry, not that it is truthy or non-zero.
--
-- The stocked test is pcall'd on its own, same defensive shape as isWild /
-- isDead above: an unreadable trough counts as NOT stocked, the strict
-- reading, so a broken read can never hand out a free pass.
--
-- Returns nil under the same conditions as countTroughsOnClaim (system
-- unavailable, or the claim has no footprints).
local function countStockedTroughsOnClaim(claim)
	if not SFeedingTroughSystem or not SFeedingTroughSystem.instance then
		return nil
	end

	local x1, y1, x2, y2 = claimBounds(claim)
	if not x1 then return nil end

	local system = SFeedingTroughSystem.instance
	local ok, count = pcall(function()
		local total = 0
		for i = 1, system:getLuaObjectCount() do
			local obj = system:getLuaObjectByIndex(i)
			if obj and obj.x and obj.y then
				if obj.x >= x1 and obj.x <= x2 and obj.y >= y1 and obj.y <= y2 then
					local okStocked, stocked = pcall(function()
						if obj.water and obj.water > 0 then return true end
						if type(obj.feedAmount) == "table" then
							for _ in pairs(obj.feedAmount) do
								return true
							end
						end
						return false
					end)
					if okStocked and stocked then
						total = total + 1
					end
				end
			end
		end
		return total
	end)

	if not ok then return nil end
	return count
end

-- ---------------------------------------------------------------------------
-- Livestock counting (fallback: proximity census, see file header)
-- ---------------------------------------------------------------------------

-- Counts living animals, babies, and occupied hutches near online crew.
--
-- Two separate engine limits are at work here, and both are deliberate:
--
--   Animals: IsoAnimal instances live on IsoGridSquare, so only loaded ground
--   can be counted. This is the fallback census GOALS.md allows.
--
--   Hutches: IsoHutch has NO global object system - unlike IsoFeedingTrough,
--   which does (SFeedingTroughSystem). The whole installed source was searched
--   and no hutch system exists; vanilla itself finds hutches by scanning
--   squares (server/Map/MapObjects/MOHutch.lua:42-46). So a hutch is findable
--   only on a loaded square. Do not "improve" this into a map-wide scan; there
--   is no API for one. L3 is therefore confirmable only while a crew member is
--   near it.
--
-- This sweeps the squares AROUND each player rather than only the exact square
-- the player stands on. The original read player:getSquare() alone, which meant
-- an animal one tile away was invisible.
--
-- Performance: (2*radius+1)^2 squares per player - 625 each at CREW_RADIUS 12.
-- It runs on the ten-minute tier tick only. Do not call it per frame.
--
-- Returns total, babies, occupiedHutches.
local function censusNearbyAnimals()
	local cell = getCell()
	local seen = {}
	local seenHutch = {}
	local total, babies, occupiedHutches = 0, 0, 0

	local radius = TwoManCrew.CREW_RADIUS

	for _, player in ipairs(TwoManCrew.getAllPlayers()) do
		local px, py = player:getX(), player:getY()
		local pz = player:getZ() or 0
		for dx = -radius, radius do
			for dy = -radius, radius do
				local square = cell and cell:getGridSquare(px + dx, py + dy, pz)
				if square then
					local movers = square:getMovingObjects()
					if movers then
						for j = 0, movers:size() - 1 do
							local obj = movers:get(j)
							if obj and instanceof(obj, "IsoAnimal") and not seen[obj] then
								seen[obj] = true
								-- L1 EXPLOIT FIX: a WILD animal is not stock.
								-- This loop used to count every IsoAnimal it saw,
								-- so a wild rabbit or deer wandering within
								-- CREW_RADIUS satisfied "First Stock" and fed
								-- "The Herd" with no husbandry at all. Playtested
								-- 0.10.6: the livestock track completed itself.
								--
								-- isWild() is verified present but only ever
								-- called in client UI (ISAnimalContextMenu.lua:153,
								-- 166, 307, 1171), never server-side in the shipped
								-- source. pcall keeps a missing method from taking
								-- the whole tier pass down with it, and an
								-- unreadable flag is treated as WILD - the strict
								-- reading, so a broken check cannot hand out a free
								-- pass. This is the same defensive shape the file
								-- already uses for SFeedingTroughSystem.
								local okWild, wild = pcall(function() return obj:isWild() end)
								if okWild and wild ~= true then
									total = total + 1
									if obj:isBaby() then
										-- L4 EXPLOIT FIX: a baby seen near the crew used to
										-- count as evidence of breeding on its own, but the
										-- mod's own trap code spawns juvenile animals
										-- directly (server/Traps/STrapGlobalObject.lua:207-236),
										-- so a crew could trap a juvenile, release it by the
										-- pen, and satisfy "The Herd" with no breeding at all.
										--
										-- getMother() and isExistInTheWorld() are pcall'd like
										-- every other animal getter here - see the file header,
										-- server-side use is unproven.
										--
										-- INVERTED strictness, on purpose - do not "fix" this
										-- to match isWild/isDead above. Several species set
										-- needMom = false in their own definitions (chick,
										-- mousepup, raccoonkit, ratbaby, turkeypoult), so a
										-- mother link is meaningless for them by design. This
										-- file has no verified way to read an IsoAnimal's
										-- species back off the object, so those species cannot
										-- be told apart from a genuinely unreadable getMother()
										-- call. Treating "unreadable or nil" as a FAILURE would
										-- make the herd stage impossible for exactly the
										-- species most likely to be farmed - a false failure
										-- here is worse than the exploit it closes, because it
										-- makes a campaign stage unwinnable rather than merely
										-- easy. So unreadable-or-nil is PERMISSIVE: it falls
										-- back to the old isBaby()-only acceptance instead of
										-- rejecting the baby.
										local okMother, mother = pcall(function() return obj:getMother() end)
										if not okMother or mother == nil then
											babies = babies + 1
										else
											local okExist, exists = pcall(function() return mother:isExistInTheWorld() end)
											if okExist and exists == true then
												babies = babies + 1
											end
											-- else: a real mother reference exists but could not
											-- be confirmed alive in world - not counted, the
											-- strict reading, same as everywhere else in this
											-- file except the permissive fallback above.
										end
									end
								end
							end
						end
					end

					local objects = square:getObjects()
					if objects then
						for j = 0, objects:size() - 1 do
							local obj = objects:get(j)
							if obj and instanceof(obj, "IsoHutch") and not seenHutch[obj] then
								seenHutch[obj] = true
								-- L3 EXPLOIT FIX: occupied must mean LIVING.
								-- size() > 0 counted a hutch holding a dead or
								-- dying animal, so a crew could stuff anything in
								-- moments before the check and let it die after.
								--
								-- isDead() has a real server-side precedent
								-- (server/Traps/STrapGlobalObject.lua:238), unlike
								-- most animal getters, which are client-only. It is
								-- still pcall'd: this runs inside the tier pass, and
								-- one missing method must not stop the whole
								-- campaign from scoring.
								local inside = obj:getAnimalInside()
								if inside and inside:size() > 0 then
									local living = false
									for k = 0, inside:size() - 1 do
										local animal = inside:get(k)
										if animal then
											local okDead, dead = pcall(function() return animal:isDead() end)
											-- Unreadable is treated as NOT living, matching
											-- the strict reading used for isWild above.
											if okDead and dead ~= true then
												living = true
											end
										end
									end
									if living then
										occupiedHutches = occupiedHutches + 1
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return total, babies, occupiedHutches
end

-- ---------------------------------------------------------------------------
-- Building tier evaluation
-- ---------------------------------------------------------------------------

-- Returns the current restored-building count, preferring a live recheck via
-- the Restoration module (may not be loaded yet - see file header), falling
-- back to the claim's own stored restored-count.
local function getRestoredCount()
	if TwoManCrew.Server.recheckClaim then
		local ok, count = pcall(TwoManCrew.Server.recheckClaim)
		if ok and type(count) == "number" then
			return count
		end
	end

	local claim = TwoManCrew.Server.getClaim and TwoManCrew.Server.getClaim()
	if not claim or not claim.restored then return 0 end

	local count = 0
	for _ in pairs(claim.restored) do
		count = count + 1
	end
	return count
end

-- Two buildings are adjacent when their footprints touch or overlap once each
-- is expanded by ADJACENCY_GAP tiles. A street-facing row has gaps of a few
-- tiles between structures, so exact edge contact would almost never fire.
local ADJACENCY_GAP = 3

-- Footprints are recorded at claim time (TwoManCrew_Campaign.lua). Claims made
-- before that existed have no bounds; those buildings simply cannot prove
-- adjacency, which keeps tier 2 honest rather than guessing from centre points.
local function isAdjacent(a, b)
	if not a or not b then return false end
	if not a.x1 or not b.x1 then return false end

	local ax1, ay1 = a.x1 - ADJACENCY_GAP, a.y1 - ADJACENCY_GAP
	local ax2, ay2 = a.x2 + ADJACENCY_GAP, a.y2 + ADJACENCY_GAP

	return ax1 <= b.x2 and ax2 >= b.x1 and ay1 <= b.y2 and ay2 >= b.y1
end

-- Largest group of mutually-reachable restored buildings, where "reachable"
-- means linked by a chain of adjacent neighbours. A row of three houses in a
-- line counts even though the end houses do not touch each other.
--
-- Plain flood fill over the restored set. Claims are dozens of buildings at
-- most, so the O(n^2) neighbour scan is not worth optimising.
local function largestAdjacentGroup(claim)
	if not claim or not claim.buildings then return 0 end
	claim.restored = claim.restored or {}

	local restored = {}
	for _, entry in ipairs(claim.buildings) do
		if claim.restored[entry.id] then
			table.insert(restored, entry)
		end
	end
	if #restored == 0 then return 0 end

	local seen = {}
	local best = 0

	for i = 1, #restored do
		if not seen[i] then
			local stack = { i }
			seen[i] = true
			local size = 0

			while #stack > 0 do
				local current = table.remove(stack)
				size = size + 1
				for j = 1, #restored do
					if not seen[j] and isAdjacent(restored[current], restored[j]) then
						seen[j] = true
						table.insert(stack, j)
					end
				end
			end

			if size > best then best = size end
		end
	end

	return best
end

-- Tier conditions. Each returns true/false given the claim and the restored
-- count. Tier 2 is a genuine adjacency test over the footprints recorded at
-- claim time. Tiers 3 and 4 were renamed rather than faked: identifying "the
-- large public building" needs a building category the MetaGrid does not
-- expose, and there is no block-boundary perimeter sweep in the engine's Lua
-- API, so both now ask for something this module can actually verify.
local function evaluateBuildingTier(tier, claim, restoredCount, tiersState)
	if not claim or not claim.buildings then return false end
	local totalBuildings = #claim.buildings

	if tier == 1 then
		-- Real check: at least one building restored.
		return restoredCount >= 1
	elseif tier == 2 then
		-- Real check: three restored buildings that form a connected run,
		-- using footprints captured at claim time. Previously this counted
		-- any three restored buildings anywhere on the block, which made
		-- "The Row" a lie.
		return largestAdjacentGroup(claim) >= 3
	elseif tier == 3 then
		-- Renamed to "Half the Block": this tests what it can actually
		-- verify. Identifying "the large public building" needs a building
		-- category the MetaGrid does not expose, so rather than keep a goal
		-- that silently meant something else, the tier now honestly asks for
		-- half the claim restored.
		local half = math.ceil(totalBuildings / 2)
		return totalBuildings > 0 and restoredCount >= half
	elseif tier == 4 then
		-- Renamed to "Every Door and Window": all buildings restored, which
		-- by definition means every ground-floor window is boarded or
		-- replaced and every doorway has a door. That is as close to "the
		-- perimeter is sealed" as this codebase can verify - there is no
		-- block-boundary sweep in the engine's Lua API.
		return totalBuildings > 0 and restoredCount >= totalBuildings
	elseif tier == 5 then
		if totalBuildings == 0 or restoredCount < totalBuildings then
			tiersState.allRestoredSinceHours = nil
			return false
		end
		local nowHours = getGameTime():getWorldAgeHours()
		if not tiersState.allRestoredSinceHours then
			tiersState.allRestoredSinceHours = nowHours
		end
		local nightsSurvived = getGameTime():getNightsSurvived()
		-- Held stretch: verified via getGameTime():getNightsSurvived() -
		-- server/radio/ISWeatherChannel.lua:132. Compared against the world
		-- age at which restoration completed rather than nights survived at
		-- that moment (no verified "nights survived at timestamp X" getter),
		-- so this approximates "held since" as elapsed hours since
		-- completion, converted to a night-equivalent via a fixed 24h/night.
		local heldHours = nowHours - tiersState.allRestoredSinceHours

		return heldHours >= (TIER5_HOLD_NIGHTS * 24) and nightsSurvived > 0
	end

	return false
end

local function evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies, claim, occupiedHutches)
	if stage == 1 then
		-- Real check: a feeding trough standing on the claimed block, read
		-- from the server-side global object system so it works whether or
		-- not anyone is nearby.
		--
		-- Deliberately does NOT verify the enclosure is fenced - no verified
		-- enclosure test exists in the engine's Lua surface. The stage
		-- description says so rather than implying more than is checked.
		--
		-- L1 EXPLOIT FIX: a trough used to satisfy this stage the instant it
		-- was built - one carpentry act, satisfied forever, even if it sat
		-- empty the whole campaign. Gated on REQUIRE_STOCKED_TROUGH so the
		-- config can still fall back to the old "exists" reading if the
		-- stocked check ever proves too strict in play.
		if TwoManCrew.Livestock.REQUIRE_STOCKED_TROUGH then
			local stocked = countStockedTroughsOnClaim(claim)
			if stocked ~= nil then
				return stocked >= 1
			end
		else
			local troughs = countTroughsOnClaim(claim)
			if troughs ~= nil then
				return troughs >= 1
			end
		end

		-- Could not read the trough system, or the claim predates footprints.
		-- Fall back to the old tally rather than failing outright. Note the
		-- deliberate absence of "return animalTotal >= 1": reaching this stage
		-- by standing near a wild animal was the bug being fixed.
		local tally = TwoManCrew.Server.getTally and TwoManCrew.Server.getTally()
		if tally and tally.pensBuilt and tally.pensBuilt > 0 then return true end
		return false
	elseif stage == 2 then
		-- Real-ish check (fallback census, see file header): at least one
		-- living animal currently seen near the crew.
		if animalTotal < 1 then return false end

		-- L2 EXPLOIT FIX: an animal merely wandering near the crew used to
		-- satisfy "First Stock" on its own, tamed or not - even with the wild
		-- filter in countNearbyAnimals, a tame animal that just wandered by
		-- still passed. Requiring a trough too proves the crew built the pen
		-- first. countTroughsOnClaim reads the map-wide global object system
		-- (see file header), not loaded ground, so this adds no new
		-- chunk-loading dependency to the census's existing three-state
		-- contract - it is evaluated independently of animalTotal.
		--
		-- Unreadable (nil) is treated as NOT satisfied here, the same strict
		-- reading used for isWild/isDead above: this is a brand-new
		-- requirement being added, not a replacement for an existing check,
		-- so there is no old fallback for it to defer to.
		if TwoManCrew.Livestock.REQUIRE_TROUGH_FOR_STOCK then
			local troughs = countTroughsOnClaim(claim)
			if not troughs or troughs < 1 then return false end
		end

		return true
	elseif stage == 3 then
		-- Real check: a hutch with at least one animal inside it. Only
		-- confirmable while a crew member is near the hutch - IsoHutch has no
		-- global object system, so it cannot be found on unloaded ground.
		if occupiedHutches and occupiedHutches >= 1 then return true end

		-- Fallback only if some other feature ever populates the tally. The
		-- old "two animals nearby" proxy is deliberately gone: two wild
		-- rabbits used to reach this stage.
		local tally = TwoManCrew.Server.getTally and TwoManCrew.Server.getTally()
		if tally and tally.hutchesBuilt and tally.hutchesBuilt > 0 then return true end
		return false
	elseif stage == 4 then
		-- Real check within the stated fallback: a baby animal currently
		-- seen near the crew is direct evidence of breeding (isBaby(),
		-- verified client/ISUI/Animal/ISAnimalUI.lua:161), held for a
		-- season-equivalent stretch so a single passing birth doesn't count.
		if animalBabies < 1 then
			tiersState.herdSinceHours = nil
			return false
		end
		local nowHours = getGameTime():getWorldAgeHours()
		if not tiersState.herdSinceHours then
			tiersState.herdSinceHours = nowHours
		end
		local heldHours = nowHours - tiersState.herdSinceHours
		return heldHours >= (L4_HERD_HOLD_NIGHTS * 24)
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Announcement
-- ---------------------------------------------------------------------------

local function announceTier(text, journalText)
	for _, player in ipairs(TwoManCrew.getAllPlayers()) do
		HaloTextHelper.addText(player, text)
	end

	if TwoManCrew.Server.addJournal then
		-- No specific player attribution makes sense for a crew-wide
		-- milestone; addJournal accepts a nil player and falls back to
		-- "Unknown" (TwoManCrew_CrewState.lua:95), which reads fine for a
		-- tier-completion entry that belongs to the whole crew.
		TwoManCrew.Server.addJournal(journalText, nil)
	end
end

-- ---------------------------------------------------------------------------
-- Main evaluation pass
-- ---------------------------------------------------------------------------

-- TEMPORARY INSTRUMENTATION (0.4.3, 2026-08-22)
--
-- The player reports occasional frame spikes. This pass runs on
-- EveryTenMinutes, which at default speed is roughly every 25 real seconds, and
-- it scans a 25x25 square block per player plus a building recheck. That is the
-- shape of an intermittent spike, but shape is not evidence.
--
-- These prints report the real cost per pass. Read them with `npm run diagnose`
-- or by grepping the log for TMC_PERF, then DELETE this instrumentation once the
-- number is known - it is a measurement, not a feature.
-- H1 PROBE - instrumentation, not a rule. DELETE THIS once the log answers it.
--
-- THE QUESTION: tier 5 asks the crew to HOLD the block, but the hold check only
-- measures elapsed time. A crew that boards itself into a basement for seven
-- nights passes exactly like a crew defending a street. The intended fix is to
-- require zombie kills during the hold window - but getZombieKills() appears in
-- ZERO server-side files in the shipped source. Only two client UI files call it
-- (client/ISUI/PlayerStats/ISPlayerStatsUI.lua:57 and
-- client/XpSystem/ISUI/ISCharacterScreen.lua:228), so whether it reads at all
-- from server Lua is unknown.
--
-- Reading source cannot settle that; only a running game can. This is the repo's
-- own instrument-first rule, and it is exactly what settled the same question
-- about pcall.
--
-- WHAT TO DO: load a session, then grep the log for TMC_PROBE.
--   a number  -> the counter reads server-side; the kill-based hold can ship
--   nil / ERR -> it does not; fall back to isOutside(), which IS proven
--                server-side (SadisticMusicDirector.lua:64) but is weaker,
--                since standing in a walled yard would satisfy it
--
-- Fires once per session rather than every pass: the answer never changes
-- within a session, and a line every ten minutes is log spam, not evidence.
local probeDone = false

local function probeZombieKills()
	if probeDone then return end
	probeDone = true
	for _, p in ipairs(TwoManCrew.getAllPlayers()) do
		local ok, kills = pcall(function() return p:getZombieKills() end)
		print("TMC_PROBE zombieKills readable=" .. tostring(ok)
			.. " value=" .. tostring(ok and kills or "ERR"))
	end
end

local function evaluateTiers()
	local perfStart = getTimestampMs()
	probeZombieKills()
	local function perfDone(where)
		print("TMC_PERF evaluateTiers ms=" .. (getTimestampMs() - perfStart) .. " exit=" .. where)
	end
	if not TwoManCrew.Server.hasClaim or not TwoManCrew.Server.hasClaim() then
		perfDone("no-claim")
		return
	end

	local state = TwoManCrew.Server.getState()
	local tiersState = ensureTierSchema(state)
	local claim = TwoManCrew.Server.getClaim()
	local restoredCount = getRestoredCount()

	for tier = 1, 5 do
		if not tiersState.buildings[tier] then
			if evaluateBuildingTier(tier, claim, restoredCount, tiersState) then
				tiersState.buildings[tier] = true
				announceTier(
					"Tier reached: " .. BUILDING_TIER_NAMES[tier],
					"reached building tier " .. tier .. " (" .. BUILDING_TIER_NAMES[tier] .. ")"
				)
			end
		end
	end

	-- Only run the animal census if at least one livestock stage remains,
	-- so a crew that already hit L4 never pays the per-square scan again.
	local livestockRemaining = not (tiersState.livestock[1] and tiersState.livestock[2]
		and tiersState.livestock[3] and tiersState.livestock[4])
	if livestockRemaining then
		local censusStart = getTimestampMs()
		local animalTotal, animalBabies, occupiedHutches = censusNearbyAnimals()
		print("TMC_PERF census ms=" .. (getTimestampMs() - censusStart)
			.. " animals=" .. tostring(animalTotal))

		-- Stash what the census actually saw, so getTierProgress can report it.
		-- Without this the crew sees a stage marked incomplete with no way to
		-- tell whether the game saw zero animals or simply could not look.
		tiersState.lastCensus = {
			animals = animalTotal,
			babies = animalBabies,
			occupiedHutches = occupiedHutches,
			troughs = countTroughsOnClaim(claim),
		}

		for stage = 1, 4 do
			if not tiersState.livestock[stage] then
				if evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies, claim, occupiedHutches) then
					tiersState.livestock[stage] = true
					announceTier(
						"Livestock stage reached: " .. LIVESTOCK_STAGE_NAMES[stage],
						"reached livestock stage " .. stage .. " (" .. LIVESTOCK_STAGE_NAMES[stage] .. ")"
					)
				end
			end
		end
	else
		-- Every stage is done, so the census no longer runs. Clear the cached
		-- figures rather than leaving the crew staring at a count frozen at
		-- the moment L4 completed.
		tiersState.lastCensus = nil
	end
	perfDone("full")
end

-- ---------------------------------------------------------------------------
-- Read surface for the UI
-- ---------------------------------------------------------------------------

local function highestReached(flags, maxTier)
	local highest = 0
	for t = 1, maxTier do
		if flags[t] then highest = t end
	end
	return highest
end

local BUILDING_REMAINING_TEXT = {
	[1] = "restore one building fully",
	[2] = "restore three buildings that sit next to each other",
	[3] = "restore half the buildings on the claimed block",
	[4] = "restore every claimed building",
	[5] = "restore every claimed building and hold the block " .. TIER5_HOLD_NIGHTS .. " nights",
}

local LIVESTOCK_REMAINING_TEXT = {
	[1] = "build a feeding trough on the claimed block",
	[2] = "keep at least one living animal near the crew",
	[3] = "build a hutch and put an animal in it, then stand near it",
	[4] = "keep a young animal alive near the crew for " .. L4_HERD_HOLD_NIGHTS .. " nights",
}

-- Returns the crew's tier progress. Shape (all fields always present, nil
-- only where explicitly noted):
--   {
--     buildingTier          = number,  -- highest reached, 0 if none
--     buildingTierName       = string, -- "None" if buildingTier is 0
--     nextBuildingTier       = number|nil,  -- nil once all 5 are reached
--     nextBuildingTierName   = string|nil,
--     buildingRemaining      = string|nil,  -- one-line description, nil once done
--     holdNightsDone         = number|nil,  -- tier 5 hold progress, nil until
--     holdNightsNeeded       = number|nil,  --   every building is restored
--     livestockStage         = number,  -- highest reached, 0 if none
--     livestockStageName     = string,  -- "None" if livestockStage is 0
--     nextLivestockStage     = number|nil,
--     nextLivestockStageName = string|nil,
--     livestockRemaining     = string|nil,
--     herdNightsDone         = number|nil,  -- L4 hold progress, nil until a
--     herdNightsNeeded       = number|nil,  --   baby animal is present
--     censusAnimals          = number|nil,  -- what the last census saw; nil
--     censusBabies           = number|nil,  --   before the first census runs
--     censusHutches          = number|nil,  -- occupied hutches seen
--     censusTroughs          = number|nil,  -- troughs on the claim, nil if
--                                           --   the trough system was unreadable
--   }
-- Safe to call with no claim assigned yet: everything reads as 0/"None"/nil.
function TwoManCrew.Server.getTierProgress()
	local state = TwoManCrew.Server.getState()
	local tiersState = ensureTierSchema(state)

	local buildingTier = highestReached(tiersState.buildings, 5)
	local nextBuildingTier = buildingTier < 5 and (buildingTier + 1) or nil

	local livestockStage = highestReached(tiersState.livestock, 4)
	local nextLivestockStage = livestockStage < 4 and (livestockStage + 1) or nil

	-- Tier 5's hold stretch, surfaced so the crew can see it counting down
	-- rather than waiting blind. nil until every building is restored, which
	-- is when allRestoredSinceHours is first stamped.
	local holdNightsDone, holdNightsNeeded
	if tiersState.allRestoredSinceHours then
		local elapsed = getGameTime():getWorldAgeHours() - tiersState.allRestoredSinceHours
		holdNightsDone = math.floor(elapsed / 24)
		holdNightsNeeded = TIER5_HOLD_NIGHTS
		if holdNightsDone > holdNightsNeeded then
			holdNightsDone = holdNightsNeeded
		end
	end

	-- L4's herd hold stretch, surfaced like tier 5's.
	local herdNightsDone, herdNightsNeeded
	if tiersState.herdSinceHours then
		local elapsed = getGameTime():getWorldAgeHours() - tiersState.herdSinceHours
		herdNightsDone = math.floor(elapsed / 24)
		herdNightsNeeded = L4_HERD_HOLD_NIGHTS
		if herdNightsDone > herdNightsNeeded then
			herdNightsDone = herdNightsNeeded
		end
	end

	local census = tiersState.lastCensus

	return {
		buildingTier = buildingTier,
		buildingTierName = BUILDING_TIER_NAMES[buildingTier] or "None",
		nextBuildingTier = nextBuildingTier,
		nextBuildingTierName = nextBuildingTier and BUILDING_TIER_NAMES[nextBuildingTier] or nil,
		buildingRemaining = nextBuildingTier and BUILDING_REMAINING_TEXT[nextBuildingTier] or nil,
		holdNightsDone = holdNightsDone,
		holdNightsNeeded = holdNightsNeeded,

		livestockStage = livestockStage,
		livestockStageName = LIVESTOCK_STAGE_NAMES[livestockStage] or "None",
		nextLivestockStage = nextLivestockStage,
		nextLivestockStageName = nextLivestockStage and LIVESTOCK_STAGE_NAMES[nextLivestockStage] or nil,
		livestockRemaining = nextLivestockStage and LIVESTOCK_REMAINING_TEXT[nextLivestockStage] or nil,
		herdNightsDone = herdNightsDone,
		herdNightsNeeded = herdNightsNeeded,
		censusAnimals = census and census.animals,
		censusBabies = census and census.babies,
		censusHutches = census and census.occupiedHutches,
		censusTroughs = census and census.troughs,
	}
end

Events.EveryTenMinutes.Add(evaluateTiers)
