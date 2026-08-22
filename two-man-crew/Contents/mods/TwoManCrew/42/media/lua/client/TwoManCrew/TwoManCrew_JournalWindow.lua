-- TwoManCrew_JournalWindow.lua (client)
--
-- The crew journal, as a real window you click rather than a key you memorise.
-- Opens from the button on the crew panel; drag it, scroll it, close it.
--
-- Reads like a logbook: newest entry first, each line stamped with the in-game
-- day it happened and who did it. The campaign claim, once assigned, sits at the
-- top as the standing objective.
--
-- Also holds three more views, as real tabs: Buildings (one line per claimed
-- building with the reason it is not yet banked), Livestock (the four stages
-- and the last census), and Journal (the log itself).
--
-- Tabs are an ISTabPanel with one child list per view. An earlier version used
-- a single button cycling through the views over one shared list, and that is
-- exactly the shape that lets one view paint over another - nothing guarantees
-- the previous view's rows are gone. Do not go back to it.
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

-- The list paints a scrollbar down its right edge. Right-aligned text that
-- measures against the full width slides underneath it and gets clipped, which
-- is what turned "could not read the ground" into "could not rea".
local SCROLLBAR_W = 14

-- How often the open journal re-surveys, in real milliseconds. Two seconds is
-- fast enough that walking into a building updates its row while you are still
-- standing there, and slow enough that the survey is not competing with the
-- frame. It only runs while the window is open.
local POLL_MS = 2000

-- Size. Read from the same player preference the crew badge uses, so one choice
-- drives the badge, this window and its buttons together
-- (TwoManCrew_PanelPrefs.lua, SCALES).
function TwoManCrewJournalWindow:step()
	local prefs = TwoManCrew.Prefs and TwoManCrew.Prefs.get and TwoManCrew.Prefs.get()
	return (prefs and prefs.journalStep) or 1
end

-- Chrome multiplier for this window. Paired with the font below by the size
-- table, so a bigger step grows the boxes and the words by the same jump - the
-- mismatch between a continuous multiplier and a stepped font is what made the
-- buttons outgrow the text.
function TwoManCrewJournalWindow:scale()
	local _, chrome = TwoManCrew.Prefs.size(self:step())
	return chrome or 1.0
end

-- The engine has a fixed set of fonts, so text cannot scale continuously the
-- way a rectangle can. Pick the largest font the current size justifies; the
-- rest of the layout is measured from it, never from a constant.
function TwoManCrewJournalWindow:font()
	local font = TwoManCrew.Prefs.size(self:step())
	return font or UIFont.NewSmall
