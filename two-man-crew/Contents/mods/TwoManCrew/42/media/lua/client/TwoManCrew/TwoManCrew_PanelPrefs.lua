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
	scale = 1.0,
	showTally = true,
	showJournal = true,
	locked = false,
	-- When false (the default) the widget is just its badge until the mouse
	-- is over it. The panel used to be a permanent dark rectangle sitting on
	-- the HUD; collapsing it to the icon is what stops it reading as a debug
	-- overlay. Players who would rather keep the text on screen at all times
	-- set this from the right-click menu.
	alwaysExpanded = false,
}

-- Scale steps offered in the right-click menu. Kept coarse: a slider in a
-- context menu is worse than four honest choices.
-- Size steps, picked by NUMBER rather than by percentage.
--
-- These used to be shown as "85%", "100%", "125%". A percentage asks the player
-- to work out what it is a percentage of; a step number just says bigger. The
-- range also stopped at 1.5, which was not big enough to read comfortably, so
-- it now runs to 3.
--
-- The index into this table IS the number the player clicks, so the order is
-- part of the contract: never reorder or insert in the middle, only append.
TwoManCrew.Prefs.SCALES = { 0.85, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0 }

-- The step number for a stored scale, for ticking the current entry in a menu.
function TwoManCrew.Prefs.scaleStep(scale)
	local best, bestGap = 1, math.huge
	for i = 1, #TwoManCrew.Prefs.SCALES do
		local gap = math.abs(TwoManCrew.Prefs.SCALES[i] - (scale or 1.0))
		if gap < bestGap then
			best, bestGap = i, gap
		end
	end
	return best
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

function TwoManCrew.Prefs.setScale(player, scale)
	local prefs = TwoManCrew.Prefs.get(player)
	prefs.scale = scale
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
