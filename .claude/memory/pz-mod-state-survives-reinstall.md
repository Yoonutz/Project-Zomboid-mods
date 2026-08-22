---
name: pz-mod-state-survives-reinstall
description: "Re-adding or updating a TwoManCrew build does not reset progress - crew claim, tally, journal, tiers and panel prefs live in the save's ModData, not the mod folder; only a new save starts over"
metadata:
  node_type: memory
  type: project
  originSessionId: a3a676dc-560c-46e9-9fb8-fc132dd1dc04
  modified: 2026-08-21T21:23:02.761Z
---

Disabling and re-enabling the mod, or dropping in an updated build, does NOT restart campaign
progress. State lives in the save file:

- Shared crew state (claim, tally, journal, tier flags) - `ModData.getOrCreate("TwoManCrew")`,
  owned by `TwoManCrew_CrewState.lua`.
- Per-player state (panel position/scale/lock, feature cooldowns) - `player:getModData()`.

Only a brand-new save starts from zero, because that is a different world.

**Why:** Kami asked this mid-session while a fix was being shipped, and the answer changes
whether an update is safe to hand to players mid-campaign. It is also the reason schema
changes need care rather than a wipe.

**How to apply:** every accessor uses `getOrCreate` plus a defensive `ensureSchema` that fills
missing fields without overwriting existing ones, so a save written by an older build loads
cleanly against newer code. Preserve that property when adding fields - add them to the
schema-fill, never reinitialise a table that may already hold player data, and never "reset to
defaults" on load. Before claiming an update is save-safe, check the diff for any assignment
that replaces a ModData table wholesale rather than filling into it.

Related: [[pz-vanilla-source-is-the-api-reference]].