end

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

	-- The base class paints its title bar and body from these two tables
	-- (ISCollapsableWindow.lua:152-166 and :179-197), so restyling the chrome is
	-- an assignment rather than a fight with the parent class. Slightly
	-- translucent, because this window opens over a live game view.
	self.backgroundColor = { r = SKIN.ground.r, g = SKIN.ground.g, b = SKIN.ground.b, a = 0.95 }
	self.borderColor = { r = SKIN.ruleLit.r, g = SKIN.ruleLit.g, b = SKIN.ruleLit.b, a = 1 }

	local top = self:titleBarHeight() + PAD

	self.claimLabel = nil

	self.list = ISScrollingListBox:new(PAD, top + ROW, self.width - PAD * 2, ROW)
	self.list:initialise()
	self.list:instantiate()
	-- Compact font so a full claim fits without reaching for the scroll wheel.
	-- setFont sets the font, its height and the row height together
	-- (client/ISUI/ISScrollingListBox.lua:703-708), so ROW must not be assigned
	-- to itemheight after this - the list owns row height now. Vanilla drives
	-- list boxes the same way at
	-- client/DebugUIs/DebugMenu/GlobalModData/GlobalModData.lua:42.
	self.list:setFont(self:font(), 1)
	self.list.selected = -1
	self.list.drawBorder = true

	-- Three more lists, one per remaining tab, built exactly like the Orders
	-- list above. addView re-parents them, so none is added to the window here.
	local function makeList()
		local l = ISScrollingListBox:new(0, 0, self.width - PAD * 2, ROW)
		l:initialise()
		l:instantiate()
		l:setFont(self:font(), 1)
		l.selected = -1
		l.drawBorder = true
		return l
	end

	self.buildingsList = makeList()
	self.livestockList = makeList()
	self.journalList = makeList()

	-- Four named views, replacing one button that cycled through three states.
	-- The old button's third state was undiscoverable: reaching Buildings meant
	-- pressing until it appeared, and nothing on screen said how many presses
	-- there were. Tabs name themselves and are one click each.
	--
	-- Verified: ISTabPanel:new at ISTabPanel.lua:614, addView at :484 (it sets
	-- the view's y to tabHeight, re-parents it, and shows only the first),
	-- activateView at :438, setEqualTabWidth at :535. Vanilla drives it the
	-- same way at ISChat.lua:830 and ISFluidDebugWindow.lua:55-67.
	self.tabs = ISTabPanel:new(PAD, top + ROW, self.width - PAD * 2, ROW)
	self.tabs:initialise()
	self.tabs:setEqualTabWidth(true)
	self:addChild(self.tabs)

	self.tabs:addView("Orders", self.list)
	self.tabs:addView("Buildings", self.buildingsList)
	self.tabs:addView("Livestock", self.livestockList)
	self.tabs:addView("Journal", self.journalList)

	-- Briefing rows are painted by this window (ISScrollingListBox.lua:304).
	-- Rows carrying a plain string - the "no claim yet" placeholders - fall
	-- through to the stock renderer, so an empty state cannot break the panel.
	--
	-- Nothing here is clickable. The briefing is read, not operated: it used to
	-- be cards you clicked open, and needing a click to find out what to do is
	-- the opposite of the point.
	local window = self
	self.list.doDrawItem = function(listSelf, y, item, alt)
		if item and item.item and item.item.kind then
			return window.drawBriefingRow(window, y, item, alt)
		end
		return ISScrollingListBox.doDrawItem(listSelf, y, item, alt)
	end

	-- The Orders list is NOT added to the window. ISTabPanel:addView already
	-- adopts it (ISTabPanel.lua:484 calls addChild and sets view.parent), and
	-- adding it here as well gave it two parents: the window drew it a second
	-- time, at window-relative 0,0, straight over the tab strip. That is why
	-- the tabs were invisible, the rows started in the top-left corner, and
	-- every right-aligned reason ran off the edge of the panel.

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
		TwoManCrewJournalWindow.onRefreshPressed
	)

	self.claimButton = self:makeIconButton(
		"Claim", "media/ui/TwoManCrew_Claim.png",
		"Claim a block - the server surveys and assigns your campaign",
		TwoManCrewJournalWindow.onClaim
	)

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
	-- Re-apply the font on every layout, not just at construction. setFont sets
	-- the font, its height and the row height together
	-- (ISScrollingListBox.lua:703-708), so this is what makes a size change
	-- actually reach the lists rather than only the buttons.
	local font = self:font()
	for _, list in ipairs({ self.list, self.buildingsList, self.livestockList, self.journalList }) do
		if list then list:setFont(font, 1) end
	end
	local top = self:titleBarHeight() + PAD

	-- The bottom strip belongs to the resize widgets (ISCollapsableWindow.lua:34-49
	-- creates a corner widget and a full-width bottom widget, both rh tall) and to
	-- the status bar the base render() paints over it (ISCollapsableWindow.lua:185-191).
	-- Placing the button row at height-ROW-PAD put it on top of that strip, so the
	-- bottom of every button was overdrawn and the bottom edge swallowed the clicks.
	-- Reserve the strip and sit the buttons above it.
	local rh = self.resizable and self:resizeWidgetHeight() or 0
	local buttonsY = self.height - rh - math.floor(BUTTON_H * self:scale()) - PAD

	-- List stops above the button row, never behind it.
	local listY = top + ROW
	local listH = buttonsY - PAD - listY
	if listH < ROW then listH = ROW end

	-- The tab panel now owns the content area; the lists are its children and
	-- are sized relative to it, not to the window. Positioning the panel and
	-- then each view keeps layout() the single owner of geometry, which is what
	-- stopped the list from covering the button row in the first place.
	self.tabs:setX(PAD)
	self.tabs:setY(listY)
	self.tabs:setWidth(self.width - PAD * 2)
	self.tabs:setHeight(listH)

	local innerH = listH - self.tabs.tabHeight
	if innerH < ROW then innerH = ROW end

	for _, viewObject in ipairs(self.tabs.viewList) do
		viewObject.view:setX(0)
		viewObject.view:setY(self.tabs.tabHeight)
		viewObject.view:setWidth(self.width - PAD * 2)
		viewObject.view:setHeight(innerH)
	end

	-- Icon buttons keep their square size and group at the left, rather than
	-- being stretched to share the full width. Three text buttons had to
	-- stretch because their labels needed the room; three icons stretched to
	-- a third of a wide window each would just be three small pictures
	-- marooned in the middle of large empty rectangles.
	-- Buttons take their size from the same preference as everything else, so
	-- "the icons are tiny" is fixed by picking a bigger number once rather than
	-- by editing a constant in here.
	local scale = self:scale()
	local buttonSize = math.floor(BUTTON_W * scale)
	local iconSize = math.floor(ICON * scale)

	local buttons = { self.refreshButton, self.claimButton }
	local gap = 6

	local x = PAD
	for i = 1, #buttons do
		buttons[i]:setX(x)
		buttons[i]:setY(buttonsY)
		buttons[i]:setWidth(buttonSize)
		buttons[i]:setHeight(buttonSize)
		if buttons[i].image then
			buttons[i].forcedWidthImage = iconSize
			buttons[i].forcedHeightImage = iconSize
		end
		x = x + buttonSize + gap
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
-- What the Refresh BUTTON does: everything onRefresh does, plus a full rescan
-- of the claim.
--
-- These are deliberately two functions. recheckClaim() walks every building on
-- the claim, and in singleplayer the "server" runs on the main thread, so the
-- survey costs a visible hitch. That is fine when a player asks for it and not
-- fine on a timer or on every window open - this window opens with onRefresh,
-- which is why the survey does not live in there.
function TwoManCrewJournalWindow:onRefreshPressed()
	self:onRefresh()
	self:onCheckRestoration()
