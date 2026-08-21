-- TwoManCrew_ShiftChange.lua (client)
-- Intentionally inert. Every input this feature needs - the current
-- in-game hour (getGameTime():getHour(), server/Traps/STrapGlobalObject.lua:535)
-- and crew proximity (TwoManCrew.getPartner) - is already computable
-- server-side with no client-only signal involved, unlike e.g.
-- TwoManCrew_FellingBonus.lua which needs to detect a local timed-action
-- completing. So there is nothing for a client to detect or request here:
-- the server (server/TwoManCrew/TwoManCrew_ShiftChange.lua) runs its own
-- EveryTenMinutes check and calls HaloTextHelper.addText(player, ...)
-- directly on each player object it decides to reward - a pattern already
-- verified server-side at server/XpSystem/XpUpdate.lua:197
-- (HaloTextHelper.addTextWithArrow called on a player from server code).
--
-- This file exists as the client half of the pair per the SPEC's file
-- naming convention, and to make the "no client logic needed" decision
-- explicit and easy to revisit rather than silently absent.

require "TwoManCrew/TwoManCrew_Config"
