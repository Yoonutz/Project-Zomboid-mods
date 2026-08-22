-- TwoManCrew_CrewPanel.lua (client)
--
-- Always-visible crew status widget. Replaces the report keybind: status you
-- glance at beats status you have to ask for, which is why the moodle idea was
-- the right instinct even though a real moodle is impossible (the MoodleType
-- list is fixed in Java - mods cannot add an eleventh entry).
--
-- Shape: a badge, not a box. Collapsed, the widget is the crew icon and a
-- small status dot, drawn straight on the HUD with no background - which is
-- how vanilla's own always-on indicators read. The dark rectangle it used to
-- paint made it look like a debug overlay bolted onto the game. Hovering
-- expands it to the full text, and the panel paints its backing plate only
-- while expanded, so the box exists exactly as long as there is text needing
-- one and not a frame longer.
--
-- Lifecycle copied from the smallest vanilla floating element, ISAlert
-- (client/Chat/ISAlert.lua): derive ISUIElement, :new, :initialise,
-- :addToUIManager, :setVisible, created on Events.OnGameStart.
--
-- Drawing signatures verified in vanilla:
--   self:drawText(text, x, y, r, g, b, a, UIFont.X)
--     - client/Fishing/FishingDebugWindow.lua:64
--   self:drawRect(x, y, w, h, a, r, g, b)   <- alpha FIRST
--     - client/Fishing/TensionUI.lua:66
--   self:drawTextureScaled(tex, x, y, w, h, a, r, g, b)  <- alpha FIRST
--     - client/ISUI/ISUIElement.lua:1032
--   self:isMouseOver()  Java-backed, client/ISUI/ISUIElement.lua:414
--   getCore():getScreenWidth() / getScreenHeight()
--     - client/Chat/ISAlert.lua:33-34
--   getTextManager():MeasureStringX(font, text)
--     - client/ISUI/ISToolTip.lua, used to size the expanded plate to its text

require "ISUI/ISUIElement"
require "TwoManCrew/TwoManCrew_Config"
require "TwoManCrew/TwoManCrew_PanelPrefs"

TwoManCrewPanel = ISUIElement:derive("TwoManCrewPanel")


-- Size of the badge when the widget is collapsed to just its icon. Bigger
-- than the 16px title-bar variant, because collapsed it is the only thing
-- on screen carrying the mod's state and it has to survive a glance.
local BADGE = 22

-- Refresh cadence. The panel renders every frame, but it only recomputes
-- partner state on this interval - render must stay cheap.
local REFRESH_MS = 500

function TwoManCrewPanel:new(x, y, width, height)
	local o = ISUIElement:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self

	o.x = x
	o.y = y
	o.width = width
	o.height = height

	o.partnerName = nil
	o.refreshTimer = 0
	o.pressed = false
	o.canDrag = false
	o.dragMoved = false
	---@type table<string, number>|nil
	o.tally = nil
	--- Newest journal entry from the server's crewReport reply, or nil before
	--- the first reply arrives. Shape mirrors TwoManCrew_CrewState.addJournal.
	---@type { text: string, playerName: string, worldAgeHours: number }|nil
	o.lastJournal = nil

	-- Crew badge. Loaded once here rather than per frame, and nil-safe:
	-- getTexture returns nil for a missing file and every draw below skips on
	-- nil, so a packaging mistake costs the badge and not the widget.
	--
	-- This is the mod's own two-hard-hats art rather than the journal book:
	-- the book belongs to the journal window's title bar, and the widget is
	-- about the crew, so they are deliberately different icons from one set.
	o.badge = getTexture("media/ui/TwoManCrew_Crew.png")

	TwoManCrewPanel.instance = o
	return o
end