end

-- Asks the server for fresh data and repaints. Cheap: three requests and a
-- couple of nils. Safe to call on open.
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
-- (it fired on entering the Buildings view). Kept because it is the only
-- on-demand rescan entry point,
-- and without it the server's requestRestorationCheck handler would have no
-- caller at all.
-- Asks the server to re-survey the claim, without telling the player.
--
-- The open window polls this, so the announced version below would put
-- "Checking the claim..." over the screen every two seconds. Announce a survey
-- the player asked for; stay quiet about the ones the panel runs for itself.
function TwoManCrewJournalWindow:requestSurvey()
	local player = getPlayer()
	if not player then return end
	TwoManCrew.requestFromServer(player, "requestRestorationCheck", {})
end

-- The announced survey, for an explicit press.
function TwoManCrewJournalWindow:onCheckRestoration()
	local player = getPlayer()
	if not player then return end

	self:requestSurvey()
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

-- Rebuilds the list from the last server reply. Newest first, because the last
-- thing that happened is the thing you want to read.
function TwoManCrewJournalWindow:populateJournal()
	local report = TwoManCrew.Client and TwoManCrew.Client.lastReport
	self.journalList:clear()

	if not report or not report.journal or #report.journal == 0 then
		self.journalList:addItem("Nothing recorded yet - go and do some work.", nil)
		return
	end

	local journal = report.journal
	for i = #journal, 1, -1 do
		local entry = journal[i]
		if entry and entry.text then
			local day = entry.worldAgeHours and math.floor(entry.worldAgeHours / 24) or 0
			local who = entry.playerName or "someone"
			self.journalList:addItem("Day " .. day .. "  -  " .. who .. " " .. entry.text, entry)
		end
	end
