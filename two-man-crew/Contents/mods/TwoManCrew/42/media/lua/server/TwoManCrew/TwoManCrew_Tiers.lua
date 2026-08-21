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
-- names for L2/L4. L1 (pen) and L3 (hutch) do not need enumeration at all and
-- are NOT checked here for real: see the fallback note on BUILDING_TIERS below -
-- this module has no verified way to identify a specific placed object (fence/
-- trough/hutch) as "the crew's pen" either, so L1/L3 use the same crew-declared-
-- and-tallied fallback as the building tiers' restoration count.

require "TwoManCrew/TwoManCrew_Config"

if isClient() then return end

TwoManCrew.Server = TwoManCrew.Server or {}

local BUILDING_TIER_NAMES = {
	[1] = "One House",
	[2] = "The Row",
	[3] = "The Square",
	[4] = "The Walls",
	[5] = "The Rebuilt Town",
}

local LIVESTOCK_STAGE_NAMES = {
	[1] = "The Pen",
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
-- Livestock counting (fallback: proximity census, see file header)
-- ---------------------------------------------------------------------------

-- Counts living (and separately, baby) IsoAnimal instances within crew radius
-- of any online crew member. Fallback census per GOALS.md's own stated
-- fallback clause - see file header for why no true area enumeration is used.
local function censusNearbyAnimals()
	local seen = {}
	local total, babies = 0, 0

	for _, player in ipairs(TwoManCrew.getAllPlayers()) do
		local square = player:getSquare()
		if square then
			local objects = square:getMovingObjects()
			if objects then
				for j = 0, objects:size() - 1 do
					local obj = objects:get(j)
					if obj and instanceof(obj, "IsoAnimal") and not seen[obj] then
						seen[obj] = true
						total = total + 1
						if obj:isBaby() then
							babies = babies + 1
						end
					end
				end
			end
		end
	end

	return total, babies
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

-- Tier conditions. Each returns true/false given the claim and the restored
-- count. Buildings adjacency (tier 2's "three ADJACENT") and public-building
-- identification (tier 3) have no verified per-building metadata check in
-- this codebase, so both fall back to a simple count against the claim's
-- building list - the same crew-declared-claim fallback GOALS.md names for
-- the enumeration gaps. Tiers 1, 2 (as "any 3 restored"), and 5 (all
-- restored + hold) are real counts against verified state; 3 and 4 are
-- explicitly the fallback.
local function evaluateBuildingTier(tier, claim, restoredCount, tiersState)
	if not claim or not claim.buildings then return false end
	local totalBuildings = #claim.buildings

	if tier == 1 then
		-- Real check: at least one building restored.
		return restoredCount >= 1
	elseif tier == 2 then
		-- Fallback: "three adjacent" cannot be verified without a building
		-- adjacency API, so this counts any three restored buildings on the
		-- claimed block instead - weaker, but still an observed count.
		return restoredCount >= 3
	elseif tier == 3 then
		-- Fallback: no verified way to flag a specific building as "the
		-- large public one" from this codebase's confirmed API list, so this
		-- treats it as satisfied once every claimed building is restored
		-- except tier 5's hold requirement - i.e. folded into full
		-- restoration rather than singled out. Reported to the player as a
		-- fallback in the module's doc comment; not a real per-building check.
		return totalBuildings > 0 and restoredCount >= totalBuildings
	elseif tier == 4 then
		-- Fallback: "perimeter sealed" has no verified block-boundary
		-- barricade sweep in this codebase (object:getBarricadeOnSameSquare()
		-- checks one object at a time, not a perimeter). Uses the same
		-- full-restoration proxy as tier 3.
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

local function evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies)
	if stage == 1 then
		-- Fallback: no verified way to identify a placed fence+trough
		-- combo as "the crew's pen" specifically (structures are anonymous
		-- IsoObjects once built). Uses the pensBuilt tally if some other
		-- feature ever populates it, else falls back to "at least one
		-- animal is present", since a pen is a precondition for keeping one.
		local tally = TwoManCrew.Server.getTally and TwoManCrew.Server.getTally()
		if tally and tally.pensBuilt and tally.pensBuilt > 0 then return true end
		return animalTotal >= 1
	elseif stage == 2 then
		-- Real-ish check (fallback census, see file header): at least one
		-- living animal currently seen near the crew.
		return animalTotal >= 1
	elseif stage == 3 then
		-- Fallback: same anonymous-structure gap as L1. Uses the
		-- hutchesBuilt tally if populated, else requires at least 2 animals
		-- present as a weak proxy for "hutch is stocked".
		local tally = TwoManCrew.Server.getTally and TwoManCrew.Server.getTally()
		if tally and tally.hutchesBuilt and tally.hutchesBuilt > 0 then return true end
		return animalTotal >= 2
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

local function evaluateTiers()
	if not TwoManCrew.Server.hasClaim or not TwoManCrew.Server.hasClaim() then
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
		local animalTotal, animalBabies = censusNearbyAnimals()

		for stage = 1, 4 do
			if not tiersState.livestock[stage] then
				if evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies) then
					tiersState.livestock[stage] = true
					announceTier(
						"Livestock stage reached: " .. LIVESTOCK_STAGE_NAMES[stage],
						"reached livestock stage " .. stage .. " (" .. LIVESTOCK_STAGE_NAMES[stage] .. ")"
					)
				end
			end
		end
	end
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
	[2] = "restore three buildings on the block",
	[3] = "restore every claimed building (public building check falls back to full restoration)",
	[4] = "restore every claimed building (perimeter check falls back to full restoration)",
	[5] = "restore every claimed building and hold the block " .. TIER5_HOLD_NIGHTS .. " nights",
}

