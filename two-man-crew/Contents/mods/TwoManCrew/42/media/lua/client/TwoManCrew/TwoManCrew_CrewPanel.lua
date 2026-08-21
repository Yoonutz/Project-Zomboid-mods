-- TwoManCrew_CrewPanel.lua (client)
--
-- Always-visible crew status widget. Replaces the report keybind: status you
-- glance at beats status you have to ask for, which is why the moodle idea was
-- the right instinct even though a real moodle is impossible (the MoodleType
-- list is fixed in Java - mods cannot add an eleventh entry).
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
--   getCore():getScreenWidth() / getScreenHeight()
--     - client/Chat/ISAlert.lua:33-34

require "ISUI/ISUIElement"
require "TwoManCrew/TwoManCrew_Config"
require "TwoManCrew/TwoManCrew_PanelPrefs"

TwoManCrewPanel = ISUIElement:derive("TwoManCrewPanel")

local PAD = 6
local LINE = 16
local WIDTH = 190

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
	o.tally = nil
	o.lastJournal = nil

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

	local showTally = self.showTally ~= false and self.tally ~= nil
	local showJournal = self.showJournal ~= false and self.lastJournal ~= nil

	local lines = 2
	if showTally then lines = lines + 1 end
	if showJournal then lines = lines + 1 end
	self.height = pad * 2 + line * lines

	self:drawRect(0, 0, self.width, self.height, 0.55, 0.0, 0.0, 0.0)

	local y = pad

	self:drawText("CREW", pad, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
	y = y + line

	-- Danger is not decided here: WatchMyBack owns that end-to-end via the
	-- server and delivers it as halo text, so this line only shows presence.
	if self.partnerName then
		self:drawText(self.partnerName .. " - nearby", pad, y, 0.5, 0.9, 0.5, 1, UIFont.Small)
	else
		self:drawText("working alone", pad, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
	end
	y = y + line

	if showTally then
		local total = 0
		for _, n in pairs(self.tally) do
			total = total + n
		end
		self:drawText("crew deeds: " .. total, pad, y, 0.8, 0.8, 0.7, 1, UIFont.Small)
		y = y + line
	end

	if showJournal and self.lastJournal.text then
		local text = self.lastJournal.text
		-- Wider panel fits more text, so the truncation point follows scale.
		local maxChars = math.floor(28 * scale)
		if #text > maxChars then text = string.sub(text, 1, maxChars - 1) .. "..." end
		self:drawText(text, pad, y, 0.65, 0.65, 0.6, 1, UIFont.Small)
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
-- file never set, which would have always returned nil/false.
-- Left click either drags the panel or opens the journal. Which one is decided
-- on mouse-up: if the pointer moved while held, it was a drag, otherwise it was
-- a click. That avoids a modifier key and avoids opening the journal every time
-- you reposition the panel.
function TwoManCrewPanel:onMouseDown(x, y)
	local prefs = TwoManCrew.Prefs.get(getPlayer())
	if prefs.locked then
		self.dragging = false
		return true
	end

	self.dragging = true
	self.dragMoved = false
	self.dragOffsetX = x
	self.dragOffsetY = y
	return true
end

function TwoManCrewPanel:onMouseMove(dx, dy)
	if not self.dragging then return end
	if dx == 0 and dy == 0 then return end

	self.dragMoved = true
	self:setX(self:getX() + dx)
	self:setY(self:getY() + dy)
end

function TwoManCrewPanel:onMouseUp(x, y)
	if self.dragging and self.dragMoved then
		-- Drag finished: persist where it landed, clamped back on screen so a
		-- panel dragged off the edge is not lost on next login.
		local player = getPlayer()
		local prefs = TwoManCrew.Prefs.get(player)
		prefs.x = self:getX()
		prefs.y = self:getY()
		TwoManCrew.Prefs.clampToScreen(prefs, self.width, self.height)
		self:setX(prefs.x)
		self:setY(prefs.y)
	elseif self.dragging and TwoManCrewJournalWindow and TwoManCrewJournalWindow.toggle then
		TwoManCrewJournalWindow.toggle()
	end

	self.dragging = false
	self.dragMoved = false
	return true
end

-- Mouse leaving the element mid-drag must not strand it in dragging state.
function TwoManCrewPanel:onMouseUpOutside(x, y)
	self.dragging = false
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

	local sizeOption = context:addOption("Panel size", self)
	local sizeMenu = context:getNew(context)
	context:addSubMenu(sizeOption, sizeMenu)
	for i = 1, #TwoManCrew.Prefs.SCALES do
		local scale = TwoManCrew.Prefs.SCALES[i]
		local label = tostring(math.floor(scale * 100)) .. "%"
		local opt = sizeMenu:addOption(label, self, TwoManCrewPanel.onSetScale, scale)
		if math.abs(prefs.scale - scale) < 0.01 then
			sizeMenu:setOptionChecked(opt, true)
		end
	end

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
function TwoManCrewPanel:applyPrefs()
	local prefs = TwoManCrew.Prefs.get(getPlayer())

	self.scale = prefs.scale
	self.showTally = prefs.showTally
	self.showJournal = prefs.showJournal

	self.width = math.floor(WIDTH * self.scale)
	self:setWidth(self.width)
end

TwoManCrewPanel.setup = function()
	if TwoManCrewPanel.instance then return end

	-- Restore where the player last left it. Defaults put it top-left under the
	-- vanilla HUD, clear of the moodle stack on the right.
	local prefs = TwoManCrew.Prefs.get(getPlayer())
	local startWidth = math.floor(WIDTH * (prefs.scale or 1.0))
	local startHeight = PAD * 2 + LINE * 2
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