end

-- The Orders briefing.
--
-- This replaced a set of click-to-expand cards that printed the database: raw
-- building ids, world coordinates and an internal work score. The verdict was
-- "nothing is intuitive for a human, more for a machine", and it was right -
-- none of those three things is something a player can act on.
--
-- What a player needs is where to walk and what to do when they arrive, so
-- every number is translated before it is shown:
--   a coordinate pair  -> a direction and a distance from where they stand
--   a work score       -> a size, because the score is roughly a room count
--   a status flag      -> a sentence
--
-- Nothing here is clickable. It is read top to bottom, in three categories,
-- each with sub-categories under it.

-- Row kinds, in the order they indent.
local ROW_HEAD = "head"   -- CATEGORY
local ROW_SUB = "sub"     -- sub-category
local ROW_TASK = "task"   -- the thing to actually do
local ROW_NOTE = "note"   -- why, or what is missing
local ROW_BAR = "bar"     -- a labelled progress ladder
local ROW_GAP = "gap"

local INDENT = { head = 0, sub = 10, task = 20, note = 32, bar = 20, gap = 0 }

-- Compass bearing from the crew to a point. PZ's y axis grows southward, so
-- north is NEGATIVE dy - getting that backwards sends the player the wrong way,
-- which is worse than showing nothing.
local function bearing(dx, dy)
	local ns, ew = "", ""
	if dy < -8 then ns = "north" elseif dy > 8 then ns = "south" end
	if dx > 8 then ew = "east" elseif dx < -8 then ew = "west" end
	if ns == "" and ew == "" then return "right here" end
	return ns .. ew
end

-- "90 tiles west", or "right here" when standing on it.
function TwoManCrewJournalWindow.whereIs(row, px, py)
	if type(row.x) ~= "number" or type(row.y) ~= "number" then return nil end
	if type(px) ~= "number" or type(py) ~= "number" then return nil end

	local dx, dy = row.x - px, row.y - py
	local dist = math.floor(math.sqrt(dx * dx + dy * dy))
	local where = bearing(dx, dy)
	if where == "right here" then return "right here" end
	return dist .. " tiles " .. where
end

-- The work score is roughly one point per room plus one per large floor span,
-- so it reads as a size rather than as a number nobody can picture.
function TwoManCrewJournalWindow.describeSize(units)
	units = tonumber(units) or 0
	if units <= 1 then return "shed" end
	if units <= 3 then return "small house" end
	if units <= 7 then return "house" end
	if units <= 14 then return "large house" end
	return "big building"
end

-- One building, named the way a person would: size first, then where it is.
local function nameBuilding(row, px, py)
	local name = TwoManCrewJournalWindow.describeSize(row.units)
	local where = TwoManCrewJournalWindow.whereIs(row, px, py)
	if where then return name .. ", " .. where end
	return name
end