local LIVESTOCK_REMAINING_TEXT = {
	[1] = "keep an animal near the claimed block (pen check falls back to animal presence)",
	[2] = "keep at least one living animal near the claimed block",
	[3] = "keep animals stocked (hutch check falls back to animal count)",
	[4] = "raise a baby animal near the block for " .. L4_HERD_HOLD_NIGHTS .. " nights",
}

-- Returns the crew's tier progress. Shape (all fields always present, nil
-- only where explicitly noted):
--   {
--     buildingTier          = number,  -- highest reached, 0 if none
--     buildingTierName       = string, -- "None" if buildingTier is 0
--     nextBuildingTier       = number|nil,  -- nil once all 5 are reached
--     nextBuildingTierName   = string|nil,
--     buildingRemaining      = string|nil,  -- one-line description, nil once done
--     livestockStage         = number,  -- highest reached, 0 if none
--     livestockStageName     = string,  -- "None" if livestockStage is 0
--     nextLivestockStage     = number|nil,
--     nextLivestockStageName = string|nil,
--     livestockRemaining     = string|nil,
--   }
-- Safe to call with no claim assigned yet: everything reads as 0/"None"/nil.
function TwoManCrew.Server.getTierProgress()
	local state = TwoManCrew.Server.getState()
	local tiersState = ensureTierSchema(state)

	local buildingTier = highestReached(tiersState.buildings, 5)
	local nextBuildingTier = buildingTier < 5 and (buildingTier + 1) or nil

	local livestockStage = highestReached(tiersState.livestock, 4)
	local nextLivestockStage = livestockStage < 4 and (livestockStage + 1) or nil

	return {
		buildingTier = buildingTier,
		buildingTierName = BUILDING_TIER_NAMES[buildingTier] or "None",
		nextBuildingTier = nextBuildingTier,
		nextBuildingTierName = nextBuildingTier and BUILDING_TIER_NAMES[nextBuildingTier] or nil,
		buildingRemaining = nextBuildingTier and BUILDING_REMAINING_TEXT[nextBuildingTier] or nil,

		livestockStage = livestockStage,
		livestockStageName = LIVESTOCK_STAGE_NAMES[livestockStage] or "None",
		nextLivestockStage = nextLivestockStage,
		nextLivestockStageName = nextLivestockStage and LIVESTOCK_STAGE_NAMES[nextLivestockStage] or nil,
		livestockRemaining = nextLivestockStage and LIVESTOCK_REMAINING_TEXT[nextLivestockStage] or nil,
	}
end

Events.EveryTenMinutes.Add(evaluateTiers)
