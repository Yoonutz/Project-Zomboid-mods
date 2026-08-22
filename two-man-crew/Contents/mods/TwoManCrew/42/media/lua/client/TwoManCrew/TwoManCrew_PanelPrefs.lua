-- TwoManCrew_PanelPrefs.lua (client)
--
-- Per-player display preferences for the crew panel: where it sits, how big it
-- is, and what it shows. Saved so the panel comes back where you left it.
--
-- These live in the PLAYER's own ModData, never in the shared crew state. Two
-- people on one server want the panel in different corners; position is not
-- something to sync. Campaign progress IS shared - that lives in
-- TwoManCrew_CrewState.lua and is owned by the server.
--
-- Verified APIs (installed Build 42.20.3):
--   player:getModData()  returns a plain table, persisted with the save
--     client/LastStand/LastStandSetup.lua:77-89
--   getCore():getScreenWidth() / getScreenHeight()
--     client/Chat/ISAlert.lua:33-34

require "TwoManCrew/TwoManCrew_Config"

TwoManCrew.Prefs = TwoManCrew.Prefs or {}

local KEY = "TwoManCrew_PanelPrefs"

local DEFAULTS = {
	x = 12,
	y = 90,
	-- Size step for the always-on-screen badge, and a SEPARATE one for the
	-- journal window. Two fields on purpose.
	--
	-- They were one, and the verdict on that was "zoom linked to everything".
	-- The surfaces want opposite things: the badge is glanceable HUD that should
	-- stay out of the way, the journal is something you open to sit and read.
	-- One number cannot serve both.
	--
	-- Do NOT merge these back to remove the duplication. The duplication is the
	-- feature, and merging them is the single most likely way to reintroduce the
	-- complaint.
	-- Badge size in PIXELS, width and height independently, set by the wheel
	-- rather than picked from a list.
	--
	-- It used to be one step out of a fixed table, and the verdict on that was
	-- "incremental zoom on all axis, infinite, not just some hardcoded values".
	-- So there is no table and no ceiling: the wheel multiplies, and it keeps
	-- going until the badge fills the screen.
	--
	-- The floor exists because a badge smaller than this cannot be hit, and a
	-- control the player cannot click back is not a size, it is a trap.
	badgeW = 32,
	badgeH = 32,
	journalStep = 2,
	locked = false,
	-- When false (the default) the widget is just its badge until the mouse
	-- is over it. The panel used to be a permanent dark rectangle sitting on
	-- the HUD; collapsing it to the icon is what stops it reading as a debug
	-- overlay. Players who would rather keep the text on screen at all times
	-- set this from the right-click menu.
}

-- Scale steps offered in the right-click menu. Kept coarse: a slider in a
-- context menu is worse than four honest choices.
-- Size presets. Each step pairs a font with the chrome multiplier that suits it.
--
-- These used to be a bare list of multipliers from 0.85 to 3.0, seven steps,
-- while the font was chosen from only three thresholds. So chrome grew
-- continuously and text jumped in three places, and between two steps the
-- buttons visibly outgrew the words on them. That is the whole of the
-- "inconsistent layout" complaint, and it was arithmetic, not taste.
--
-- Pairing them removes the mismatch by construction: one step, one font, one
-- chrome multiplier, both moving together. There are only four fonts in the
-- engine, so there are four steps. Do not add a fifth without a fifth font.
--
-- The font is stored by NAME, not as a UIFont value, because this file loads
-- before the engine globals are guaranteed to exist. Resolve it at use.
TwoManCrew.Prefs.SIZES = {
	{ font = "NewSmall", chrome = 1.00 },
	{ font = "Small",    chrome = 1.20 },
	{ font = "Medium",   chrome = 1.50 },
	{ font = "Large",    chrome = 1.90 },
}

-- Resolves a step index to its font value and chrome multiplier.
function TwoManCrew.Prefs.size(step)
	local entry = TwoManCrew.Prefs.SIZES[step or 1] or TwoManCrew.Prefs.SIZES[1]
	local font = UIFont and UIFont[entry.font] or nil
	return font, entry.chrome
end


-- Returns a fresh copy of the defaults. Callers that have no player to read
-- from get this instead of the DEFAULTS table itself: every mutator writes
-- through whatever get() hands back, so returning the shared table let one
-- call with no player (getPlayer() is nil between saves and during early
-- load) permanently rewrite the defaults for every character created after.
local function copyDefaults()
	local copy = {}
	for k, v in pairs(DEFAULTS) do copy[k] = v end
	return copy
