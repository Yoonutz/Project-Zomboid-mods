-- TwoManCrew_FellingBonus.lua (server)
-- Handles the client's "fellingBonus" request. Re-validates that a crew
-- partner is actually in range and that the cooldown has expired before
-- awarding anything. The server is authoritative; the client's own check
-- (client/TwoManCrew/TwoManCrew_FellingBonus.lua) is a hint only.

local COOLDOWN_KEY = "FellingBonus"

local function awardFellingBonus(player, partner)
	local amount = TwoManCrew.FellingBonus.XP_AMOUNT

	player:getXp():AddXP(Perks.Woodwork, amount, false, false, false, false)
	partner:getXp():AddXP(Perks.Woodwork, amount, false, false, false, false)

	TwoManCrew.startCooldown(player, COOLDOWN_KEY, TwoManCrew.FellingBonus.COOLDOWN_SECONDS)
	TwoManCrew.startCooldown(partner, COOLDOWN_KEY, TwoManCrew.FellingBonus.COOLDOWN_SECONDS)

	-- Shared crew scoreboard. Guarded: CrewState is a separate server file and
	-- load order across mod files is not guaranteed.
	if TwoManCrew.Server and TwoManCrew.Server.addTally then
		TwoManCrew.Server.addTally("treesFelled", 1, player)
		TwoManCrew.Server.addJournal("felled a tree with the crew", player)
	end

	-- Plain literal, not a translation key: no Translate/*.txt entry is part
	-- of this feature's two-file scope, and an undefined getText() key would
	-- just echo back onscreen anyway.
	HaloTextHelper.addText(player, "Crew felling bonus!")
	HaloTextHelper.addText(partner, "Crew felling bonus!")
end

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "fellingBonus" then return end
	if not player then return end

	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, TwoManCrew.FellingBonus.COOLDOWN_SECONDS) then
		return
	end

	-- Re-validate proximity server-side; never trust the client's claim.
	local partner = TwoManCrew.getPartner(player)
	if not partner then return end

	awardFellingBonus(player, partner)
end

Events.OnClientCommand.Add(OnClientCommand)