-- Builds the whole briefing as a flat list of typed rows.
--
-- Pure: takes the two server payloads and the crew's position, returns rows.
-- No engine call, no drawing, so the wording can be reasoned about on its own.
function TwoManCrewJournalWindow.buildBriefing(progress, detail, px, py)
	local rows = {}
	local function add(kind, text, tone)
		table.insert(rows, { kind = kind, text = text, tone = tone })
	end

	progress = progress or {}
	detail = detail or {}

	-- Sort the buildings that still need work by distance, so the first thing
	-- named is the one worth walking to.
	local todo, unreadable, doneCount = {}, {}, 0
	for _, row in ipairs(detail) do
		if row.status == "restored" then
			doneCount = doneCount + 1
		elseif row.status == "unknown" then
			table.insert(unreadable, row)
		else
			table.insert(todo, row)
		end
	end

	local function byDistance(a, b)
		local function d(r)
			if type(r.x) ~= "number" or type(px) ~= "number" then return 1e9 end
			local dx, dy = r.x - px, r.y - py
			return dx * dx + dy * dy
		end
		return d(a) < d(b)
	end
	table.sort(todo, byDistance)
	table.sort(unreadable, byDistance)

	-- ---------------------------------------------------------- DO THIS NOW
	add(ROW_HEAD, "DO THIS NOW")

	local anything = false

	if #todo > 0 then
		anything = true
		add(ROW_SUB, "Buildings")
		local first = todo[1]
		add(ROW_TASK, "Restore the " .. nameBuilding(first, px, py))
		local why = TwoManCrewJournalWindow.describeRow(first)
		if why then add(ROW_NOTE, why) end
		if #todo > 1 then
			add(ROW_NOTE, (#todo - 1) .. " more still need work after that")
		end
	elseif type(progress.buildingRemaining) == "string" and progress.buildingRemaining ~= "" then
		anything = true
		add(ROW_SUB, "Buildings")
		add(ROW_TASK, progress.buildingRemaining)
	end

	if type(progress.livestockRemaining) == "string" and progress.livestockRemaining ~= "" then
		anything = true
		add(ROW_SUB, "Livestock")
		add(ROW_TASK, progress.livestockRemaining)

		-- Say what the census actually saw, in a sentence rather than as four
		-- separate counters the player has to interpret.
		local animals = progress.censusAnimals
		local hutches = progress.censusHutches
		if type(animals) == "number" and animals > 0 and (hutches or 0) == 0 then
			add(ROW_NOTE, animals .. " animals nearby and nowhere to house them")
		elseif type(animals) == "number" and animals == 0 then
			add(ROW_NOTE, "no animals nearby yet")
		end
	end

	if not anything then
		add(ROW_TASK, "Nothing left. Hold the block.")
	end

	-- ---------------------------------------------------------- PROGRESS
	add(ROW_GAP, "")
	add(ROW_HEAD, "PROGRESS")

	add(ROW_SUB, "Buildings")
	add(ROW_BAR, doneCount .. " of " .. #detail .. " restored", {
		done = doneCount, target = #detail,
	})
	local tier = progress.buildingTier
	if tier and BUILDING_TIERS[tier] then
		add(ROW_NOTE, "Tier " .. tier .. " of 5, " .. BUILDING_TIERS[tier].label)
	end

	add(ROW_SUB, "Livestock")
	local stage = progress.livestockStage or 0
	add(ROW_BAR, "stage " .. stage .. " of 4", { done = stage, target = 4 })
	if LIVESTOCK_STAGES[stage] then
		add(ROW_NOTE, LIVESTOCK_STAGES[stage].label)
	end

	-- ---------------------------------------------------------- BLOCKED
	if #unreadable > 0 then
		add(ROW_GAP, "")
		add(ROW_HEAD, "CANNOT CHECK YET")
		add(ROW_SUB, "Too far to inspect")
		for i = 1, math.min(#unreadable, 4) do
			add(ROW_NOTE, nameBuilding(unreadable[i], px, py))
		end
		if #unreadable > 4 then
			add(ROW_NOTE, "and " .. (#unreadable - 4) .. " more")
		end
	end

	return rows
end

-- Colour per row kind. Only the task lines are bright; everything else recedes,
-- so the eye lands on the thing to go and do.
local ROW_COLOUR = {
	head = SKIN.active,
	sub = SKIN.dim,
	task = SKIN.text,
	note = SKIN.faint,
	bar = SKIN.dim,
	gap = SKIN.faint,
}

-- Draws one briefing row. Returns the next row's y, which is the contract the
-- list uses to set item.height (ISScrollingListBox.lua:533).
function TwoManCrewJournalWindow:drawBriefingRow(y, item, alt)
	local row = item and item.item
	local font = self:font()
	local lineH = getTextManager():getFontHeight(font)
	local scale = self:scale()
	local pad = math.floor(3 * scale)
	local height = lineH + pad

	if not row then
		item.height = height
		return y + height
	end

	if row.kind == ROW_GAP then
		height = math.floor(lineH * 0.5)
		item.height = height
		return y + height
	end

	local w = (self.list and self.list:getWidth() or self.width) - SCROLLBAR_W
	local x = CARD_PAD + math.floor((INDENT[row.kind] or 0) * scale)
	local c = ROW_COLOUR[row.kind] or SKIN.text

	if row.kind == ROW_HEAD then
		-- A category gets a little air above it and a rule beneath, so the three
		-- sections separate without any box drawing.
		height = lineH + math.floor(7 * scale)
		self:drawText(row.text, x, y, c.r, c.g, c.b, 1, font)
		self:drawRect(x, y + lineH + math.floor(2 * scale), w - x - CARD_PAD, 1,
			1, SKIN.rule.r, SKIN.rule.g, SKIN.rule.b)

	elseif row.kind == ROW_BAR then
		-- Label on the left, ladder filling the rest. One cell per building or
		-- stage, because these counts are small enough to count.
		local labelW = getTextManager():MeasureStringX(font, row.text)
		self:drawText(row.text, x, y, c.r, c.g, c.b, 1, font)

		local tone = row.tone or {}
		local target = tone.target or 0
		local done = tone.done or 0
		local barX = x + labelW + math.floor(12 * scale)
		local barW = w - barX - CARD_PAD
		local barH = math.floor(LADDER_H * scale)
		local barY = y + math.floor((lineH - barH) / 2)

		if target > 0 and barW > 20 then
			local gap = 2
			local cellW = (barW - (target - 1) * gap) / target
			for i = 1, target do
				local cx = barX + (i - 1) * (cellW + gap)
				local cc = (i <= done) and SKIN.done or SKIN.ground
				self:drawRect(cx, barY, cellW, barH, 1, cc.r, cc.g, cc.b)
				self:drawRectBorder(cx, barY, cellW, barH, 1,
					SKIN.ruleLit.r, SKIN.ruleLit.g, SKIN.ruleLit.b)
			end
		end

	else
		local prefix = ""
		if row.kind == ROW_TASK then prefix = "> " end
		self:drawText(
			TwoManCrewJournalWindow.fit(prefix .. row.text, w - x - CARD_PAD, font),
			x, y, c.r, c.g, c.b, 1, font)
	end

	item.height = height
	return y + height
end

-- Rebuilds the Orders briefing from the last server reply.
--
-- Everything the old card version showed is still here, but as prose a player
-- can act on rather than as ids, coordinates and an internal score.
function TwoManCrewJournalWindow:populateCampaign()
	local progress = TwoManCrew.Client and TwoManCrew.Client.lastTierProgress
	local received = TwoManCrew.Client and TwoManCrew.Client.tierProgressReceived
	local detail = TwoManCrew.Client and TwoManCrew.Client.lastClaimDetail

	self.list:clear()

	if not received then
		self.list:addItem("Requesting campaign progress...", nil)
		return
	end
	if not progress then
		self.list:addItem("No claim yet - press the flag button to claim a block.", nil)
		return
	end

	-- The crew's own position, so every building can be given a direction and a
	-- distance instead of a coordinate pair. Nil is handled: the briefing simply
	-- omits the "where" rather than printing a wrong one.
	local player = getPlayer()
	local px, py
	if player then px, py = player:getX(), player:getY() end

	for _, row in ipairs(TwoManCrewJournalWindow.buildBriefing(progress, detail, px, py)) do
		self.list:addItem(row.text or "", row)
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
	self.buildingsList:clear()

	if not received then
		self.buildingsList:addItem("Asking the server...", nil)
		return
	end
	if not detail or #detail == 0 then
		self.buildingsList:addItem("No claim yet - press Claim a block.", nil)
		return
	end

	local done = 0
	for _, row in ipairs(detail) do
		if row.status == "restored" then done = done + 1 end
	end
	self.buildingsList:addItem(string.format("-- %d of %d restored --", done, #detail), nil)

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

		self.buildingsList:addItem(line, row)
	end
end

-- Fills the Livestock tab: the four stages and what the last census saw.
--
-- The Orders tab carries the single next livestock task; this is the whole
-- track, so a crew can see which stage they are on and what the game actually
-- counted. A census that never ran reads as "not counted yet", never as zero -
-- the same distinction the cards draw as an unknown mark.
function TwoManCrewJournalWindow:populateLivestock()
	local progress = TwoManCrew.Client and TwoManCrew.Client.lastTierProgress
	self.livestockList:clear()

	if not progress then
		self.livestockList:addItem("No claim yet - press the flag button.", nil)
		return
	end

	local stage = progress.livestockStage or 0
	for i, entry in ipairs(LIVESTOCK_STAGES) do
		local mark = "..."
		if i < stage then
			mark = "done"
		elseif i == stage then
			mark = "now"
		end
		self.livestockList:addItem(
			string.format("[%s] %s: %s", mark, entry.key, entry.label), entry)
	end

	local function countLine(label, value)
		if type(value) ~= "number" then
			return label .. ": not counted yet"
		end
		return label .. ": " .. value
	end

	self.livestockList:addItem(countLine("Animals nearby", progress.censusAnimals), nil)
	self.livestockList:addItem(countLine("Young animals", progress.censusBabies), nil)
	self.livestockList:addItem(countLine("Occupied hutches", progress.censusHutches), nil)
	self.livestockList:addItem(countLine("Feeding troughs", progress.censusTroughs), nil)

	if type(progress.herdNightsDone) == "number"
		and type(progress.herdNightsNeeded) == "number"
	then
		self.livestockList:addItem(string.format(
			"Herd held: %d of %d nights",
			progress.herdNightsDone, progress.herdNightsNeeded), nil)
	end
end

-- Fills every tab. The tab panel decides which one is visible, so all four are
-- kept current rather than rebuilt on switch - a switch is now a click on a
-- widget this window never hears about.
function TwoManCrewJournalWindow:populate()
	self:populateCampaign()
	self:populateBuildings()
	self:populateLivestock()
	self:populateJournal()
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

	-- One amber rule under the title, doubled with a dark line beneath it. It is
	-- the single bright horizontal in the window, and it is what makes the panel
	-- read as a work order posted on a wall rather than as a system dialog.
	--
	-- drawRect takes alpha BEFORE the rgb triplet (ISUIElement.lua:1191). The
	-- drawText calls below take it LAST. That inconsistency is the engine's, not
	-- a typo here.
	local ruleY = self:titleBarHeight()
	self:drawRect(0, ruleY, self.width, 1, 1, SKIN.active.r, SKIN.active.g, SKIN.active.b)
	self:drawRect(0, ruleY + 1, self.width, 1, 1, SKIN.rule.r, SKIN.rule.g, SKIN.rule.b)

	-- The size can be changed from the crew badge's menu while this window is
	-- open. Nothing tells the window about it, so notice the change here and
	-- lay out again; without this the new size only appeared after a resize.
	local scaleNow = self:scale()
	if self.lastScale ~= scaleNow then
		self.lastScale = scaleNow
		self:layout()
		self:populate()
	end

	-- Keep the panel live while it is open.
	--
	-- Every per-building verdict is a snapshot: "nobody here - stand inside"
	-- stays on screen until something re-surveys, so walking into the building
	-- changed nothing and the panel looked broken. It was not stale data, it
	-- was no new data at all.
	--
	-- The survey is the expensive call, so it is throttled rather than run per
	-- frame, and only while the window is actually on screen. Closed, this
	-- costs nothing.
	local nowMs = getTimestampMs()
	if not self.nextPollMs or nowMs >= self.nextPollMs then
		self.nextPollMs = nowMs + POLL_MS
		if TwoManCrew.Client and TwoManCrew.Client.requestClaimDetail then
			TwoManCrew.Client.requestClaimDetail(getPlayer())
		end
		if TwoManCrew.Client and TwoManCrew.Client.requestTierProgress then
			TwoManCrew.Client.requestTierProgress(getPlayer())
		end
		self:requestSurvey()
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
		self:drawText(text, PAD, y, SKIN.active.r, SKIN.active.g, SKIN.active.b, 1, UIFont.Small)
	elseif refusal then
		-- The server surveyed and said no. Kept on screen rather than left to
		-- the halo text that fades: a player who presses claim and sees only
		-- a vanishing message reads the button as broken, which is what was
		-- reported. Amber, because it is an answer and not an error.
		self:drawText("No claim: " .. refusal, PAD, y, SKIN.blocked.r, SKIN.blocked.g, SKIN.blocked.b, 1, UIFont.Small)
	else
		-- The button says "Claim" now, not "Claim a block", so the hint names
		-- the icon by its tooltip word rather than a label that no longer exists.
		self:drawText("No claim yet - press the flag button", PAD, y, SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.Small)
	end

	-- Refresh acknowledgement. A crew with an empty journal saw the list
	-- redraw the identical "nothing recorded yet" line and concluded the
	-- button was dead - the request had in fact gone out and been answered.
	-- Flashing a short confirmation makes the round trip visible whether or
	-- not the contents changed, which is the only thing the button was
	-- missing. Timer counts down in real milliseconds, same clock the crew
	-- panel's own refresh uses.
	if self.refreshFlashMs and self.refreshFlashMs > 0 then
		self.refreshFlashMs = self.refreshFlashMs - UIManager.getMillisSinceLastRender()

		-- Right-aligned on the header line. It must not sit above the button
		-- row: that space belongs to the tab panel, which renders after this
		-- prerender as a child and would paint straight over the text. The
		-- header strip is the only band this window draws into directly.
		--
		-- This used to offset itself left of the view name. The tabs replaced
		-- that name, and the offset kept subtracting its width - a nil - which
		-- threw once per frame inside render and dragged the whole machine
		-- down. Nothing shares this line now, so it simply right-aligns.
		local label = "updated"
		local labelW = getTextManager():MeasureStringX(UIFont.Small, label)
		local labelX = self.width - PAD - labelW

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
-- Right click anywhere in the window opens its own size menu.
--
-- Deliberately separate from the badge's menu: the two surfaces store separate
-- steps, because one number driving both was the complaint. Set the badge from
-- the badge, and this window from this window.
function TwoManCrewJournalWindow:onRightMouseUp(x, y)
	local player = getPlayer()
	if not player then return end

	local context = ISContextMenu.get(0, self:getAbsoluteX() + x, self:getAbsoluteY() + y)
	local sizeOption = context:addOption("Journal size", self)
	local sizeMenu = context:getNew(context)
	context:addSubMenu(sizeOption, sizeMenu)

	local current = self:step()
	for i = 1, #TwoManCrew.Prefs.SIZES do
		local opt = sizeMenu:addOption(tostring(i), self, TwoManCrewJournalWindow.onSetStep, i)
		if i == current then
			sizeMenu:setOptionChecked(opt, true)
		end
	end
end

function TwoManCrewJournalWindow:onSetStep(step)
	TwoManCrew.Prefs.setJournalStep(getPlayer(), step)

	-- Drop the cards so their heights are rebuilt at the new font, and lay out
	-- again rather than waiting for a resize.
	self:layout()
end

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
