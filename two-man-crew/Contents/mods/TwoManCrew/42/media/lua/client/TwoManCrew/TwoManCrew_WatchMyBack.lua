-- TwoManCrew_WatchMyBack.lua
-- Warns a player when their crew partner is in danger and they are not.
--
-- Danger stats (getNumChasingZombies/getNumVeryCloseZombies/getNumVisibleZombies)
-- are only ever read from a client's own local player in verified vanilla call
-- sites (client/ISUI/ISWorldObjectContextMenu.lua:1056, client/Foraging/
-- ISSearchManager.lua:1096-1097, server/NPCs/SadisticAIDirector/
-- SadisticMusicDirector.lua:10-13 - the latter explicitly guards
-- `if isServer() then return end` before reading getStats() on
-- getSpecificPlayer(0), the local player). No verified vanilla site reads
-- another (remote) player's getStats() from a client. On a dedicated server
-- a client's view of a remote IsoPlayer cannot be assumed to carry synced
-- danger stats, so this feature is client+server: each client reports only
-- its own danger state to the server, and the server (which can see every
-- connected player) decides whether to warn the partner and messages that
-- partner's client specifically via sendServerCommand(playerObj, ...).

require "TwoManCrew/TwoManCrew_Config"

local cfg = TwoManCrew.WatchMyBack

-- Real-time throttle: OnPlayerUpdate fires every tick (~60/s). Danger state
-- does not need per-tick resolution, so real work only runs once every
-- CHECK_INTERVAL_TICKS ticks. Plain integer counter, no allocation.
local CHECK_INTERVAL_TICKS = 30
local tickCounter = 0

-- Only send a report when the danger boolean actually changes, so a
-- prolonged chase or a prolonged calm spell does not spam the server every
-- interval - just once at each transition. The server needs this edge to
-- know when a player has become safe again (see server half).
local lastReportedDanger = nil

local function OnPlayerUpdate(player)
	if not player then return end

	tickCounter = tickCounter + 1
	if tickCounter < CHECK_INTERVAL_TICKS then return end
	tickCounter = 0

	if isServer() then return end
	if TwoManCrew.isAlone(player) then return end

	local stats = player:getStats()
	if not stats then return end

	local chasing = stats:getNumChasingZombies()
	local inDanger = chasing >= cfg.CHASING_ZOMBIE_THRESHOLD

	if inDanger == lastReportedDanger then return end
	lastReportedDanger = inDanger

	sendClientCommand(player, TwoManCrew.MODULE, "watchMyBackDanger", {
		chasing = chasing,
	})
end
Events.OnPlayerUpdate.Add(OnPlayerUpdate)

-- Server tells this client its partner is in danger and this client is not.
local function OnServerCommand(module, command, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "watchMyBackWarning" then return end

	local player = getPlayer()
	if not player then return end

	-- Plain literal, not getText(): this mod ships no Translate/ files yet,
	-- and an unresolved translation key would render as the raw key in-game.
	HaloTextHelper.addBadText(player, "Your partner is in danger!")
end
Events.OnServerCommand.Add(OnServerCommand)
