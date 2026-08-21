-- TwoManCrew_CrewState.lua
-- Single owner of the shared crew ModData: schema, safe accessors, the
-- increment/append functions, and cap enforcement. Every other server
-- feature module calls into this file rather than touching ModData
-- directly. Server-only; never require this from client code.
--
-- Public surface (stable, other features depend on these names):
--   TwoManCrew.Server.getState()                -> the live shared state table
--   TwoManCrew.Server.addTally(key, n, player)   -> new count for key
--   TwoManCrew.Server.addJournal(text, player)   -> the entry table just added
--   TwoManCrew.Server.getTally()                 -> { [key] = count, ... }
--   TwoManCrew.Server.getJournal()               -> array of entry tables, oldest first
--
-- ModData schema (all under ModData.getOrCreate("TwoManCrew")):
--   {
--     tally = { [key:string] = count:number, ... },
--     journal = {
--       { text = string, playerName = string, worldAgeHours = number },
--       ...  -- oldest first, capped at TwoManCrew.CrewJournal.MAX_ENTRIES
--     },
--   }

if isClient() then return end

TwoManCrew = TwoManCrew or {}
TwoManCrew.Server = TwoManCrew.Server or {}

local MODDATA_KEY = "TwoManCrew"

-- The live shared state table. Cached after first getOrCreate so repeated
-- calls in the same tick don't re-hit ModData; getOrCreate itself is cheap
-- and idempotent (verified: client/Foraging/forageClient.lua:7), but there's
-- no reason to call it more than once per access.
local state = nil

-- Defensively fills in any missing schema fields on a possibly-empty or
-- partially-populated table (brand new save, or a save from before this
-- module existed). Never overwrites existing data.
local function ensureSchema(t)
	t.tally = t.tally or {}
	t.journal = t.journal or {}
	return t
end

-- Returns the live shared state table, creating and schema-filling it on
-- first access. Safe to call from any server-side handler.
function TwoManCrew.Server.getState()
	if not state then
		state = ModData.getOrCreate(MODDATA_KEY)
		ensureSchema(state)
	end
	return state
end

-- Returns the tally sub-table directly ({ [key] = count }). Callers should
-- treat this as read-only; use addTally to mutate.
function TwoManCrew.Server.getTally()
	return TwoManCrew.Server.getState().tally
end

-- Returns the journal array directly (oldest first). Callers should treat
-- this as read-only; use addJournal to mutate.
function TwoManCrew.Server.getJournal()
	return TwoManCrew.Server.getState().journal
end

-- Increments the shared tally counter for key by n (default 1) and returns
-- the new count. player is optional and currently unused for the tally
-- itself (no per-player breakdown), but accepted so callers have a single
-- consistent call shape across addTally/addJournal and so a per-player
-- breakdown can be added later without changing the signature.
-- key: short string identifying the achievement, e.g. "treesFelled".
function TwoManCrew.Server.addTally(key, n, player)
	if not key then return nil end
	n = n or 1

	local tally = TwoManCrew.Server.getTally()
	local newCount = (tally[key] or 0) + n
	tally[key] = newCount
	return newCount
end

-- Appends a journal entry recording text, attributed to player, timestamped
-- with the current in-game world age. Enforces the configured entry cap,
-- trimming the oldest entry(ies) first so the table never grows unbounded.
-- Returns the entry table just added.
-- Verified: getGameTime():getWorldAgeHours() at server/Farming/SFarmingSystem.lua:258;
-- player:getUsername() at client/ServerCommands.lua:168.
function TwoManCrew.Server.addJournal(text, player)
	if not text then return nil end

	local journal = TwoManCrew.Server.getJournal()
	local entry = {
		text = text,
		playerName = player and player:getUsername() or "Unknown",
		worldAgeHours = getGameTime():getWorldAgeHours(),
	}

	journal[#journal + 1] = entry

	local maxEntries = TwoManCrew.CrewJournal.MAX_ENTRIES
	while #journal > maxEntries do
		table.remove(journal, 1)
	end

	return entry
end
