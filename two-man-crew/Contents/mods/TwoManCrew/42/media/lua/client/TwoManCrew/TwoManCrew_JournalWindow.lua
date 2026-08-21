-- TwoManCrew_JournalWindow.lua (client)
--
-- The crew journal, as a real window you click rather than a key you memorise.
-- Opens from the button on the crew panel; drag it, scroll it, close it.
--
-- Reads like a logbook: newest entry first, each line stamped with the in-game
-- day it happened and who did it. The campaign claim, once assigned, sits at the
-- top as the standing objective.
--
-- Also holds the Campaign view: the five building tiers and four livestock
-- stages from GOALS.md, showing what is done and what remains. A single
-- "View: Journal / Campaign" toggle button switches between the two, rather
-- than a second ISTabPanel - see the toggle-vs-tabs note below the button
-- definitions for why.
--
-- Verified APIs (installed Build 42.20.3):
--   ISCollapsableWindow:derive   client/Camping/ISUI/ISCampingInfoWindow.lua:4
--   ISCollapsableWindow.createChildren / :initialise / :addToUIManager
--     same file, :7-13
--   ISButton:new(x,y,w,h,title,target,onclick)
--     client/ISUI/ISButton.lua:479 signature; onclick invoked as
--     self.onclick(self.target, self, ...) at client/ISUI/ISButton.lua:47,
--     i.e. (target, button); usage client/Chat/ISChat.lua:103
--   ISScrollingListBox            client/DebugUIs/AnimationClipViewer.lua:1
--   self:drawText(text,x,y,r,g,b,a,font)   alpha LAST
--     client/ISUI/ISUIElement.lua:1293, usage client/Fishing/FishingDebugWindow.lua:64
--   self:drawRect(x,y,w,h,a,r,g,b)   alpha BEFORE the r,g,b triplet
--     client/ISUI/ISUIElement.lua:1191, usage client/Fishing/TensionUI.lua:66
--   Base ISCollapsableWindow:close() only hides, never removeFromUIManager()
--     client/ISUI/ISCollapsableWindow.lua:134-136 - so this window overrides
--     close() to pair both calls, matching client/Fishing/FishingDebugWindow.lua:10-11
--     and client/DebugUIs/ISTeleportDebugUI.lua:142-143
--
-- Tabs vs toggle: ISTabPanel exists (client/ISUI/ISTabPanel.lua) and is used
-- by real windows (e.g. client/ISUI/Hutch/ISHutchUI.lua:764-790), but
-- ISTabPanel:addView(name, view) (ISTabPanel.lua:484) requires a separate
-- child ISPanel per tab that the panel itself resizes/positions - a second
-- widget hierarchy on top of the list this window already has. A toggle
-- button switching what the existing content area renders needed no new
-- widget hierarchy and keeps the Journal view byte-for-byte unchanged when
-- collapsed, so it was chosen over tabs for this two-view case.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "TwoManCrew/TwoManCrew_Config"

TwoManCrewJournalWindow = ISCollapsableWindow:derive("TwoManCrewJournalWindow")

local PAD = 8
local ROW = 20
local BUTTON_W = 90

-- Building tiers and livestock stages, per GOALS.md. Kept here (not in the
-- Tiers server module, which this client code cannot see the final shape
-- of) purely as display labels/order - the actual completion state comes
-- from the server and is matched onto these by index/key defensively.
local BUILDING_TIERS = {
	{ key = "tier1", label = "One House" },
	{ key = "tier2", label = "The Row" },
	{ key = "tier3", label = "The Square" },
	{ key = "tier4", label = "The Walls" },
	{ key = "tier5", label = "The Rebuilt Town" },
}

local LIVESTOCK_STAGES = {
	{ key = "L1", label = "The Pen" },
	{ key = "L2", label = "First Stock" },
	{ key = "L3", label = "The Hutch" },
	{ key = "L4", label = "The Herd" },
}

