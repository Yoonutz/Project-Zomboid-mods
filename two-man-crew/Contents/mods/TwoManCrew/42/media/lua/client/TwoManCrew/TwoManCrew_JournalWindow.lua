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
-- stages from GOALS.md, showing what is done and what remains, plus the
-- Buildings view: one line per claimed building with the reason it is not
-- yet banked. A single view button cycles Journal -> Campaign -> Buildings,
-- rather than an ISTabPanel - see the toggle-vs-tabs note below the button
-- definitions for why. The button's label names the view the NEXT press
-- switches to, so it reads as an instruction rather than a state.
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

-- Icon buttons, sized to be comfortably hittable rather than merely legal.
--
-- The first icon pass used 28x22 with a 14px icon, which was reported as
-- "bugged and small" - and it was: a 14px picture is smaller than the text
-- label it replaced, so the row looked like a mistake rather than a design.
-- These are square, generous, and the icon fills most of the face.
local BUTTON_W = 40
local BUTTON_H = 40

-- Icon drawn inside each button, leaving an even margin all round. At 28px
-- inside a 40px button the art reads clearly at a glance and still has room
-- to breathe against the border.
local ICON = 28

-- Work Order skin.
--
-- The engine takes colour components as 0..1 floats, so each entry is the
-- spec's hex divided by 255. Kept in one table because a colour repeated
-- inline across twenty draw calls is a colour that drifts.
--
-- Palette and the role of each token:
-- docs/superpowers/specs/2026-08-22-campaign-task-cards-design.md
local SKIN = {
	ground  = { r = 0.078, g = 0.071, b = 0.055 }, -- #14120E window body
	panel   = { r = 0.118, g = 0.106, b = 0.082 }, -- #1E1B15 list background
	rule    = { r = 0.227, g = 0.196, b = 0.145 }, -- #3A3225 dividers
	ruleLit = { r = 0.353, g = 0.294, b = 0.196 }, -- #5A4B32 borders
	text    = { r = 0.863, g = 0.835, b = 0.769 }, -- #DCD5C4 primary text
	dim     = { r = 0.549, g = 0.514, b = 0.443 }, -- #8C8371 secondary text
	faint   = { r = 0.384, g = 0.357, b = 0.298 }, -- #625B4C locked
	active  = { r = 0.784, g = 0.569, b = 0.235 }, -- #C8913C current task
	done    = { r = 0.498, g = 0.659, b = 0.361 }, -- #7FA85C met
	blocked = { r = 0.706, g = 0.341, b = 0.290 }, -- #B4574A failed
	unread  = { r = 0.431, g = 0.541, b = 0.627 }, -- #6E8AA0 unknown
}

-- Card geometry.
local CARD_PAD = 6
local SPINE_W = 3
local LADDER_H = 7
local CHECK_ROW_H = 14

-- Above this many required units a ladder stops being countable, so the card
-- draws a continuous bar instead. Only the 7- and 30-night holds exceed it.
local LADDER_MAX = 12

-- Building tiers and livestock stages, per GOALS.md. Kept here (not in the
-- Tiers server module, which this client code cannot see the final shape
-- of) purely as display labels/order - the actual completion state comes
-- from the server and is matched onto these by index/key defensively.
local BUILDING_TIERS = {
	{ key = "tier1", label = "One House" },
	{ key = "tier2", label = "The Row" },
	{ key = "tier3", label = "Half the Block" },
	{ key = "tier4", label = "Every Door and Window" },
	{ key = "tier5", label = "The Rebuilt Town" },
}

local LIVESTOCK_STAGES = {
	{ key = "L1", label = "The Trough" },
	{ key = "L2", label = "First Stock" },
	{ key = "L3", label = "The Hutch" },
	{ key = "L4", label = "The Herd" },
}