-- Recomputes partner presence and danger. Kept out of render so the per-frame
-- path stays allocation-free.
function TwoManCrewPanel:refresh()
	local player = getPlayer()
	if not player then
		self.partnerName = nil
		return
	end

	local partner = TwoManCrew.getPartner(player)
	if not partner then
		self.partnerName = nil
		return
	end

	self.partnerName = partner:getUsername()

	-- No local danger read here: getStats() on a remote IsoPlayer is not a
	-- verified-safe call on a dedicated server (see TwoManCrew_WatchMyBack.lua
	-- header comment - no vanilla call site reads another client's stats
	-- this way). TwoManCrew_WatchMyBack owns the danger warning end-to-end
	-- via the server, so this panel does not duplicate it.
end

-- Cached from the server's crewReport reply, so the panel shows real counts
-- rather than guessing. TwoManCrew_CrewReport stores the last reply.
function TwoManCrewPanel:pullCachedReport()
	local report = TwoManCrew.Client and TwoManCrew.Client.lastReport
	if not report then return end

	self.tally = report.tally
	self.lastJournal = report.journal and report.journal[#report.journal] or nil
end

-- Collapsed: the badge plus a status dot, no plate, no text. The dot is the
-- whole status read at a glance - green means the partner is beside you, grey
-- means working alone - so it is drawn last and sits proud of the badge's
-- bottom-right corner rather than inside it.
-- Draws the badge. That is the entire widget.
--
-- There used to be a hover state that expanded this into a text plate with the
-- partner, the crew tally and the latest journal line. It is gone at the
-- player's request: "Remove any hoover effect. Just let me click on the button
-- and open the journal."
--
-- Everything that plate showed is in the journal, one click away, which is
-- where someone actually reads it.
function TwoManCrewPanel:renderBadge(w, h)
	if self.badge then
		self:drawTextureScaled(self.badge, 0, 0, w, h, 1, 1, 1, 1)
	else
		-- No texture: fall back to a readable label rather than an empty
		-- widget the player cannot find or click.
		self:drawText("CREW", 0, 0, 0.85, 0.85, 0.85, 1, UIFont.Small)
	end

	-- No partner indicator. There used to be a small coloured square in the
	-- corner here, and the verdict on it was "remove the square for good".
	--
	-- Nothing is lost that is not said better elsewhere: hovering the badge
	-- already spells out "working alone" or the partner's name in words, which
	-- is legible in a way a six-pixel dot never was.

end

-- Expanded: the badge on the header row and the full status text, over a
-- backing plate. The plate is drawn here and only here, which is what keeps
-- the collapsed widget free of the box the player asked to be rid of.
function TwoManCrewPanel:prerender()
	local prefs = TwoManCrew.Prefs.get()
	local w = prefs.badgeW or 32
	local h = prefs.badgeH or 32

	-- The widget IS the badge now, so the hitbox is the icon.
	--
	-- It used to stay permanently at the width the hover plate needed, which
	-- left a large invisible rectangle that opened the journal when clicked. The
	-- fixed size existed to stop the panel oscillating as the pointer crossed
	-- its edge while expanding; with no expansion there is nothing to oscillate.
	--
	-- Size still goes through the setters, never the raw fields: PZ hit-tests
	-- against the Java object and only these reach it.
	if self.width ~= w then self:setWidth(w) end
	if self.height ~= h then self:setHeight(h) end

	self:renderBadge(w, h)
end

function TwoManCrewPanel:initialise()
	ISUIElement.initialise(self)
end

-- The whole panel is the button. Clicking it opens the crew journal, which is
-- where the campaign claim and the full log live. No keybind to remember.
--
-- ISUIElement:new sets wantMouseEvents = true by default (client/ISUI/
-- ISUIElement.lua:1998), and :instantiate() wires that straight into
-- self.javaObject:setConsumeMouseEvents(...) (ISUIElement.lua:1004) when
-- addToUIManager() creates the Java-side element. Nothing here overrides
-- that default, so this element already receives mouse events without any
-- extra setCapture/setConsumeMouseEvents call. onMouseDown/onMouseUp below
-- override the base ISUIElement no-op implementations (ISUIElement.lua:
-- 1509-1538) the same way client/ISUI/ISButton.lua does on ISPanel.
--
-- isMouseOver is intentionally NOT overridden: the base ISUIElement version
-- (ISUIElement.lua:414, self.javaObject:isMouseOver()) is Java-backed and
-- already correct. A prior override here read self.mouseOver, a field this
-- file never set, which would have always returned nil/false. The hover
-- expand in prerender depends on that base version being the real one.
--
-- Left click either drags the panel or opens the journal. Which one is decided
-- on mouse-up: if the pointer moved while held, it was a drag, otherwise it was
-- a click. That avoids a modifier key and avoids opening the journal every time
-- you reposition the panel.
-- A locked panel must still OPEN the journal - locking is about not moving the
-- panel by accident, not about disabling it. The click is therefore always
-- tracked; `canDrag` is what locking turns off. Previously locking left
-- dragging false, and since the journal opened only from the `dragging`
-- branch of onMouseUp, a locked panel made the journal permanently
-- unreachable (it is the mod's only opener).
function TwoManCrewPanel:onMouseDown(x, y)
	local prefs = TwoManCrew.Prefs.get(getPlayer())

	self.pressed = true
	self.canDrag = not prefs.locked
	self.dragMoved = false
	self.dragOffsetX = x
	self.dragOffsetY = y
	return true
end

function TwoManCrewPanel:onMouseMove(dx, dy)
	self:dragBy(dx, dy)
end

-- A fast drag outruns the widget: the pointer leaves the element's rectangle
-- and PZ starts delivering onMouseMoveOutside instead of onMouseMove. Without
-- this the panel stopped following the mouse the moment that happened, which
-- is the "I keep my mouse down and drag and it snaps out" report - motion was
-- simply no longer being delivered anywhere.
--
-- Vanilla handles it by implementing the SAME movement in both handlers
-- (ISCollapsableWindow.lua:206-236), which is what this mirrors.
function TwoManCrewPanel:onMouseMoveOutside(dx, dy)
	self:dragBy(dx, dy)
end

-- One drag implementation, called from both move handlers so they can never
-- drift apart.
function TwoManCrewPanel:dragBy(dx, dy)
	if not self.pressed or not self.canDrag then return end
	if dx == 0 and dy == 0 then return end

	self.dragMoved = true
	self:setX(self:getX() + dx)
	self:setY(self:getY() + dy)
end

function TwoManCrewPanel:onMouseUp(x, y)
	if self.pressed and self.dragMoved then
		-- Drag finished: persist where it landed, clamped back on screen so a
		-- panel dragged off the edge is not lost on next login. Clamped against
		-- the element's real size, which is now always the expanded one - the
		-- widget no longer resizes, so there is no second size to choose from.
		local player = getPlayer()
		local prefs = TwoManCrew.Prefs.get(player)
		prefs.x = self:getX()
		prefs.y = self:getY()
		TwoManCrew.Prefs.clampToScreen(prefs, self.width, self.height)
		self:setX(prefs.x)
		self:setY(prefs.y)
	elseif self.pressed and TwoManCrewJournalWindow and TwoManCrewJournalWindow.toggle then
		-- Click without movement, locked or not: open the journal.
		TwoManCrewJournalWindow.toggle()
	end

	self.pressed = false
	self.canDrag = false
	self.dragMoved = false
	return true
end

-- Releasing the button while the pointer is outside the element still ends a
-- real drag, so it has to SAVE where the panel landed rather than just drop
-- the state. Previously this threw the position away, so a drag that finished
-- with the cursor off the widget - which is most of them, since a fast drag
-- leaves the rectangle - was forgotten by the next login.
--
-- It deliberately does not open the journal: a release outside the element is
-- never a click on it.
function TwoManCrewPanel:onMouseUpOutside(x, y)
	if self.pressed and self.dragMoved then
		local prefs = TwoManCrew.Prefs.get(getPlayer())
		prefs.x = self:getX()
		prefs.y = self:getY()
		TwoManCrew.Prefs.clampToScreen(prefs, self.width, self.height)
		self:setX(prefs.x)
		self:setY(prefs.y)
	end

	self.pressed = false
	self.canDrag = false
	self.dragMoved = false
	return true
end

-- Right click opens the settings menu: scale, what to show, lock, reset.
-- Pattern copied from vanilla's own HUD context menu (client/Chat/ISChat.lua:246
-- ISContextMenu.get + addOption + getNew/addSubMenu).
function TwoManCrewPanel:onRightMouseDown(x, y)
	self.lastMenuX = x
	self.lastMenuY = y
	local player = getPlayer()
	if not player then return true end

	local prefs = TwoManCrew.Prefs.get(player)
	local context = ISContextMenu.get(0, self:getAbsoluteX() + x, self:getAbsoluteY() + y)

	-- Sizes are numbered, not given as percentages. "125%" made the player do
	-- arithmetic to find out whether it was bigger than what they had; "3" does
	-- not. This one setting drives the badge, the journal window and the
	-- journal's buttons together, so picking a size here changes all of them.
	-- Size by increment, not by preset.
	--
	-- A fixed list of numbers means the size you want is whichever listed value
	-- is least wrong. These step from wherever you are, so the badge converges
	-- on the size you actually want, and the current pixels are on the label so
	-- you can see where you are.
	--
	-- The menu reopens after each press, so + + + is three clicks rather than
	-- three right-clicks. Deliberately NOT the mouse wheel: scrolling over the
	-- badge mid-game would resize it by accident.
	local sizeOption = context:addOption(
		string.format("Icon size: %d x %d", prefs.badgeW or 32, prefs.badgeH or 32), self)
	local sizeMenu = context:getNew(context)
	context:addSubMenu(sizeOption, sizeMenu)

	sizeMenu:addOption("-   smaller", self, TwoManCrewPanel.onStepSize, -1, -1)
	sizeMenu:addOption("+   bigger", self, TwoManCrewPanel.onStepSize, 1, 1)
	sizeMenu:addOption("-   narrower", self, TwoManCrewPanel.onStepSize, -1, 0)
	sizeMenu:addOption("+   wider", self, TwoManCrewPanel.onStepSize, 1, 0)
	sizeMenu:addOption("-   shorter", self, TwoManCrewPanel.onStepSize, 0, -1)
	sizeMenu:addOption("+   taller", self, TwoManCrewPanel.onStepSize, 0, 1)
	sizeMenu:addOption("Reset to 32 x 32", self, TwoManCrewPanel.onResetBadgeSize)

	local lockOpt = context:addOption("Lock position", self, TwoManCrewPanel.onToggle, "locked")
	context:setOptionChecked(lockOpt, prefs.locked)

	context:addOption("Reset panel", self, TwoManCrewPanel.onReset)

	-- Development convenience: reloads the journal window's Lua in place, so a
	-- UI change can be seen without leaving the save. Only that one file is
	-- safe to reload - every other file in this mod hooks a game event when it
	-- loads, and reloading one of those leaves the old hook running as well.
	context:addOption("Reload journal UI", self, TwoManCrewPanel.onReloadJournalUI)

	return true
end

-- Steps the badge by one increment on either axis.
--
-- dw and dh are -1, 0 or 1: which direction each axis moves, or not at all.
-- The step is proportional rather than a flat pixel count, so a press changes
-- the badge by the same visible amount whether it is small or large, and there
-- is no ceiling to run into.
function TwoManCrewPanel:onStepSize(dw, dh)
	local function factor(direction)
		if direction > 0 then return 1.15 end
		if direction < 0 then return 1 / 1.15 end
		return 1
	end

	TwoManCrew.Prefs.zoomBadge(getPlayer(), factor(dw), factor(dh))

	-- Reopen where it was, so repeated presses do not mean repeated
	-- right-clicks. Without this, "+" is a four-action loop every time.
	self:onRightMouseDown(self.lastMenuX or 0, self.lastMenuY or 0)
end

function TwoManCrewPanel:onResetBadgeSize()
	local prefs = TwoManCrew.Prefs.get(getPlayer())
	prefs.badgeW = 32
	prefs.badgeH = 32
end

function TwoManCrewPanel:onToggle(field)
	TwoManCrew.Prefs.toggle(getPlayer(), field)
	self:applyPrefs()
end

-- Reloads the journal window from disk, without restarting the game.
--
-- The open window MUST go first. reloadLuaFile re-executes the file, which
-- rebuilds the window's class table from scratch; anything still on screen
-- belongs to the old table and would keep rendering the old code forever while
-- the next open created a second window beside it.
function TwoManCrewPanel:onReloadJournalUI()
	if TwoManCrewJournalWindow then
		local open = TwoManCrewJournalWindow.instance
		if open then
			open:close()
			TwoManCrewJournalWindow.instance = nil
		end
	end

	-- The path is found rather than typed: getLoadedLua enumerates every loaded
	-- file, so a moved or renamed mod folder cannot break this.
	local reloaded = 0
	for i = 0, getLoadedLuaCount() - 1 do
		local path = getLoadedLua(i)
		-- Plain find with the pattern flag off: the path contains dots and
		-- dashes, which a Lua pattern would treat as wildcards.
		if path and string.find(path, "TwoManCrew_JournalWindow", 1, true) then
			reloadLuaFile(path)
			reloaded = reloaded + 1
		end
	end

	local player = getPlayer()
	if player then
		if reloaded > 0 then
			HaloTextHelper.addText(player, "Journal UI reloaded")
		else
			HaloTextHelper.addText(player, "Journal UI not found")
		end
	end
end

function TwoManCrewPanel:onReset()
	local prefs = TwoManCrew.Prefs.reset(getPlayer())
	self:setX(prefs.x)
	self:setY(prefs.y)
	self:applyPrefs()
end

-- Pushes saved preferences onto the live element. Called on setup and after any
-- menu change, so the panel reflects a choice immediately.
--
-- Size is NOT applied here: prerender reads the stored pixels every frame, so
-- a wheel notch shows up immediately without this having to run.
--
-- Nothing else is cached onto self any more. The three fields that used to be
-- (crew deeds, latest journal line, always-expanded) all configured the hover
-- plate, and that is gone.
function TwoManCrewPanel:applyPrefs()
	TwoManCrew.Prefs.get(getPlayer())
end

TwoManCrewPanel.setup = function()
	if TwoManCrewPanel.instance then return end

	-- Restore where the player last left it. Defaults put it top-left under the
	-- vanilla HUD, clear of the moodle stack on the right.
	-- Created at the stored badge size. prerender keeps it in step from there,
	-- through the setters, which is what reaches the Java hitbox.
	local prefs = TwoManCrew.Prefs.get(getPlayer())
	local startWidth = prefs.badgeW or 32
	local startHeight = prefs.badgeH or 32
	TwoManCrew.Prefs.clampToScreen(prefs, startWidth, startHeight)

	local panel = TwoManCrewPanel:new(prefs.x, prefs.y, startWidth, startHeight)
	panel:initialise()
	panel:addToUIManager()
	panel:setVisible(true)
	panel:applyPrefs()

	-- One report request at start so the counters are populated without the
	-- player having to ask. The panel refreshes them from the cached reply.
	if TwoManCrew.Client and TwoManCrew.Client.requestCrewReport then
		TwoManCrew.Client.requestCrewReport(getPlayer())
	end
end

Events.OnGameStart.Add(TwoManCrewPanel.setup)