function TwoManCrewJournalWindow:createChildren()
	ISCollapsableWindow.createChildren(self)

	local top = self:titleBarHeight() + PAD

	self.claimLabel = nil

	-- "journal" or "campaign" - which view the content area currently
	-- renders. Toggled by viewButton; see the tabs-vs-toggle note at the top
	-- of this file for why this is a button rather than an ISTabPanel.
	self.activeView = "journal"

	self.list = ISScrollingListBox:new(PAD, top + ROW, self.width - PAD * 2, ROW)
	self.list:initialise()
	self.list:instantiate()
	self.list.itemheight = ROW
	self.list.selected = -1
	self.list.drawBorder = true
	self:addChild(self.list)

	self.refreshButton = ISButton:new(
		PAD, 0, BUTTON_W, ROW,
		"Refresh", self, TwoManCrewJournalWindow.onRefresh
	)
	self.refreshButton:initialise()
	self:addChild(self.refreshButton)

	self.claimButton = ISButton:new(
		PAD, 0, BUTTON_W, ROW,
		"Claim a block", self, TwoManCrewJournalWindow.onClaim
	)
	self.claimButton:initialise()
	self:addChild(self.claimButton)

	self.viewButton = ISButton:new(
		PAD, 0, BUTTON_W, ROW,
		"View: Campaign", self, TwoManCrewJournalWindow.onToggleView
	)
	self.viewButton:initialise()
	self:addChild(self.viewButton)

	-- Forces an immediate rescan of the claim. Without this button the server's
	-- requestRestorationCheck handler had no caller at all: restoration only
	-- ever updated on the ten-minute tick, and a crew that had just finished a
	-- house had no way to see it counted.
	self.checkButton = ISButton:new(
		PAD, 0, BUTTON_W, ROW,
		"Check progress", self, TwoManCrewJournalWindow.onCheckRestoration
	)
	self.checkButton:initialise()
	self:addChild(self.checkButton)

	-- Every child above is created at a placeholder position; layout() is the
	-- single owner of where they actually sit, so the window is laid out the
	-- same way on first open and on every resize.
	self:layout()

	self:onRefresh()
end