end

-- Returns the live preference table for this player, creating it with defaults
-- on first use. Mutating the returned table persists with the save.
-- Older saves stored a single `scale` multiplier. Map it onto the nearest step
-- once, for both surfaces, so an existing character keeps roughly the size they
-- had instead of silently snapping back to the default.
function TwoManCrew.Prefs.migrate(prefs)
	if prefs.scale == nil then return prefs end

	local best, bestGap = 1, math.huge
	for i = 1, #TwoManCrew.Prefs.SIZES do
		local gap = math.abs(TwoManCrew.Prefs.SIZES[i].chrome - prefs.scale)
		if gap < bestGap then
			best, bestGap = i, gap
		end
	end

	prefs.journalStep = prefs.journalStep or best
	prefs.badgeW = prefs.badgeW or math.floor(22 * prefs.scale + 0.5)
	prefs.badgeH = prefs.badgeH or math.floor(22 * prefs.scale + 0.5)
	prefs.scale = nil
	return prefs
end

function TwoManCrew.Prefs.get(player)
	player = player or getPlayer()
	if not player then return copyDefaults() end

	local md = player:getModData()
	if not md then return copyDefaults() end

	local prefs = md[KEY]
	if not prefs then
		prefs = {}
		md[KEY] = prefs
	end

	-- An older save may still hold the single `scale` field. Fold it into the
	-- two per-surface steps BEFORE the additive fill, so the migrated value
	-- wins over the defaults instead of being overwritten by them.
	TwoManCrew.Prefs.migrate(prefs)

	-- Additive fill: a save written before a preference existed still loads,
	-- and a preference removed later does not strand a stale value.
	for k, v in pairs(DEFAULTS) do
		if prefs[k] == nil then prefs[k] = v end
	end

	return prefs
end

-- Clamps a stored position back onto the visible screen. A panel dragged to the
-- edge and then reopened at a smaller resolution would otherwise be lost.
function TwoManCrew.Prefs.clampToScreen(prefs, width, height)
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()

	if prefs.x < 0 then prefs.x = 0 end
	if prefs.y < 0 then prefs.y = 0 end
	if prefs.x > sw - width then prefs.x = sw - width end
	if prefs.y > sh - height then prefs.y = sh - height end

	return prefs
end

function TwoManCrew.Prefs.setPosition(player, x, y)
	local prefs = TwoManCrew.Prefs.get(player)
	prefs.x = x
	prefs.y = y
end


-- Multiplies the badge towards a target size. Free-form, so there is no step
-- list and no maximum - only a floor small enough to stay clickable and a
-- ceiling of the screen itself, because a badge larger than the screen cannot
-- be reached to shrink again.
--
-- Width and height move independently so the player can stretch either axis.
function TwoManCrew.Prefs.zoomBadge(player, factorW, factorH)
	local prefs = TwoManCrew.Prefs.get(player)

	local minSize = 12
	local maxW = getCore():getScreenWidth()
	local maxH = getCore():getScreenHeight()

	local w = (prefs.badgeW or 32) * (factorW or 1)
	local h = (prefs.badgeH or 32) * (factorH or 1)

	-- Round away from the current value, so a small badge still grows by at
	-- least a pixel per notch instead of rounding back to where it started.
	w = math.floor(w + 0.5)
	h = math.floor(h + 0.5)
	if w == prefs.badgeW and (factorW or 1) > 1 then w = w + 1 end
	if h == prefs.badgeH and (factorH or 1) > 1 then h = h + 1 end

	if w < minSize then w = minSize end
	if h < minSize then h = minSize end
	if w > maxW then w = maxW end
	if h > maxH then h = maxH end

	prefs.badgeW = w
	prefs.badgeH = h
end

function TwoManCrew.Prefs.setJournalStep(player, step)
	local prefs = TwoManCrew.Prefs.get(player)
	prefs.journalStep = step
end

function TwoManCrew.Prefs.toggle(player, field)
	local prefs = TwoManCrew.Prefs.get(player)
	prefs[field] = not prefs[field]
	return prefs[field]
end

function TwoManCrew.Prefs.reset(player)
	local prefs = TwoManCrew.Prefs.get(player)
	for k, v in pairs(DEFAULTS) do
		prefs[k] = v
	end
	return prefs
end