-- Builds one square icon button, adds it to the window and returns it.
--
-- Position is a placeholder: layout() is the single owner of where the row
-- actually sits, so every button is created at PAD,0 and moved later.
--
-- The title is kept even though an image hides it, because ISButton falls
-- back to drawing the title when self.image is nil (ISButton.lua:197). That
-- makes a missing texture degrade to a readable text button rather than an
-- invisible one - the same nil-safety the panel's badge uses.
function TwoManCrewJournalWindow:makeIconButton(title, texturePath, tooltip, onclick)
	local button = ISButton:new(PAD, 0, BUTTON_W, BUTTON_H, title, self, onclick)
	button:initialise()

	local texture = getTexture(texturePath)
	if texture then
		button:setImage(texture)
		-- Force the drawn size so the 48px source art is not blitted at its
		-- native size inside a 28px button. ISButton only honours these two
		-- fields together (ISButton.lua:222).
		button.forcedWidthImage = ICON
		button.forcedHeightImage = ICON
	end

	button.tooltip = tooltip
	self:addChild(button)

	return button
end

function TwoManCrewJournalWindow:createChildren()
	ISCollapsableWindow.createChildren(self)

	local top = self:titleBarHeight() + PAD

	self.claimLabel = nil

	-- "journal", "campaign" or "buildings" - which view the content area
	-- currently renders. Cycled by viewButton; see the tabs-vs-toggle note at
	-- the top of this file for why this is a button rather than an ISTabPanel.
	self.activeView = "journal"

	self.list = ISScrollingListBox:new(PAD, top + ROW, self.width - PAD * 2, ROW)
	self.list:initialise()
	self.list:instantiate()
	-- Compact font so a full claim fits without reaching for the scroll wheel.
	-- setFont sets the font, its height and the row height together
	-- (client/ISUI/ISScrollingListBox.lua:703-708), so ROW must not be assigned
	-- to itemheight after this - the list owns row height now. Vanilla drives
	-- list boxes the same way at
	-- client/DebugUIs/DebugMenu/GlobalModData/GlobalModData.lua:42.
	self.list:setFont(UIFont.NewSmall, 1)
	self.list.selected = -1
	self.list.drawBorder = true
	self:addChild(self.list)

	-- Icon buttons rather than three wide text buttons. The labels were the
	-- widest thing in the window and forced a 460px minimum width for what
	-- are three one-word actions; the icon carries the meaning and the
	-- tooltip carries the word, which is how vanilla's own toolbars work.
	--
	-- setImage/tooltip verified at client/ISUI/ISButton.lua:179 (setImage)
	-- and :317-327 (the tooltip is rendered by ISButton itself when the
	-- field is set - no ISToolTip wiring needed here).
	--
	-- Every button keeps a text fallback title: getTexture returns nil for a
	-- missing file, and a button with neither image nor title is an invisible
	-- square. ISButton draws the title only when self.image is nil
	-- (ISButton.lua:197), so setting both costs nothing and means a packaging
	-- mistake degrades to the old text button instead of an empty row.
	self.refreshButton = self:makeIconButton(
		"Refresh", "media/ui/TwoManCrew_Refresh.png",
		"Refresh - ask the server for the latest tally and journal",
		TwoManCrewJournalWindow.onRefresh
	)

	self.claimButton = self:makeIconButton(
		"Claim", "media/ui/TwoManCrew_Claim.png",
		"Claim a block - the server surveys and assigns your campaign",
		TwoManCrewJournalWindow.onClaim
	)

	-- Tooltip names the view the next press switches to. Starting view is
	-- "journal", so the first press goes to Campaign.
	self.viewButton = self:makeIconButton(
		"View", "media/ui/TwoManCrew_View.png",
		"Switch view - next: Campaign",
		TwoManCrewJournalWindow.onToggleView
	)

	-- No "Check progress" button. It existed to force an immediate rescan, but
	-- opening the Buildings view now does that (see onToggleView), so the
	-- button only duplicated it. Three buttons also leaves every label room to
	-- breathe. onCheckRestoration survives as the rescan entry point.

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
	local buttonsY = self.height - rh - BUTTON_H - PAD

	-- List stops above the button row, never behind it.
	local listY = top + ROW
	local listH = buttonsY - PAD - listY
	if listH < ROW then listH = ROW end

	self.list:setX(PAD)
	self.list:setY(listY)
	self.list:setWidth(self.width - PAD * 2)
	self.list:setHeight(listH)

	-- Icon buttons keep their square size and group at the left, rather than
	-- being stretched to share the full width. Three text buttons had to
	-- stretch because their labels needed the room; three icons stretched to
	-- a third of a wide window each would just be three small pictures
	-- marooned in the middle of large empty rectangles.
	local buttons = { self.refreshButton, self.claimButton, self.viewButton }
	local gap = 6

	local x = PAD
	for i = 1, #buttons do
		buttons[i]:setX(x)
		buttons[i]:setY(buttonsY)
		buttons[i]:setWidth(BUTTON_W)
		buttons[i]:setHeight(BUTTON_H)
		x = x + BUTTON_W + gap
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
	if TwoManCrew.Client and TwoManCrew.Client.requestClaimDetail then
		TwoManCrew.Client.requestClaimDetail(getPlayer())
	end

	-- Show that the press was heard. Without this the button looks dead
	-- whenever the reply contains what the list already showed, which on an
	-- empty journal is every single press - the round trip happened, nothing
	-- on screen moved, and the only reasonable conclusion was "broken".
	self.refreshFlashMs = 1200

	-- Force the next prerender to rebuild the list even if the server hands
	-- back the very same table. The identity comparison in prerender exists
	-- to avoid rebuilding every frame, but it also means a manual Refresh
	-- could legitimately change nothing on screen; clearing these makes an
	-- explicit press always repaint.
	self.lastSeenReport = nil
	self.lastSeenTierProgress = nil
	self.lastSeenClaimDetail = nil
