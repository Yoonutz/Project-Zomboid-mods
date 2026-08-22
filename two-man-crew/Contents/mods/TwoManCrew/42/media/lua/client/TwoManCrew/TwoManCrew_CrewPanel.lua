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

local PAD = 6
local LINE = 16
local WIDTH = 190

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
	-- True while the widget is showing its full text rather than just the
	-- badge. Driven by hover in prerender, forced on by the alwaysExpanded
	-- preference, and forced on while a drag is in progress so the thing
	-- being dragged does not change size under the cursor.
	o.expanded = false
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
function TwoManCrewPanel:renderCollapsed(scale)
	local size = math.floor(BADGE * scale)

	if self.badge then
		self:drawTextureScaled(self.badge, 0, 0, size, size, 1, 1, 1, 1)
	else
		-- No texture: fall back to a readable label rather than an empty
		-- widget the player cannot find or click.
		self:drawText("CREW", 0, 0, 0.85, 0.85, 0.85, 1, UIFont.Small)
	end

	local dot = math.max(4, math.floor(6 * scale))
	local dx = size - dot
	local dy = size - dot

	-- Dark ring first, coloured dot inside it, so the indicator stays legible
	-- against both a bright road and a dark interior. Two rects is cheaper
	-- than shipping another texture for a six-pixel dot.
	self:drawRect(dx - 1, dy - 1, dot + 2, dot + 2, 0.85, 0.05, 0.04, 0.03)
	if self.partnerName then
		self:drawRect(dx, dy, dot, dot, 1, 0.43, 0.69, 0.37)
	else
		self:drawRect(dx, dy, dot, dot, 1, 0.45, 0.45, 0.45)
	end
end

