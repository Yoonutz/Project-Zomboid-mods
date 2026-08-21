-- TwoManCrew_MastersMark.lua (server)
-- Handles the client's "mastersMark" notification. The client has already
-- written the mark into the crafted item's own ModData (crafting is
-- client-authoritative in vanilla MP - see the client half for why), so
-- this handler's job is limited to what the server does own: re-validating
-- the claim before it becomes shared, rewarded state (tally/journal/XP),
-- exactly as required by SPEC.md "Never trust a client-supplied value the
-- server can compute itself."

local COOLDOWN_KEY = "MastersMark"

local function awardMastersMark(player, partner, count)
	TwoManCrew.Server.addTally("mastersMarkCrafted", count, player)
	TwoManCrew.Server.addJournal(
		player:getUsername() .. " crafted " .. count .. " master-marked piece(s), witnessed by " .. partner:getUsername() .. ".",
		player
	)

	TwoManCrew.startCooldown(player, COOLDOWN_KEY, TwoManCrew.MastersMark.COOLDOWN_SECONDS)

	-- Small, immediate reward for the apprentice partner, mirroring the
	-- witnessed-high-skill-action XP bonus MastersMark.XP_AMOUNT already
	-- documents in TwoManCrew_Config.lua. The mentor already benefits from
	-- the mark itself (sturdier structures downstream); this keeps the
	-- partner from getting nothing out of standing nearby.
	partner:getXp():AddXP(Perks.Woodwork, TwoManCrew.MastersMark.XP_AMOUNT, false, false, false, false)
	HaloTextHelper.addText(partner, "Learned from a master's mark!")
end

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "mastersMark" then return end
	if not player then return end

	local count = args and args.count
	if not count or type(count) ~= "number" or count < 1 then return end

	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, TwoManCrew.MastersMark.COOLDOWN_SECONDS) then
		return
	end

	-- Re-validate skill and proximity server-side; never trust the client's claim.
	if player:getPerkLevel(Perks.Woodwork) < TwoManCrew.MastersMark.MIN_SKILL_GAP then return end

	local partner = TwoManCrew.getPartner(player)
	if not partner then return end -- alone: silent no-op per SPEC

	awardMastersMark(player, partner, count)
end

Events.OnClientCommand.Add(OnClientCommand)