end

-- Asks the server to rescan the claim now rather than waiting for the
-- ten-minute tick. The server owns the verdict; this only requests it. Reply is
-- handled in TwoManCrew_TierReport.lua's OnServerCommand.
--
-- No longer bound to a button - opening the Buildings view calls this instead
-- (see onToggleView). Kept because it is the only on-demand rescan entry point,
-- and without it the server's requestRestorationCheck handler would have no
-- caller at all.
function TwoManCrewJournalWindow:onCheckRestoration()
	local player = getPlayer()
	if not player then return end

	TwoManCrew.requestFromServer(player, "requestRestorationCheck", {})
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

-- Cycles Journal -> Campaign -> Buildings -> Journal. The button label names
-- the view the NEXT press will switch to.
local VIEW_ORDER = { "journal", "campaign", "buildings" }
local VIEW_LABEL = {
	journal = "Journal",
	campaign = "Campaign",
	buildings = "Buildings",
}

local function nextView(current)
	for i, name in ipairs(VIEW_ORDER) do
		if name == current then
			return VIEW_ORDER[(i % #VIEW_ORDER) + 1]
		end
	end
	return VIEW_ORDER[1]
end

function TwoManCrewJournalWindow:onToggleView()
	self.activeView = nextView(self.activeView)

	-- The button is an icon now, so the "what does pressing this do" text
	-- lives in the tooltip rather than the label. The header line below the
	-- title bar is what tells you which view you are currently looking at -
	-- without that, an icon-only button would leave the window unlabelled.
	self.viewButton.tooltip = "Switch view - next: " .. VIEW_LABEL[nextView(self.activeView)]

	-- Entering the Buildings view forces a fresh rescan, which is what the
	-- removed "Check progress" button used to do. Requesting the detail alone
	-- would render whatever the last ten-minute tick happened to leave behind,
	-- and neither Refresh nor the Campaign view rescans anything - they only
	-- re-read stored state.
	if self.activeView == "buildings" then
		self:onCheckRestoration()
		if TwoManCrew.Client and TwoManCrew.Client.requestClaimDetail then
			TwoManCrew.Client.requestClaimDetail(getPlayer())
		end
	end

	self.lastSeenReport = nil
	self.lastSeenTierProgress = nil
	self.lastSeenClaimDetail = nil
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
-- Spine and task colour, by card state.
local STATE_COLOUR = {
	active  = SKIN.active,
	done    = SKIN.done,
	blocked = SKIN.blocked,
	locked  = SKIN.faint,
}

-- The three marks. Kept as plain characters rather than glyphs, because the
-- game's bitmap fonts do not carry a tick and a missing glyph draws as nothing
-- at all - an invisible mark is worse than a plain one.
local MARK_GLYPH = { yes = "+", no = "x", unknown = "?" }
local MARK_COLOUR = { yes = SKIN.done, no = SKIN.blocked, unknown = SKIN.unread }

-- How tall a card is, open or shut.
--
-- Single owner of card geometry. drawCard calls this rather than recomputing,
-- so the drawing and the hit-testing can never disagree about where a card
-- ends - a disagreement would put the click on the wrong card.
function TwoManCrewJournalWindow:cardHeight(card)
	local lineH = getTextManager():getFontHeight(UIFont.NewSmall)
	local h = lineH + 4 + LADDER_H + 3 + 2
	if card.context then h = h + lineH end
	if card.expanded then
		h = h + #(card.checks or {}) * CHECK_ROW_H
	end
	return h
end

-- Draws one card, and its checks when it is open. Returns the y of the next
-- row, and stamps item.height so rowAt() can hit-test a tall card - the same
-- contract vanilla's recipe list uses (ISRecipeScrollingListBox.lua:191).
--
-- The alpha positions below differ between the two calls and that is not a
-- typo: drawRect takes alpha BEFORE the rgb triplet (ISUIElement.lua:1191),
-- drawText takes it LAST (ISUIElement.lua:1293).
function TwoManCrewJournalWindow:drawCard(y, item, alt)
	local card = item and item.item
	if not card then
		return y + ((item and item.height) or self.list.itemheight or 20)
	end

	local lineH = getTextManager():getFontHeight(UIFont.NewSmall)
	local height = self:cardHeight(card)
	local top = y
	local x = CARD_PAD + SPINE_W + 5
	local w = self.list and self.list:getWidth() or self.width

	-- Body. Alternating rows separate adjacent cards without a heavy rule.
	local bg = alt and SKIN.panel or SKIN.ground
	self:drawRect(0, y, w, height, 1, bg.r, bg.g, bg.b)

	local state = STATE_COLOUR[card.state] or SKIN.faint

	-- The spine: state as colour, read before a word is parsed.
	self:drawRect(CARD_PAD, y + 2, SPINE_W, height - 4, 1, state.r, state.g, state.b)

	-- Chevron, task, count.
	self:drawText(card.expanded and "v" or ">", x, y + 2,
		SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)

	local taskColour = SKIN.text
	if card.state == "locked" or card.state == "done" then taskColour = SKIN.dim end
	self:drawText(card.task, x + 12, y + 2,
		taskColour.r, taskColour.g, taskColour.b, 1, UIFont.NewSmall)

	local count = "locked"
	if card.state ~= "locked" then
		count = tostring(card.done or 0) .. " / " .. tostring(card.target or 0)
	end
	local cw = getTextManager():MeasureStringX(UIFont.NewSmall, count)
	self:drawText(count, w - CARD_PAD - cw, y + 2,
		SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)

	y = y + lineH + 4

	-- Progress. A ladder while the target is small enough to count, a
	-- continuous bar once it is not - see LADDER_MAX.
	local barW = w - x - CARD_PAD
	local target = card.target or 0
	local done = card.done or 0

	if target > 0 and target <= LADDER_MAX then
		local gap = 2
		local cellW = (barW - (target - 1) * gap) / target
		for i = 1, target do
			local cx = x + (i - 1) * (cellW + gap)
			local c = (i <= done) and SKIN.done or SKIN.ground
			self:drawRect(cx, y, cellW, LADDER_H, 1, c.r, c.g, c.b)
			self:drawRectBorder(cx, y, cellW, LADDER_H, 1,
				SKIN.ruleLit.r, SKIN.ruleLit.g, SKIN.ruleLit.b)
		end
	else
		self:drawRect(x, y, barW, LADDER_H, 1, SKIN.ground.r, SKIN.ground.g, SKIN.ground.b)
		if target > 0 and done > 0 then
			self:drawRect(x, y, barW * (done / target), LADDER_H, 1,
				SKIN.active.r, SKIN.active.g, SKIN.active.b)
		end
		self:drawRectBorder(x, y, barW, LADDER_H, 1,
			SKIN.ruleLit.r, SKIN.ruleLit.g, SKIN.ruleLit.b)
	end
	y = y + LADDER_H + 3

	-- Context, so the ladder is never anonymous.
	if card.context then
		self:drawText(card.context, x, y,
			SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)
		y = y + lineH
	end

	-- The checks, only while the card is open.
	if card.expanded then
		for _, chk in ipairs(card.checks or {}) do
			local mc = MARK_COLOUR[chk.mark] or SKIN.dim
			self:drawText(MARK_GLYPH[chk.mark] or "?", x + 8, y,
				mc.r, mc.g, mc.b, 1, UIFont.NewSmall)
			self:drawText(chk.label, x + 22, y,
				SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)
			if chk.why then
				local ww = getTextManager():MeasureStringX(UIFont.NewSmall, chk.why)
				self:drawText(chk.why, w - CARD_PAD - ww, y,
					SKIN.faint.r, SKIN.faint.g, SKIN.faint.b, 1, UIFont.NewSmall)
			end
			y = y + CHECK_ROW_H
		end
	end

	-- Bottom rule.
	self:drawRect(0, top + height - 1, w, 1, 1, SKIN.rule.r, SKIN.rule.g, SKIN.rule.b)

	item.height = height
	return top + height
end

-- Turns the two server payloads the client already holds into task cards.
--
-- Pure by design: no getCell, no getPlayer, no drawing, no engine global at
-- all. That is what makes it testable under the fengari harness, and it is why
-- every decision below is a field read rather than a world lookup.
--
-- A card is:
--   { key, track, task, context, state, done, target, checks = {...}, expanded }
-- A check is:
--   { mark = "yes"|"no"|"unknown", label = string, why = string|nil }
--
-- The three marks are not two. "unknown" means the ground was never loaded and
-- nothing could be read, which is a different fact from a condition that
-- failed. Collapsing the two was the original defect in the Buildings view: a
-- crew could not tell a broken window from a building nobody had walked near.
function TwoManCrewJournalWindow.buildCards(progress, detail)
	local cards = {}
	progress = progress or {}

	-- Building track. One check per claimed building, so the card explains
	-- itself instead of asserting a number the crew cannot audit.
	if type(progress.buildingRemaining) == "string" and progress.buildingRemaining ~= "" then
		local checks = {}
		local done = 0
		local blocked = false

		for i, row in ipairs(detail or {}) do
			local mark = "unknown"
			if row.status == "restored" then
				mark = "yes"
				done = done + 1
			elseif row.status == "not_restored" then
				mark = "no"
				blocked = true
			end

			table.insert(checks, {
				mark = mark,
				label = string.format("Building %d - %s units", i, tostring(row.units)),
				why = TwoManCrewJournalWindow.describeRow(row),
			})
		end

		table.insert(cards, {
			key = "building",
			track = "building",
			task = progress.buildingRemaining,
			context = "Tier " .. tostring(progress.buildingTier or 0) .. " of 5",
			state = blocked and "blocked" or "active",
			done = done,
			target = #checks,
			checks = checks,
			expanded = false,
		})
	end

	-- Livestock track. The census numbers stop being a free-floating block at
	-- the bottom of the panel and become the conditions they actually gate.
	if type(progress.livestockRemaining) == "string" and progress.livestockRemaining ~= "" then
		-- A count that is absent is not a count of zero: the census may simply
		-- not have run yet, which is the "unknown" case again.
		local function countCheck(value, label)
			if type(value) ~= "number" then
				return { mark = "unknown", label = label, why = "could not read" }
			end
			if value > 0 then
				return { mark = "yes", label = label, why = value .. " seen" }
			end
			return { mark = "no", label = label, why = "0 seen" }
		end

		local checks = {
			countCheck(progress.censusTroughs, "A feeding trough on the block"),
			countCheck(progress.censusAnimals, "A living animal near the crew"),
			countCheck(progress.censusHutches, "An occupied hutch"),
			countCheck(progress.censusBabies, "A young animal"),
		}

		local done = 0
		local failed = false
		for _, c in ipairs(checks) do
			if c.mark == "yes" then
				done = done + 1
			elseif c.mark == "no" then
				failed = true
			end
		end

		table.insert(cards, {
			key = "livestock",
			track = "livestock",
			task = progress.livestockRemaining,
			context = "Stage " .. tostring(progress.livestockStage or 0) .. " of 4",
			state = failed and "blocked" or "active",
			done = done,
			target = #checks,
			checks = checks,
			expanded = false,
		})
	end

	return cards
end

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

	-- What the last census actually saw. Without this a stage reads as
	-- incomplete with no way to tell "saw zero animals" from "could not look".
	if type(progress.censusAnimals) == "number" then
		local line = string.format(
			"Last count: %d animals (%d young)",
			progress.censusAnimals, progress.censusBabies or 0
		)
		self.list:addItem(line, nil)
	end

	if type(progress.censusTroughs) == "number" then
		self.list:addItem(
			string.format("Feeding troughs on the block: %d", progress.censusTroughs),
			nil
		)
	elseif progress.censusAnimals ~= nil then
		self.list:addItem("Feeding troughs: could not read", nil)
	end

	if type(progress.censusHutches) == "number" then
		self.list:addItem(
			string.format("Occupied hutches seen: %d", progress.censusHutches),
			nil
		)
	end

	if type(progress.herdNightsDone) == "number"
		and type(progress.herdNightsNeeded) == "number"
	then
		self.list:addItem(
			string.format(
				"Herd held: %d of %d nights",
				progress.herdNightsDone, progress.herdNightsNeeded
			),
			nil
		)
	end

	-- Tier 5's hold countdown. Only present once every building is restored.
	if type(progress.holdNightsDone) == "number"
		and type(progress.holdNightsNeeded) == "number"
	then
		self.list:addItem(
			string.format(
				"Holding the block: %d of %d nights",
				progress.holdNightsDone, progress.holdNightsNeeded
			),
			nil
		)
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

-- Turns one detail row into a single human line explaining its status.
-- Returns nil when there is nothing useful to add (an already-banked
-- building needs no explanation).
function TwoManCrewJournalWindow.describeRow(row)
	if row.status == "restored" then
		return nil
	end

	-- An explicit server-supplied reason always wins - it is more specific
	-- than anything reconstructed from the flags.
	if row.reason then
		return row.reason
	end

	-- Kept short: the reason now shares the building's line, so a long string
	-- clips at the panel edge rather than wrapping.
	if row.status == "unknown" then
		if row.roomsSeen and row.roomsTotal and row.roomsSeen < row.roomsTotal then
			return string.format("only %d/%d rooms seen - walk closer", row.roomsSeen, row.roomsTotal)
		end
		return "too far - walk closer"
	end

	local todo = {}
	if row.windowsOk == false then table.insert(todo, "windows") end
	if row.doorsOk == false then table.insert(todo, "doors") end
	if row.noCorpses == false then table.insert(todo, "corpses") end
	if row.crewPresent == false then table.insert(todo, "nobody here") end

	if #todo == 0 then
		return "blocked - check the logs"
	end
	return "needs " .. table.concat(todo, ", ")
end

-- Renders one line per claimed building plus an indented reason line, so the
-- crew can see which building is blocked and on what.
--
-- Three statuses, deliberately distinct: DONE (banked), WORK (a real condition
-- failed) and ?? (not checkable right now - usually the ground is not loaded
-- because nobody is near it). Collapsing "unknown" into "not restored" was the
-- original defect; a crew could not tell a broken window from a far-away
-- building.
function TwoManCrewJournalWindow:populateBuildings()
	local detail = TwoManCrew.Client and TwoManCrew.Client.lastClaimDetail
	local received = TwoManCrew.Client and TwoManCrew.Client.claimDetailReceived
	self.list:clear()

	if not received then
		self.list:addItem("Asking the server...", nil)
		return
	end
	if not detail or #detail == 0 then
		self.list:addItem("No claim yet - press Claim a block.", nil)
		return
	end

	local done = 0
	for _, row in ipairs(detail) do
		if row.status == "restored" then done = done + 1 end
	end
	self.list:addItem(string.format("-- %d of %d restored --", done, #detail), nil)

	for i, row in ipairs(detail) do
		local mark = "??"
		if row.status == "restored" then
			mark = "DONE"
		elseif row.status == "not_restored" then
			mark = "WORK"
		end

		-- Reason shares the building's own line rather than taking an indented
		-- second row. Two rows per building overflowed the list at seven
		-- buildings, and this panel should be readable without scrolling it.
		local line = string.format("[%s] %d. %s units", mark, i, tostring(row.units))
		local reason = TwoManCrewJournalWindow.describeRow(row)
		if reason then
			line = line .. " - " .. reason
		end

		self.list:addItem(line, row)
	end
end

function TwoManCrewJournalWindow:populate()
	if self.activeView == "campaign" then
		self:populateCampaign()
	elseif self.activeView == "buildings" then
		self:populateBuildings()
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
	local claimDetail = TwoManCrew.Client and TwoManCrew.Client.lastClaimDetail
	if report ~= self.lastSeenReport
		or tierProgress ~= self.lastSeenTierProgress
		or claimDetail ~= self.lastSeenClaimDetail
	then
		self.lastSeenReport = report
		self.lastSeenTierProgress = tierProgress
		self.lastSeenClaimDetail = claimDetail
		self:populate()
	end

	local y = self:titleBarHeight() + PAD - 2
	local summary = TwoManCrew.Client and TwoManCrew.Client.claimSummary
	local refusal = TwoManCrew.Client and TwoManCrew.Client.lastClaimRefusal

	if summary and summary.count and summary.count > 0 then
		local restored = summary.restored or 0
		local text = "Claim: " .. restored .. " of " .. summary.count .. " buildings restored"
		self:drawText(text, PAD, y, 0.85, 0.8, 0.6, 1, UIFont.Small)
	elseif refusal then
		-- The server surveyed and said no. Kept on screen rather than left to
		-- the halo text that fades: a player who presses claim and sees only
		-- a vanishing message reads the button as broken, which is what was
		-- reported. Amber, because it is an answer and not an error.
		self:drawText("No claim: " .. refusal, PAD, y, 0.9, 0.7, 0.4, 1, UIFont.Small)
	else
		-- The button says "Claim" now, not "Claim a block", so the hint names
		-- the icon by its tooltip word rather than a label that no longer exists.
		self:drawText("No claim yet - press the flag button", PAD, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
	end

	-- Which view is on screen, right-aligned on the same header line. The
	-- view button lost its text label when it became an icon, so without this
	-- there would be nothing on screen naming the current view.
	local viewName = VIEW_LABEL[self.activeView] or "Journal"
	local vw = getTextManager():MeasureStringX(UIFont.Small, viewName)
	self:drawText(viewName, self.width - PAD - vw, y, 0.55, 0.6, 0.7, 1, UIFont.Small)

	-- Refresh acknowledgement. A crew with an empty journal saw the list
	-- redraw the identical "nothing recorded yet" line and concluded the
	-- button was dead - the request had in fact gone out and been answered.
	-- Flashing a short confirmation makes the round trip visible whether or
	-- not the contents changed, which is the only thing the button was
	-- missing. Timer counts down in real milliseconds, same clock the crew
	-- panel's own refresh uses.
	if self.refreshFlashMs and self.refreshFlashMs > 0 then
		self.refreshFlashMs = self.refreshFlashMs - UIManager.getMillisSinceLastRender()

		-- Drawn on the header line, to the LEFT of the right-aligned view
		-- name. It must not sit above the button row: that space belongs to
		-- the scrolling list, which renders after this prerender as a child
		-- and would paint its own rows straight over the text. The header
		-- strip is the only band this window draws into directly.
		local label = "updated"
		local labelW = getTextManager():MeasureStringX(UIFont.Small, label)
		local labelX = self.width - PAD - vw - 8 - labelW

		self:drawText(label, labelX, y, 0.6, 0.85, 0.6, 1, UIFont.Small)
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
	-- dragged down to nothing and the button row would be squashed and overlap.
	--
	-- With icon buttons the row is no longer what sets the floor - three 28px
	-- squares need barely 100px. The header line is the widest fixed element
	-- now ("Claim: N of N buildings restored" plus the right-aligned view
	-- name), so the floor is set from that instead. Sizing to the buttons
	-- would let the window shrink until the header clipped.
	o.minimumWidth = 300
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
