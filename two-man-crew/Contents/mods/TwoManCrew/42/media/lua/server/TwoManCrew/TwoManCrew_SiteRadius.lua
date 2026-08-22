-- TwoManCrew_SiteRadius.lua (server)
-- Handles the client's "siteRadiusBonus" request: a build or craft action
-- just completed with a crew partner within TwoManCrew.SiteRadius.RADIUS_TILES.
-- Re-validates proximity and cooldown server-side before awarding anything;
-- the client's own check (client/TwoManCrew/TwoManCrew_SiteRadius.lua) is a
-- hint only.

require "TwoManCrew/TwoManCrew_Config"

if isClient() then return end

local COOLDOWN_KEY = "SiteRadius"

local function awardSiteBonus(player, partner)
	local amount = TwoManCrew.SiteRadius.XP_AMOUNT -- no dedicated SiteRadius.XP_AMOUNT in config; reuse the same small, conservative bonus size

	player:getXp():AddXP(Perks.Woodwork, amount, false, false, false, false)
	partner:getXp():AddXP(Perks.Woodwork, amount, false, false, false, false)

	TwoManCrew.startCooldown(player, COOLDOWN_KEY, TwoManCrew.SiteRadius.CHECK_INTERVAL_SECONDS)
	TwoManCrew.startCooldown(partner, COOLDOWN_KEY, TwoManCrew.SiteRadius.CHECK_INTERVAL_SECONDS)

	TwoManCrew.Server.addTally("siteRadiusBonus", 1, player)

	HaloTextHelper.addText(player, "Two-man work site bonus!")
	HaloTextHelper.addText(partner, "Two-man work site bonus!")
end

local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if command ~= "siteRadiusBonus" then return end
	if not player then return end

	if TwoManCrew.onCooldown(player, COOLDOWN_KEY, TwoManCrew.SiteRadius.CHECK_INTERVAL_SECONDS) then
		return
	end

	-- Re-validate proximity server-side; never trust the client's claim.
	-- SiteRadius uses its own configured radius rather than the default
	-- crew radius, so this checks distance directly. It also keeps the
	-- winning partner's distance, which getPartner does not return.
	local px, py = player:getX(), player:getY()
	local partner = nil
	local partnerDist = nil

	for _, other in ipairs(TwoManCrew.getAllPlayers()) do
		if other ~= player then
			local dist = other:DistTo(px, py)
			if dist <= TwoManCrew.SiteRadius.RADIUS_TILES then
				if not partnerDist or dist < partnerDist then
					partner = other
					partnerDist = dist
				end
			end
		end
	end

	if not partner then return end -- alone at the site: silent no-op per SPEC

	awardSiteBonus(player, partner)
end

Events.OnClientCommand.Add(OnClientCommand)