-- Positions the list and the button row from the CURRENT window size.
--
-- Previously these were positioned inline in createChildren() against the
-- construction-time width/height, which produced two defects: the list was
-- given the full height below the header (`self.height - top - ROW - PAD`)
-- while the buttons were placed at `self.height - ROW - PAD`, so the list
-- covered the button row by exactly ROW pixels; and the four fixed button
-- offsets summed to 466px inside a 440px window, pushing "Check progress"
-- 34px off the right edge. Both are now derived, and the window is
-- resizable, so this runs again on every resize.
function TwoManCrewJournalWindow:layout()
	local top = self:titleBarHeight() + PAD

	-- The bottom strip belongs to the resize widgets (ISCollapsableWindow.lua:34-49
	-- creates a corner widget and a full-width bottom widget, both rh tall) and to
	-- the status bar the base render() paints over it (ISCollapsableWindow.lua:185-191).
	-- Placing the button row at height-ROW-PAD put it on top of that strip, so the
	-- bottom of every button was overdrawn and the bottom edge swallowed the clicks.
	-- Reserve the strip and sit the buttons above it.
	local rh = self.resizable and self:resizeWidgetHeight() or 0
	local buttonsY = self.height - rh - ROW - PAD

	-- List stops above the button row, never behind it.
	local listY = top + ROW
	local listH = buttonsY - PAD - listY
	if listH < ROW then listH = ROW end

	self.list:setX(PAD)
	self.list:setY(listY)
	self.list:setWidth(self.width - PAD * 2)
	self.list:setHeight(listH)

	-- Buttons share the usable width evenly, so they always fit whatever the
	-- window has been resized to rather than overflowing a fixed layout.
	local buttons = { self.refreshButton, self.claimButton, self.viewButton, self.checkButton }
	local gap = 6
	local usable = self.width - PAD * 2 - gap * (#buttons - 1)
	local each = math.floor(usable / #buttons)
	if each < 40 then each = 40 end

	local x = PAD
	for i = 1, #buttons do
		buttons[i]:setX(x)
		buttons[i]:setY(buttonsY)
		buttons[i]:setWidth(each)
		x = x + each + gap
	end
end

-- Resizable window: re-run the same layout the constructor used, so dragging
-- the corner can never reintroduce the overlap this replaced.
--
-- ISResizeWidget drives the parent's size while dragging. Neither
-- ISCollapsableWindow nor ISPanel defines onResize, so the call below
-- resolves up the chain to ISUIElement:onResize (ISUIElement.lua:563), which
-- re-reads width/height and applies minimumWidth/minimumHeight. The nil guard
-- matters because a resize can arrive before createChildren has finished
-- building the row (the base createChildren adds the resize widgets first).
function TwoManCrewJournalWindow:onResize()
	ISCollapsableWindow.onResize(self)
	if self.list and self.refreshButton then
		self:layout()
	end
end

-- Asks the server for the current tally and journal. The reply lands in
-- TwoManCrew.Client.lastReport, which populate() reads on the next render.
-- Also requests campaign tier progress, so both views are fresh on open and
-- on every Refresh click - one button, two round trips.
function TwoManCrewJournalWindow:onRefresh()
	if TwoManCrew.Client and TwoManCrew.Client.requestCrewReport then
		TwoManCrew.Client.requestCrewReport(getPlayer())
	end
	if TwoManCrew.Client and TwoManCrew.Client.requestTierProgress then
		TwoManCrew.Client.requestTierProgress(getPlayer())
	end
end

-- Asks the server to rescan the claim now rather than waiting for the timer.
-- The server owns the verdict; this only requests it. Reply is handled in
-- TwoManCrew_TierReport.lua's OnServerCommand, which refreshes this window.
function TwoManCrewJournalWindow:onCheckRestoration()
	local player = getPlayer()
	if not player then return end

	sendClientCommand(player, TwoManCrew.MODULE, "requestRestorationCheck", {})
	HaloTextHelper.addText(player, "Checking the claim...")
end

-- Asks the server to survey and assign a block. The server decides which one
-- and how big; the crew does not choose, so neither player can shop for an
-- easier campaign.
function TwoManCrewJournalWindow:onClaim()
	if TwoManCrew.Client and TwoManCrew.Client.requestClaim then
		TwoManCrew.Client.requestClaim(getPlayer())
	end
end

-- Flips between the Journal and Campaign views. A button, not a keybind -
-- everything in this window is click-driven.
function TwoManCrewJournalWindow:onToggleView()
	if self.activeView == "journal" then
		self.activeView = "campaign"
		self.viewButton:setTitle("View: Journal")
	else
		self.activeView = "journal"
		self.viewButton:setTitle("View: Campaign")
	end
	-- Force a repopulate even though the underlying report tables did not
	-- change - only which one is displayed did.
	self.lastSeenReport = nil
	self.lastSeenTierProgress = nil
end

-- Rebuilds the list from the last server reply. Newest first, because the last
-- thing that happened is the thing you want to read.
function TwoManCrewJournalWindow:populateJournal()
	local report = TwoManCrew.Client and TwoManCrew.Client.lastReport
	self.list:clear()

	if not report or not report.journal or #report.journal == 0 then
		self.list:addItem("Nothing recorded yet - go and do some work.", nil)
		return
	end

	local journal = report.journal
	for i = #journal, 1, -1 do
		local entry = journal[i]
		if entry and entry.text then
			local day = entry.worldAgeHours and math.floor(entry.worldAgeHours / 24) or 0
			local who = entry.playerName or "someone"
			self.list:addItem("Day " .. day .. "  -  " .. who .. " " .. entry.text, entry)
		end
	end
end

-- Reads a single stage/tier's completion state out of whatever shape the
-- server sent, trying several plausible field names since the Tiers module
-- (server) was written by another agent concurrently and its final schema
-- was not visible from here. Returns true/false/nil (nil = unknown).
--
-- Tried, in order, against a per-tier entry the progress table might expose
-- keyed by the tier's key (e.g. progress.tiers.tier1 or progress.tier1):
--   .done / .complete / .completed (booleans)
-- Falls back to comparing progress.currentTier/.tier/.current (a number or
-- the tier key itself) against this tier's index/key, on the assumption a
-- lower/earlier tier than "current" is done.
local function isStageDone(progress, tierIndex, tierKey, containerKey)
	if not progress then return nil end

	local container = progress[containerKey]
	local entry = nil
	if type(container) == "table" then
		entry = container[tierKey] or container[tierIndex]
	end
	if not entry then
		entry = progress[tierKey]
	end

	if type(entry) == "table" then
		if entry.done ~= nil then return entry.done and true or false end
		if entry.complete ~= nil then return entry.complete and true or false end
		if entry.completed ~= nil then return entry.completed and true or false end
	elseif type(entry) == "boolean" then
		return entry
	end

	-- The real shape TwoManCrew_Tiers.lua returns: a highest-reached number per
	-- track, named buildingTier / livestockStage. That module was written in
	-- parallel with this one, so the generic probes above were speculative and
	-- never matched it - every row rendered unknown. These two lines are the
	-- ones that actually fire.
	local reached
	if containerKey == "livestock" then
		reached = progress.livestockStage
	else
		reached = progress.buildingTier
	end
	if type(reached) == "number" then
		return tierIndex <= reached
	end

	local current = progress.currentTier or progress.currentStage or progress.tier or progress.current
	if type(current) == "number" then
		return tierIndex < current
	end
	if type(current) == "string" then
		if current == tierKey then return false end
	end

	return nil
end

-- Renders campaign progress: the five building tiers and four livestock
-- stages from GOALS.md, each marked done/current/unknown from whatever the
-- server sent. Every field read is optional - a bare-bones or absent Tiers
-- module still produces a readable (if sparse) list rather than an error.
function TwoManCrewJournalWindow:populateCampaign()
	local progress = TwoManCrew.Client and TwoManCrew.Client.lastTierProgress
	local received = TwoManCrew.Client and TwoManCrew.Client.tierProgressReceived
	self.list:clear()

	if not received then
		self.list:addItem("Requesting campaign progress...", nil)
		return
	end
	if not progress then
		self.list:addItem("Campaign progress unavailable - no claim yet, or the server has no data.", nil)
		return
	end

	self.list:addItem("-- Building tiers --", nil)
	for i, tier in ipairs(BUILDING_TIERS) do
		local done = isStageDone(progress, i, tier.key, "tiers")
		local mark = "?"
		if done == true then mark = "DONE" elseif done == false then mark = "..." end
		self.list:addItem(string.format("[%s] Tier %d: %s", mark, i, tier.label), tier)
	end

	self.list:addItem("-- Livestock stages --", nil)
	for i, stage in ipairs(LIVESTOCK_STAGES) do
		local done = isStageDone(progress, i, stage.key, "livestock")
		local mark = "?"
		if done == true then mark = "DONE" elseif done == false then mark = "..." end
		self.list:addItem(string.format("[%s] %s: %s", mark, stage.key, stage.label), stage)
	end

	-- What is left to do next, per track. TwoManCrew_Tiers.lua sends these as
	-- buildingRemaining and livestockRemaining; the generic names below were
	-- guessed before that module existed and never matched, so the hint never
	-- appeared. Both are shown because the two tracks advance independently.
	if type(progress.buildingRemaining) == "string" and progress.buildingRemaining ~= "" then
		self.list:addItem("Next: " .. progress.buildingRemaining, nil)
	end
	if type(progress.livestockRemaining) == "string" and progress.livestockRemaining ~= "" then
		self.list:addItem("Next: " .. progress.livestockRemaining, nil)
	end

	local remaining = progress.remaining or progress.remainingText or progress.summary
	if type(remaining) == "string" and remaining ~= "" then
		self.list:addItem("-- " .. remaining, nil)
	end
end

function TwoManCrewJournalWindow:populate()
	if self.activeView == "campaign" then
		self:populateCampaign()
	else
		self:populateJournal()
	end
end

function TwoManCrewJournalWindow:prerender()
	ISCollapsableWindow.prerender(self)

	-- Icon sits in the title bar, immediately right of the close button.
	--
	-- It used to draw at x=4, which is underneath the close button: the base
	-- class puts that button at x=1 with width titleBarHeight-2
	-- (ISCollapsableWindow.lua:55), and buttons are children, so they render
	-- AFTER this prerender and painted straight over the icon. The icon was
	-- being drawn every frame and never seen. Start past the button instead.
	if self.titleIcon then
		local th = self:titleBarHeight()
		local size = th - 4
		local iconX = 1 + (th - 2) + 2
		self:drawTextureScaled(self.titleIcon, iconX, 2, size, size, 1, 1, 1, 1)
	end

	-- Repopulate only when the underlying report changed (or the view was
	-- just toggled, which nils these out), so the list does not rebuild
	-- every frame.
	local report = TwoManCrew.Client and TwoManCrew.Client.lastReport
	local tierProgress = TwoManCrew.Client and TwoManCrew.Client.lastTierProgress
	if report ~= self.lastSeenReport or tierProgress ~= self.lastSeenTierProgress then
		self.lastSeenReport = report
		self.lastSeenTierProgress = tierProgress
		self:populate()
	end

	local y = self:titleBarHeight() + PAD - 2
	local summary = TwoManCrew.Client and TwoManCrew.Client.claimSummary

	if summary and summary.count and summary.count > 0 then
		local restored = summary.restored or 0
		local text = "Claim: " .. restored .. " of " .. summary.count .. " buildings restored"
		self:drawText(text, PAD, y, 0.85, 0.8, 0.6, 1, UIFont.Small)
	else
		self:drawText("No claim yet - press Claim a block", PAD, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
	end
end

-- Base ISCollapsableWindow:close() (client/ISUI/ISCollapsableWindow.lua:134-136) only
-- hides the window; it never calls removeFromUIManager(). Left unoverridden, clicking
-- the title-bar close button leaves the instance registered with the UIManager, so the
-- next toggle() sees getIsVisible() == false and calls addToUIManager() again on a
-- javaObject that was never removed. Vanilla singleton windows pair the two calls in an
-- overridden close() (verified: client/Fishing/FishingDebugWindow.lua:10-11,
-- client/DebugUIs/ISTeleportDebugUI.lua:142-143).
function TwoManCrewJournalWindow:close()
	self:setVisible(false)
	self:removeFromUIManager()
end

function TwoManCrewJournalWindow:new(x, y, width, height)
	local o = ISCollapsableWindow:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self

	-- Title-bar icon. Loaded once per window rather than per frame, and left
	-- nil-safe: getTexture returns nil for a missing file, and prerender skips
	-- the draw in that case, so a packaging mistake costs the icon and not the
	-- window. Path is the mod's own media/ui, mirroring vanilla's
	-- getTexture("media/ui/...") convention (client/Chat/ISChat.lua:921-924).
	o.titleIcon = getTexture("media/ui/TwoManCrew_Journal_16.png")

	o.title = "Crew Journal"
	o.resizable = true
	o.drawFrame = true

	-- The base prerender only fills the window body when self.background is
	-- true (ISCollapsableWindow.lua:163-167); ISPanel's constructor does not
	-- set it, and neither did this window. Result: only the title bar was
	-- painted and the game world showed through everywhere the list did not
	-- cover, which is the "renders weirdly" look. setDrawFrame sets both flags
	-- together (ISCollapsableWindow.lua:356-364), so keep them in step here.
	o.background = true

	-- ISResizeWidget clamps a drag to the target's minimumWidth/minimumHeight
	-- (ISResizeWidget.lua:13-22) and both default to 0, so the window could be
	-- dragged down to nothing and the button row would be squashed to its 40px
	-- floor and overlap. Four buttons plus the gaps and padding is the real
	-- floor for width; the title bar, header line, one list row and the button
	-- row is the floor for height.
	o.minimumWidth = PAD * 2 + BUTTON_W * 4 + 6 * 3
	o.minimumHeight = 160
	o.lastSeenReport = nil

	return o
end

-- Opens the window, or brings it back if it was closed. One instance only.
TwoManCrewJournalWindow.toggle = function()
	local w = TwoManCrewJournalWindow.instance

	if w and w:getIsVisible() then
		w:close()
		return
	end

	if not w then
		local sw = getCore():getScreenWidth()
		local sh = getCore():getScreenHeight()
		w = TwoManCrewJournalWindow:new(sw / 2 - 220, sh / 2 - 160, 440, 320)
		w:initialise()
		w:instantiate()
		TwoManCrewJournalWindow.instance = w
	end

	w:addToUIManager()
	w:setVisible(true)
	w:onRefresh()
end
