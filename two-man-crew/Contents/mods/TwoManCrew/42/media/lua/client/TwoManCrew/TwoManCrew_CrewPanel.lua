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
	o.partnerInDanger = false
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
		self.partnerInDanger = false
		return
	end

	local partner = TwoManCrew.getPartner(player)
	if not partner then
		self.partnerName = nil
		self.partnerInDanger = false
		return
	end

	self.partnerName = partner:getUsername()

	-- Danger is self-reported per client on a dedicated server, so the local
	-- read below is a best-effort hint only. TwoManCrew_WatchMyBack owns the
	-- authoritative warning path; this is decoration on top of it.
	local stats = partner:getStats()
	if stats then
		local threshold = TwoManCrew.WatchMyBack.CHASING_ZOMBIE_THRESHOLD
		self.partnerInDanger = stats:getNumChasingZombies() >= threshold
	end
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

	local lines = 2
	if self.tally then lines = lines + 1 end
	if self.lastJournal then lines = lines + 1 end
	self.height = PAD * 2 + LINE * lines

	self:drawRect(0, 0, self.width, self.height, 0.55, 0.0, 0.0, 0.0)

	local y = PAD

	self:drawText("CREW", PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
	y = y + LINE

	if self.partnerName then
		if self.partnerInDanger then
			self:drawText(self.partnerName .. " - IN DANGER", PAD, y, 1, 0.35, 0.25, 1, UIFont.Small)
		else
			self:drawText(self.partnerName .. " - nearby", PAD, y, 0.5, 0.9, 0.5, 1, UIFont.Small)
		end
	else
		self:drawText("working alone", PAD, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
	end
	y = y + LINE

	if self.tally then
		local total = 0
		for _, n in pairs(self.tally) do
			total = total + n
		end
		self:drawText("crew deeds: " .. total, PAD, y, 0.8, 0.8, 0.7, 1, UIFont.Small)
		y = y + LINE
	end

	if self.lastJournal and self.lastJournal.text then
		local text = self.lastJournal.text
		if #text > 28 then text = string.sub(text, 1, 27) .. "..." end
		self:drawText(text, PAD, y, 0.65, 0.65, 0.6, 1, UIFont.Small)
	end
end

function TwoManCrewPanel:initialise()
	ISUIElement.initialise(self)
end

TwoManCrewPanel.setup = function()
	if TwoManCrewPanel.instance then return end

	-- Top-left under the vanilla HUD, clear of the moodle stack on the right.
	local panel = TwoManCrewPanel:new(12, 90, WIDTH, PAD * 2 + LINE * 2)
	panel:initialise()
	panel:addToUIManager()
	panel:setVisible(true)

	-- One report request at start so the counters are populated without the
	-- player having to ask. The panel refreshes them from the cached reply.
	if TwoManCrew.Client and TwoManCrew.Client.requestCrewReport then
		TwoManCrew.Client.requestCrewReport(getPlayer())
	end
end

Events.OnGameStart.Add(TwoManCrewPanel.setup)