-- Expanded: the badge on the header row and the full status text, over a
-- backing plate. The plate is drawn here and only here, which is what keeps
-- the collapsed widget free of the box the player asked to be rid of.
function TwoManCrewPanel:renderExpanded(scale, pad, line)
	self:drawRect(0, 0, self.width, self.height, 0.55, 0.0, 0.0, 0.0)

	local y = pad

	-- Badge sits on the header row and scales with the panel, so the widget
	-- stays one piece at every size. The label shifts right by the badge width
	-- only when the badge actually drew; a missing texture leaves the original
	-- flush-left layout rather than an empty gap.
	local labelX = pad
	if self.badge then
		local badgeSize = line - 2
		self:drawTextureScaled(self.badge, pad, y, badgeSize, badgeSize, 1, 1, 1, 1)
		labelX = pad + badgeSize + math.floor(4 * scale)
	end

	self:drawText("CREW", labelX, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
	y = y + line

	-- Danger is not decided here: WatchMyBack owns that end-to-end via the
	-- server and delivers it as halo text, so this line only shows presence.
	if self.partnerName then
		self:drawText(self.partnerName .. " - nearby", pad, y, 0.5, 0.9, 0.5, 1, UIFont.Small)
	else
		self:drawText("working alone", pad, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
	end
	y = y + line

	if self.showTally ~= false and self.tally then
		local total = 0
		for _, n in pairs(self.tally) do
			total = total + n
		end
		self:drawText("crew deeds: " .. total, pad, y, 0.8, 0.8, 0.7, 1, UIFont.Small)
		y = y + line
	end

	-- Read the entry into a local before touching its fields, so the non-nil
	-- guarantee is visible at the point of use rather than several lines above.
	local entry = self.lastJournal
	if self.showJournal ~= false and entry and entry.text then
		local text = entry.text
		-- Wider panel fits more text, so the truncation point follows scale.
		local maxChars = math.floor(28 * scale)
		if #text > maxChars then text = string.sub(text, 1, maxChars - 1) .. "..." end
		self:drawText(text, pad, y, 0.65, 0.65, 0.6, 1, UIFont.Small)
	end
end

function TwoManCrewPanel:prerender()
	self.refreshTimer = self.refreshTimer - UIManager.getMillisSinceLastRender()
	if self.refreshTimer <= 0 then
		self.refreshTimer = REFRESH_MS
		self:refresh()
		self:pullCachedReport()
	end

	-- Scale multiplies the row height and padding so the whole widget grows,
	-- rather than only the box. Font stays vanilla-sized: PZ exposes a fixed
	-- set of UIFont values, so text cannot scale continuously.
	local scale = self.scale or 1.0
	local pad = math.floor(PAD * scale)
	local line = math.floor(LINE * scale)

	-- The element's SIZE never changes. Only what is drawn inside it does.
	--
	-- This is the whole fix for three separate bugs, and the reason the size
	-- is not recomputed per frame any more. Mouse hit-testing is done by the
	-- Java object, and the Java object only learns a new size through
	-- setWidth()/setHeight() (ISUIElement.lua:1136-1160, which forward to
	-- javaObject:setWidth/setHeight). Assigning self.width directly - which
	-- is what this function used to do on every frame - updates the Lua field
	-- that drawing reads while leaving Java's hitbox at whatever it was when
	-- the element was added to the UIManager.
	--
	-- With the widget starting collapsed, that stale hitbox was the 22px
	-- badge, permanently. Everything followed from that:
	--   - the expanded panel could not be clicked outside its top-left corner,
	--   - dragging "snapped out" the moment the pointer left those 22px,
	--     because PZ then delivered onMouseUpOutside and killed the drag,
	--   - and "Always show text" made it permanent rather than intermittent.
	--
	-- Keeping one fixed hitbox at the expanded size means Lua and Java can
	-- never disagree. The cost is that the collapsed badge reserves the full
	-- rectangle; that is invisible (nothing is painted there) and is worth far
	-- more than a pixel-tight hitbox that does not work.
	local lines = 2
	if self.showTally ~= false and self.tally then lines = lines + 1 end
	if self.showJournal ~= false and self.lastJournal then lines = lines + 1 end

	local wantWidth = math.floor(WIDTH * scale)
	local wantHeight = pad * 2 + line * lines

	-- Go through the setters, and only when the value actually changed, so
	-- Java is kept in step without a redundant call every frame.
	if self.width ~= wantWidth then self:setWidth(wantWidth) end
	if self.height ~= wantHeight then self:setHeight(wantHeight) end

	-- Hover now decides only what is PAINTED. isMouseOver() is the Java-backed
	-- base implementation (ISUIElement.lua:414) and is honest again now that
	-- the Java rectangle matches the real one.
	self.expanded = self.alwaysExpanded == true or self.pressed or self:isMouseOver()

	if self.expanded then
		self:renderExpanded(scale, pad, line)
	else
		self:renderCollapsed(scale)
	end
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
	local player = getPlayer()
	if not player then return true end

	local prefs = TwoManCrew.Prefs.get(player)
	local context = ISContextMenu.get(0, self:getAbsoluteX() + x, self:getAbsoluteY() + y)

	-- Sizes are numbered, not given as percentages. "125%" made the player do
	-- arithmetic to find out whether it was bigger than what they had; "3" does
	-- not. This one setting drives the badge, the journal window and the
	-- journal's buttons together, so picking a size here changes all of them.
	local sizeOption = context:addOption("Size", self)
	local sizeMenu = context:getNew(context)
	context:addSubMenu(sizeOption, sizeMenu)
	local current = TwoManCrew.Prefs.scaleStep(prefs.scale)
	for i = 1, #TwoManCrew.Prefs.SCALES do
		local scale = TwoManCrew.Prefs.SCALES[i]
		local opt = sizeMenu:addOption(tostring(i), self, TwoManCrewPanel.onSetScale, scale)
		if i == current then
			sizeMenu:setOptionChecked(opt, true)
		end
	end

	local expandOpt = context:addOption("Always show text", self, TwoManCrewPanel.onToggle, "alwaysExpanded")
	context:setOptionChecked(expandOpt, prefs.alwaysExpanded)

	local tallyOpt = context:addOption("Show crew deeds", self, TwoManCrewPanel.onToggle, "showTally")
	context:setOptionChecked(tallyOpt, prefs.showTally)

	local journalOpt = context:addOption("Show latest journal line", self, TwoManCrewPanel.onToggle, "showJournal")
	context:setOptionChecked(journalOpt, prefs.showJournal)

	local lockOpt = context:addOption("Lock position", self, TwoManCrewPanel.onToggle, "locked")
	context:setOptionChecked(lockOpt, prefs.locked)

	context:addOption("Reset panel", self, TwoManCrewPanel.onReset)

	return true
end

function TwoManCrewPanel:onSetScale(scale)
	TwoManCrew.Prefs.setScale(getPlayer(), scale)
	self:applyPrefs()
end

function TwoManCrewPanel:onToggle(field)
	TwoManCrew.Prefs.toggle(getPlayer(), field)
	self:applyPrefs()
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
-- Width is NOT set here any more: prerender owns it, because it differs
-- between the collapsed badge and the expanded plate and changes on hover.
-- Setting it here too would have the two fight for a frame on every toggle.
function TwoManCrewPanel:applyPrefs()
	local prefs = TwoManCrew.Prefs.get(getPlayer())

	self.scale = prefs.scale
	self.showTally = prefs.showTally
	self.showJournal = prefs.showJournal
	self.alwaysExpanded = prefs.alwaysExpanded
end

TwoManCrewPanel.setup = function()
	if TwoManCrewPanel.instance then return end

	-- Restore where the player last left it. Defaults put it top-left under the
	-- vanilla HUD, clear of the moodle stack on the right.
	-- Created at the FULL size, not the collapsed badge size. The element's
	-- rectangle is fixed now (see prerender), and the size handed to :new is
	-- the one the Java object is built with when addToUIManager runs - so
	-- starting small would hand Java a hitbox the widget never uses again.
	local prefs = TwoManCrew.Prefs.get(getPlayer())
	local scale = prefs.scale or 1.0
	local startWidth = math.floor(WIDTH * scale)
	local startHeight = math.floor(PAD * scale) * 2 + math.floor(LINE * scale) * 2
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
