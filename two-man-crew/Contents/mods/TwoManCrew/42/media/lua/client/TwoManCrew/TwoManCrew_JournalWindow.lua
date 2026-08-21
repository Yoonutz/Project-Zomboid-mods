-- TwoManCrew_JournalWindow.lua (client)
--
-- The crew journal, as a real window you click rather than a key you memorise.
-- Opens from the button on the crew panel; drag it, scroll it, close it.
--
-- Reads like a logbook: newest entry first, each line stamped with the in-game
-- day it happened and who did it. The campaign claim, once assigned, sits at the
-- top as the standing objective.
--
-- Verified APIs (installed Build 42.20.3):
--   ISCollapsableWindow:derive   client/Camping/ISUI/ISCampingInfoWindow.lua:4
--   ISCollapsableWindow.createChildren / :initialise / :addToUIManager
--     same file, :7-13
--   ISButton:new(x,y,w,h,title,target,onclick)
--     client/ISUI/ISButton.lua:461 signature, usage client/Chat/ISChat.lua:103
--   ISScrollingListBox            client/DebugUIs/AnimationClipViewer.lua:1
--   self:drawText(text,x,y,r,g,b,a,font)
--     client/Fishing/FishingDebugWindow.lua:64
--   self:drawRect(x,y,w,h,a,r,g,b)   alpha FIRST
--     client/Fishing/TensionUI.lua:66
--   Base ISCollapsableWindow:close() only hides, never removeFromUIManager()
--     client/ISUI/ISCollapsableWindow.lua:134-136 - so this window overrides
--     close() to pair both calls, matching client/Fishing/FishingDebugWindow.lua:10-11
--     and client/DebugUIs/ISTeleportDebugUI.lua:142-143

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "TwoManCrew/TwoManCrew_Config"

TwoManCrewJournalWindow = ISCollapsableWindow:derive("TwoManCrewJournalWindow")

local PAD = 8
local ROW = 20

function TwoManCrewJournalWindow:createChildren()
	ISCollapsableWindow.createChildren(self)

	local top = self:titleBarHeight() + PAD

	self.claimLabel = nil

	self.list = ISScrollingListBox:new(PAD, top + ROW, self.width - PAD * 2, self.height - top - ROW - PAD)
	self.list:initialise()
	self.list:instantiate()
	self.list.itemheight = ROW
	self.list.selected = -1
	self.list.drawBorder = true
	self:addChild(self.list)

	self.refreshButton = ISButton:new(
		PAD, self.height - ROW - PAD, 90, ROW,
		"Refresh", self, TwoManCrewJournalWindow.onRefresh
	)
	self.refreshButton:initialise()
	self:addChild(self.refreshButton)

	self.claimButton = ISButton:new(
		PAD + 96, self.height - ROW - PAD, 110, ROW,
		"Claim a block", self, TwoManCrewJournalWindow.onClaim
	)
	self.claimButton:initialise()
	self:addChild(self.claimButton)

	self:onRefresh()
end

-- Asks the server for the current tally and journal. The reply lands in
-- TwoManCrew.Client.lastReport, which populate() reads on the next render.
function TwoManCrewJournalWindow:onRefresh()
	if TwoManCrew.Client and TwoManCrew.Client.requestCrewReport then
		TwoManCrew.Client.requestCrewReport(getPlayer())
	end
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
function TwoManCrewJournalWindow:populate()
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

function TwoManCrewJournalWindow:prerender()
	ISCollapsableWindow.prerender(self)

	-- Repopulate only when the underlying report changed, so the list does not
	-- rebuild every frame.
	local report = TwoManCrew.Client and TwoManCrew.Client.lastReport
	if report ~= self.lastSeenReport then
		self.lastSeenReport = report
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

	o.title = "Crew Journal"
	o.resizable = true
	o.drawFrame = true
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
