-- TwoManCrew_CrewReport.lua (client)
-- Requests the shared crew tally/journal from the server and displays the
-- reply to the local player. No local state is authoritative here; this
-- module only renders what the server last sent.
--
-- Verified: sendClientCommand(playerObj, module, command, args) at
-- client/Context/Inventory/InvContextMedia.lua:36; OnServerCommand handler
-- shape at client/Farming/CFarmingSystem.lua:21; HaloTextHelper.addText at
-- client/Foraging/forageClient.lua:73; player:Say at client/ServerCommands.lua:182.

if isServer() then return end

TwoManCrew = TwoManCrew or {}
TwoManCrew.Client = TwoManCrew.Client or {}

-- Last report received from the server, kept for anything that wants to
-- redraw without re-requesting (e.g. a UI panel). nil until the first reply.
TwoManCrew.Client.lastReport = nil

-- Sends the request to the server. Call this from a keybind, context menu
-- entry, or UI button handler.
function TwoManCrew.Client.requestCrewReport(player)
	player = player or getPlayer()
	if not player then return end

	sendClientCommand(player, TwoManCrew.MODULE, "requestCrewReport", {})
end

-- Formats and prints the tally/journal to the player via HaloText and the
-- chat/say line, since there's no dedicated panel yet. Kept small and
-- replaceable once a real UI exists.
local function displayReport(player, tally, journal)
	-- Plain literal, not a getText() key: no Translate/ entry exists for this
	-- mod yet, and getText() on a missing key is not worth relying on here.
	HaloTextHelper.addText(player, "Crew report received")

	local tallyLines = {}
	for key, count in pairs(tally or {}) do
		tallyLines[#tallyLines + 1] = key .. ": " .. tostring(count)
	end
	if #tallyLines == 0 then
		player:Say("Crew tally: (nothing recorded yet)")
	else
		player:Say("Crew tally - " .. table.concat(tallyLines, ", "))
	end

	local entryCount = journal and #journal or 0
	if entryCount == 0 then
		player:Say("Crew journal: (no entries yet)")
	else
		local latest = journal[entryCount]
		player:Say("Crew journal (" .. entryCount .. " entries) - latest: "
			.. tostring(latest.playerName) .. " " .. tostring(latest.text))
	end
end

local function onServerCommand(module, command, args)
	if module ~= TwoManCrew.MODULE then return end

	if command == "crewReport" then
		local player = getPlayer()
		if not player or not args then return end

		TwoManCrew.Client.lastReport = args

		displayReport(player, args.tally, args.journal)
	end
end

Events.OnServerCommand.Add(onServerCommand)

-- Keybind for the FULL report. Without this, requestCrewReport above is
-- defined but never called, and the tally and journal can never be seen.
--
-- TwoManCrew_CrewPanel shows a permanent at-a-glance summary and refreshes
-- itself from the same reply, so this key is not the only way in. It stays
-- because the panel has room for one journal line and a total; this prints
-- the full breakdown on demand.
--
-- Same pattern as TwoManCrew_DistressCall: a direct OnKeyStartPressed
-- listener compared against a literal Keyboard.KEY_* constant, as vanilla
-- itself does (client/ISUI/ISUIHandler.lua:35, registered at :102; raw
-- keycode comparison at client/ISUI/Maps/Editor/WorldMapEditor.lua:209).
--
-- Default key: F7. Checked against every bind.key entry in
-- shared/keyBinding.lua and every Keyboard.KEY_* literal in the installed
-- lua tree - F7 appears in neither. F9 is taken by the distress call,
-- F10 and F11 by vanilla bindings.
local REPORT_KEY = Keyboard.KEY_F7

local function onKeyStartPressed(key)
	if key ~= REPORT_KEY then return end

	local player = getPlayer()
	if not player then return end

	TwoManCrew.Client.requestCrewReport(player)
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)
