# Restoration Visibility Implementation Plan

> **STATUS: written, NOT TESTED. Branch `restoration-visibility`, 2026-08-22, version `0.1.7`.**
>
> **This code has never been executed.** Not once, not partially. No Project Zomboid session has
> loaded it. Nothing below is known to work.
>
> What actually ran: `luaparse` (syntax only), `lua-language-server` (undefined names only),
> `prettier` (markdown formatting), plus grep checks that identifiers match across files and
> pen-and-paper arithmetic on the layout. None of that executes a line of the mod. It is
> proofreading, not testing - it cannot catch a wrong method name, a nil at runtime, a wrong
> event, or a UI that draws garbage.
>
> Every task's in-game check is OPEN. Task 0's needs two connected players. The first load in PZ
> may simply fail, and `~/Zomboid/Logs/` is the only thing that will say so.
>
> The version note, for the record: `0.1.7` rather than the `0.1.16` this document's per-task
> ladder predicted, because Task 0 took three commits and tasks 1-12 were batched into one.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Crew Journal show exactly why each claimed building does or does not count as restored, and do the same for the livestock track - fixing the window check that lets broken glass pass, making tier 2's "three adjacent" and livestock stages L1 and L3 into real checks, surfacing both hold countdowns, and renaming every tier and stage that promised more than it verified.

**Architecture:** The server-side checker in `TwoManCrew_Restoration.lua` already computes every per-condition fact and then throws all of it away, returning a single count. This plan stops discarding it: the checker gains a per-building report function, a new `requestClaimDetail` command carries that report to the client, and the journal window renders it as a third view. Building footprints are computed once at claim time from `RoomDef` bounds (MetaGrid data, no chunk loading) so tier-2 adjacency becomes a genuine geometric test, and the same footprints give the livestock checks a claim boundary. Livestock follows the identical arc: L1 and L3 stop guessing from nearby animal counts and read real structures instead, and the census result is surfaced rather than discarded. Furniture is explicitly out of scope; the crew-presence requirement it used to justify is promoted to a rule in its own right.

**Tech Stack:** Lua 5.1 (Kahlua dialect), Project Zomboid Build 42.20.3 client/server Lua API, `luaparse` for syntax gating, `lua-language-server` for diagnostics.

---

## Context for the implementer

You almost certainly have no context on this repo. Read this section before Task 1.

### What this mod is

`TwoManCrew` is a Project Zomboid Build 42 mod for a two-player co-op campaign. The crew claims a
block of buildings and restores them. Progress is tracked as five building tiers and four
livestock stages. This plan touches both tracks.

### The critical constraint: chunk loading

A Project Zomboid server only simulates `IsoGridSquare`s near online players. Windows, doors and
corpses live on `IsoGridSquare`, so a building far from any player is **unreadable** - not
"unrestored", unreadable. `getCell():getGridSquare(x, y, z)` returns `nil` for unloaded ground.

The existing checker already handles this correctly by returning `"unknown"`. Do not "simplify"
that away. Preserving the three-state verdict (`restored` / `not_restored` / `unknown`) is the
entire point of Tasks 2 and 3.

`BuildingDef` and `RoomDef`, by contrast, come from the **MetaGrid** - static map metadata that is
readable anywhere, with no chunk loading. That is why Task 6 can compute footprints at claim time.

### How this repo verifies work

There is **no unit test harness** and there cannot easily be one: this code calls PZ engine
globals (`getCell`, `getWorld`, `IsoPlayer`, `instanceof`) that only exist inside the running
game. Do not invent a mock harness for this plan - that is a separate project.

Verification here is three real gates, run from the repo root:

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed` (the count rises as files are added).

```bash
"C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`. Run from the **repo root** or `.luarc.json`
is not picked up.

```bash
npx prettier --check "*.md" "docs/*.md"
```

Expected: `All matched files use Prettier code style!`

Because there are no tests, **every task below ends with a manual in-game check** written as an
explicit "load the game, do X, expect Y" instruction. That is the real test. A task is not done
when it parses; it is done when the stated in-game observation holds.

### Rules that bind every task

- **Verify before using any API.** If a task uses a PZ function not already cited in the repo,
  confirm it against the installed source at
  `D:\Games\Steam\steamapps\common\ProjectZomboid\media\lua` before writing the call. Every API
  in this plan was verified on 2026-08-22 and carries its `file:line` citation.
- **Bump `modversion` in the same commit as any behaviour change**, in BOTH
  `two-man-crew/Contents/mods/TwoManCrew/mod.info` and
  `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`. They must stay byte-identical. Current
  version is `0.1.2`. This plan ends at `0.1.16`.
- **Never touch the installed game folder.** `~/Zomboid/mods/TwoManCrew` is deliberately pinned to
  `0.1.0` to match another player. Do not deploy, sync, or "helpfully update" it.
- **Do not add Claude attribution to commits.**

### Files you will touch

| File                                                 | Responsibility after this plan                                                                     |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `.../server/TwoManCrew/TwoManCrew_Restoration.lua`   | Per-building condition checks; gains `getClaimDetail()`; window fix; presence rule                 |
| `.../server/TwoManCrew/TwoManCrew_Campaign.lua`      | Claim survey; gains footprint capture at claim time                                                |
| `.../server/TwoManCrew/TwoManCrew_Tiers.lua`         | Tier and stage evaluation; real tier-2 adjacency, real L1/L3 checks, both hold countdowns, renames |
| `.../client/TwoManCrew/TwoManCrew_TierReport.lua`    | Client cache; gains `lastClaimDetail`                                                              |
| `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua` | Renders the new Buildings view and the livestock census detail                                     |
| `two-man-crew/GOALS.md`                              | Tier names, stage names and the restoration definition, corrected                                  |

Paths are abbreviated above. In full, every `.../server/` and `.../client/` path is prefixed with
`two-man-crew/Contents/mods/TwoManCrew/42/media/lua/`.

---

## Task 0: Fix the server-side player lookup and the distress call range

**Do this task FIRST.** Everything else in this plan makes progress _visible_; this makes the crew
features _work_ for the second player. A better progress panel is worth little if the features
behind it never fire.

**Bug 1 - the server cannot see remote players.** Seven places call `IsoPlayer.getPlayers()` from
server-side or shared code. That function returns only players on the local machine (split-screen),
not remote clients. On a real multiplayer session the second player is absent from that list, so
`getPartner()` returns nil, `isAlone()` returns true, and every crew feature silently no-ops for
them.

Verified against the installed source: server code uses `getOnlinePlayers()` -
`server/Foraging/forageServer.lua:463`, `server/XpSystem/XpUpdate.lua:300`,
`server/ClientCommands.lua:628`. The only `IsoPlayer.getPlayers()` in vanilla's entire `server/`
tree sits inside a commented-out block guarded by `if isServer() then return end`
(`server/Seasons/season.lua:121-124`) - i.e. vanilla itself does not use it server-side.

**The singleplayer half, which matters here.** `getOnlinePlayers()` covers every multiplayer case,
host and remote client alike - it is NOT dedicated-server only (verified client-side at
`client/Chat/ISChat.lua:560`). Singleplayer has no online list at all, and falls back to
`getSpecificPlayer` - the branch vanilla uses at `server/XpSystem/XpUpdate.lua:301-303`:

```lua
	local playersNumber = isServer() and players:size()-1 or getNumActivePlayers()-1
	local playerObj = isServer() and players:get(playerIndex) or getSpecificPlayer(playerIndex)
```

This repo has already shipped one bug from ignoring the singleplayer case (commit `4e8980c`,
"Fix three features silently disabled in singleplayer"). Do not repeat it: the fix must be a single
shared helper that handles both, not a blind find-and-replace.

**Bug 2 - the distress call cannot reach past 12 tiles.** `TwoManCrew.DistressCall.RANGE_TILES` is
30, but both halves find the partner via `getPartner()`, which is hard-capped at
`CREW_RADIUS = 12`. The 30 is checked afterwards and can never matter. So a distress call only
works when your partner is already beside you - the one situation it is not needed for.

**Bug 3 - F9 fails silently.** `TwoManCrew_DistressCall.lua:45` returns with no message when
`isAlone()` is true, so the key appears dead.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/shared/TwoManCrew/TwoManCrew_Config.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_DistressCall.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_DistressCall.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua:266`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_ShiftChange.lua:77`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_SiteRadius.lua:42`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua:136,295`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Add one shared player-enumeration helper**

In `TwoManCrew_Config.lua`, insert immediately above `function TwoManCrew.getNearbyCrew`:

```lua
-- Returns a plain Lua array of every player this machine can currently see.
--
-- THE BUG THIS REPLACES: every server-side and shared caller used
-- IsoPlayer.getPlayers(), which returns only players on the LOCAL machine
-- (split-screen). On a dedicated server the remote player is not in that list,
-- so getPartner() returned nil and every crew feature silently no-opped for the
-- second player.
--
-- Vanilla's own rule, verified: server code uses getOnlinePlayers()
-- (server/Foraging/forageServer.lua:463, server/XpSystem/XpUpdate.lua:300,
-- server/ClientCommands.lua:628). The single IsoPlayer.getPlayers() in the whole
-- vanilla server/ tree is inside a commented-out block
-- (server/Seasons/season.lua:121-124).
--
-- getOnlinePlayers() covers every multiplayer case, host and client alike.
-- Singleplayer has no online-player list at all, so it goes through
-- getSpecificPlayer instead - the same branch vanilla uses at
-- server/XpSystem/XpUpdate.lua:301-303. This repo has already shipped one
-- singleplayer regression from ignoring that case (commit 4e8980c), so the
-- branch is deliberate, not defensive noise.
function TwoManCrew.getAllPlayers()
	local result = {}

	-- Any multiplayer context, either side of the connection. NOT isServer()
	-- alone: that is false on a listen/co-op host and on every remote client,
	-- both of which would then fall through to the split-screen branch and
	-- never see the other player.
	if isClient() or isServer() then
		local players = getOnlinePlayers()
		if players then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p then table.insert(result, p) end
			end
		end
		return result
	end

	local count = getNumActivePlayers()
	if count and count > 0 then
		for i = 0, count - 1 do
			local p = getSpecificPlayer(i)
			if p then table.insert(result, p) end
		end
	end

	-- Singleplayer with no split-screen still has exactly one player, and
	-- getNumActivePlayers() has been seen to report 0 during early load.
	if #result == 0 then
		local p = getPlayer()
		if p then table.insert(result, p) end
	end

	return result
end
```

- [ ] **Step 2: Route `getNearbyCrew` through the helper**

Replace the body of `TwoManCrew.getNearbyCrew` so it no longer calls `IsoPlayer.getPlayers()`
directly. Keep its existing signature and return shape:

```lua
function TwoManCrew.getNearbyCrew(player, radius)
	if not player then return nil end
	radius = radius or TwoManCrew.CREW_RADIUS

	local px, py = player:getX(), player:getY()
	local found = nil

	for _, other in ipairs(TwoManCrew.getAllPlayers()) do
		if other ~= player then
			if other:DistTo(px, py) <= radius then
				found = found or {}
				table.insert(found, other)
			end
		end
	end

	return found
end
```

Before editing, read the current function - if its existing contract differs (for example it
returns an empty table rather than nil), preserve the existing contract exactly and change only the
enumeration. Callers depend on it.

- [ ] **Step 3: Give `getPartner` an optional radius, defaulting to today's behaviour**

Replace `TwoManCrew.getPartner` with:

```lua
-- Returns the single nearest other player within radius, or nil.
-- radius defaults to CREW_RADIUS so existing callers are unchanged; the
-- distress call passes its own wider range.
function TwoManCrew.getPartner(player, radius)
	if not player then return nil end
	radius = radius or TwoManCrew.CREW_RADIUS

	local px, py = player:getX(), player:getY()
	local nearest, nearestDist = nil, nil

	for _, other in ipairs(TwoManCrew.getAllPlayers()) do
		if other ~= player then
			local dist = other:DistTo(px, py)
			if dist <= radius then
				if not nearestDist or dist < nearestDist then
					nearest = other
					nearestDist = dist
				end
			end
		end
	end

	return nearest
end
```

`isAlone` needs no change - it calls `getPartner(player)` with no radius and keeps its meaning.

- [ ] **Step 4: Replace the six remaining direct calls**

In each of these, replace the `IsoPlayer.getPlayers()` enumeration with the helper. The pattern is
the same everywhere: a `local players = IsoPlayer.getPlayers()` followed by a
`for i = 0, players:size() - 1 do ... players:get(i)` loop becomes
`for _, p in ipairs(TwoManCrew.getAllPlayers()) do`.

The six sites:

- `server/TwoManCrew/TwoManCrew_Restoration.lua:266` (in `crewPresentNear`)
- `server/TwoManCrew/TwoManCrew_ShiftChange.lua:77`
- `server/TwoManCrew/TwoManCrew_SiteRadius.lua:42`
- `server/TwoManCrew/TwoManCrew_Tiers.lua:136` (in `censusNearbyAnimals`)
- `server/TwoManCrew/TwoManCrew_Tiers.lua:295` (in `announceTier`)

Read each function before editing and preserve its existing logic exactly - only the enumeration
changes. Note the nil-guard difference: `IsoPlayer.getPlayers()` could return nil and each site
guards for it, but `getAllPlayers()` always returns a table, so those `if not players then return`
guards become dead and should be removed rather than left misleading.

Each of these files must `require "TwoManCrew/TwoManCrew_Config"` already - verify, and add it if
any does not.

- [ ] **Step 5: Let the distress call use its own advertised range**

In `server/TwoManCrew/TwoManCrew_DistressCall.lua`, replace:

```lua
	local partner = TwoManCrew.getPartner(player)
	if not partner then return end
```

with:

```lua
	-- Search the full advertised distress range, not CREW_RADIUS. Previously
	-- this used the default 12-tile getPartner, so RANGE_TILES (30) was checked
	-- afterwards against a partner who was already guaranteed to be within 12 -
	-- the wider range could never apply, and a call only worked when the partner
	-- was already beside you.
	local partner = TwoManCrew.getPartner(player, cfg.RANGE_TILES)
	if not partner then return end
```

The existing `dist > cfg.RANGE_TILES` check below stays: it re-validates against the
client-supplied position rather than the player's current one.

- [ ] **Step 6: Make F9 explain itself instead of failing silently**

In `client/TwoManCrew/TwoManCrew_DistressCall.lua`, replace:

```lua
	if TwoManCrew.isAlone(player) then return end
```

with:

```lua
	-- Say something rather than nothing. This used to return silently, so a
	-- crew with no partner in range experienced F9 as a dead key with no
	-- indication whether the mod was even loaded.
	if TwoManCrew.getPartner(player, cfg.RANGE_TILES) == nil then
		HaloTextHelper.addBadText(player, "No crew partner in range.")
		return
	end
```

- [ ] **Step 7: Verify no direct enumeration survives outside the helper**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && grep -rn "IsoPlayer.getPlayers" two-man-crew/Contents/mods/TwoManCrew/42/media/lua/
```

Expected: only comment lines referencing the old approach, and no executable call outside
`getAllPlayers`. Any remaining live call is a missed site.

- [ ] **Step 8: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`. If `getOnlinePlayers`, `getNumActivePlayers` or
`getSpecificPlayer` are flagged as undefined globals, add them to `types/pz.lua` rather than
silencing:

```lua
---@return ArrayList
function getOnlinePlayers() end

---@return number
function getNumActivePlayers() end

---@param index number
---@return IsoPlayer
function getSpecificPlayer(index) end
```

- [ ] **Step 9: Bump modversion to 0.1.3 in both files and commit**

Note: Task 0 shipped as three commits and consumed 0.1.3, 0.1.4 (listen-host correction) and
0.1.5 (code-review fixes). Task 1 starts at 0.1.6 and every later task shifts up accordingly.

Note this takes the 0.1.3 slot; every later task in this plan shifts up by one. Confirm both files
match:

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && diff two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info && echo IDENTICAL
```

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Let server-side code see remote players, and unbreak the distress call"
```

- [ ] **Step 10: In-game check - REQUIRES BOTH PLAYERS**

This is the one task in the plan that cannot be verified solo. With both players connected:

1. Stand together. Expected: the crew panel shows the partner, as before - no regression.
2. Separate to roughly 20 tiles apart, out of the old 12-tile radius.
3. Press F9. Expected: the partner sees "Distress call: <direction>, <n> tiles!".
4. Separate to over 30 tiles. Press F9.
   Expected: "No crew partner in range." rather than silence.
5. Load a singleplayer save and open the Crew Journal.
   Expected: no Lua errors, and the panel still renders - this is the regression check for the
   `getSpecificPlayer` branch.
6. Check `~/Zomboid/Logs/` on both machines for errors mentioning `getOnlinePlayers`.

---

## Task 1: Fix the window check so broken glass fails

**Why first:** it is the smallest correctness fix, it is self-contained, and it changes what the
later per-building report will display. Doing it first means Task 3 never renders a stale verdict.

**The bug:** `squareWindowsRestored()` only inspects `IsoWindowFrame` (a window whose pane is gone
entirely). An `IsoWindow` that has been smashed - glass broken but frame intact - is never
examined, so it silently passes. A player can leave every window on the ground floor smashed and
the building still counts.

**The fix:** `IsoWindow` exposes smashed/glass-removed state. Verified in the installed source:

- `window:isSmashed()` - `client/ISUI/ISButtonPrompt.lua:822`, toggled at
  `client/DebugUIs/DebugContextMenu.lua:861`
- `window:isGlassRemoved()` - `client/DebugUIs/DebugContextMenu.lua:865`
- `window:isBarricaded()` - `shared/Moveables/ISMoveableSpriteProps.lua:882`

Per GOALS.md a window is acceptable when **boarded or replaced**. So a smashed pane passes only if
it has been barricaded.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua:84-97`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Replace `squareWindowsRestored` with the version that checks both object types**

Find the function at line 84 and replace the whole function, keeping the existing comment block
above it but updating it. The complete replacement, comment included:

```lua
-- REAL CHECK: ground-floor window state.
--
-- Two distinct objects represent a window, and BOTH must be checked - the
-- original version of this function only looked at IsoWindowFrame, so a
-- smashed-but-still-present pane passed silently and a crew could leave every
-- window on the ground floor broken with the building still counting.
--
-- IsoWindow: the pane is still there. It may be intact, smashed
-- (isSmashed(), client/ISUI/ISButtonPrompt.lua:822) or have had its glass
-- removed deliberately (isGlassRemoved(),
-- client/DebugUIs/DebugContextMenu.lua:865). GOALS.md accepts a window that is
-- "boarded or replaced", so a broken pane passes only when barricaded
-- (isBarricaded(), shared/Moveables/ISMoveableSpriteProps.lua:882).
--
-- IsoWindowFrame: the pane is gone outright, leaving a frame. hasWindow()
-- (client/DebugUIs/DebugContextMenu.lua:381) reports whether a replacement
-- pane was fitted; a boarded-over empty frame is also acceptable.
local function squareWindowsRestored(square)
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if obj then
			if instanceof(obj, "IsoWindowFrame") then
				if not obj:hasWindow() and not obj:isBarricaded() then
					return false
				end
			elseif instanceof(obj, "IsoWindow") then
				local broken = obj:isSmashed() or obj:isGlassRemoved()
				if broken and not obj:isBarricaded() then
					return false
				end
			end
		end
	end
	return true
end
```

Note the ordering: `IsoWindowFrame` is tested first because in this engine a frame is not an
`IsoWindow` subclass, but testing the more specific type first is defensive against that changing.

- [ ] **Step 2: Verify it parses**

Run:

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`, and the line for `TwoManCrew_Restoration.lua` reads `ok`.

- [ ] **Step 3: Verify no new diagnostics**

Run from the repo root:

```bash
"C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

If it instead reports an undefined-field warning on `isSmashed` or `isGlassRemoved`, that means
`types/pz.lua` lacks the stub. Add them to the `IsoWindow` class in `types/pz.lua` rather than
silencing the warning - see the repo's `CLAUDE.md` rule on the stub. The stub entries are:

```lua
---@return boolean
function IsoWindow:isSmashed() end

---@return boolean
function IsoWindow:isGlassRemoved() end
```

- [ ] **Step 4: Bump modversion in both files**

Set `modversion=0.1.6` in both `mod.info` files, then confirm they are identical:

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && diff two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info && echo IDENTICAL
```

Expected: `IDENTICAL`.

- [ ] **Step 5: Commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Fail the window check on smashed panes, not just empty frames"
```

If `types/pz.lua` was edited in Step 3, add it to the same commit.

- [ ] **Step 6: In-game check (this is the real test)**

This cannot be verified by any static tool. Load the game and confirm:

1. Claim a block, stand inside a claimed building.
2. Smash one ground-floor window (or find one already smashed).
3. Press **Check progress**.
4. Expected: that building does NOT count as restored.
5. Barricade the smashed window with planks.
6. Press **Check progress** again.
7. Expected: the window condition no longer blocks that building.

Check `~/Zomboid/Logs/` for Lua errors after each press. Any stack trace mentioning
`isSmashed` or `isGlassRemoved` means the method name is wrong for this build - re-grep the
installed source before proceeding.

---

## Task 2: Promote crew presence to a rule of its own

**Why:** furniture is out of scope by decision. But the crew-presence requirement currently exists
_only_ as the furniture fallback - the variable is literally named `furnishedDeclared`. Deleting
furniture without this task would silently remove the presence rule too, letting buildings flip to
restored with nobody there. The decision taken was to keep presence as its own rule.

This task is a rename plus a comment rewrite. Behaviour is deliberately unchanged; the point is
that the code now says what it means, so Task 3 can report it honestly.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua:151-162, 260-276, 315-333`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Replace the furniture fallback comment block**

Delete the entire comment block at lines 151-162 (it begins `-- FELL BACK: crew-built furniture
per room.` and ends `-- Implemented as furnishedDeclared() below rather than a per-square scan.`)
and replace it with:

```lua
-- CREW PRESENCE: a rule in its own right, not a fallback.
--
-- This used to stand in for "each room contains crew-built furniture". That
-- goal was dropped: the engine offers no way to tell crew-built furniture from
-- map-spawned furniture (no isPlayerBuilt marker exists anywhere in the
-- installed Lua source, and the Build 42 entity build path does not stamp
-- ModData - see ISBuildIsoEntity.lua, which never calls setModData).
--
-- Rather than delete the check along with the goal, the crew-presence half is
-- kept deliberately: a building counts as restored only while a crew member is
-- standing near it. Restoration is something the crew witnesses, not something
-- that happens off-screen. Implemented as crewPresentNear() below.
```

- [ ] **Step 2: Rewrite the `crewPresentNear` doc comment**

Replace the comment block immediately above `crewPresentNear` (lines 260-264, beginning
`-- FELL BACK check, standalone:`) with:

```lua
-- Is any crew member currently standing at the claimed building? This is the
-- crew-presence rule (see the block above). Uses CLAIM_PROXIMITY_RADIUS so
-- "close enough to witness" means the same distance everywhere in this file.
```

Leave the function body itself unchanged.

- [ ] **Step 3: Rename the variable and its reported field in `checkBuildingRestored`**

In `checkBuildingRestored`, replace the block currently at lines 315-333 with:

```lua
	-- Crew presence: a building only counts while someone is there to see it.
	local crewPresent = crewPresentNear(buildingEntry.x, buildingEntry.y)
	detail.crewPresent = crewPresent

	if status == "candidate_restored" and crewPresent then
		detail.status = "restored"
		return true, detail
	end

	if status == "candidate_restored" and not crewPresent then
		-- Windows, doors and corpses all pass, but nobody is there. Hold at
		-- unknown rather than failing a building that is otherwise finished -
		-- walking back to it must be able to complete it.
		detail.status = "unknown"
		detail.reason = "no crew member present - stand near the building and check again"
		return false, detail
	end

	detail.status = "not_restored"
	return false, detail
end
```

- [ ] **Step 4: Update the function's return-shape doc comment**

In the doc comment above `TwoManCrew.Server.checkBuildingRestored` (around line 282-292), change
the `detail:table` line so the field list matches reality:

```lua
--   detail:table   - { status = "restored"|"not_restored"|"unknown",
--                       windowsOk, doorsOk, noCorpses, crewPresent,
--                       roomsSeen, roomsTotal, fullyCovered, reason }
```

And change the `restored:bool` description's second sentence, which still mentions furniture, to:

```lua
--   restored:bool  - true only when every condition passed AND a crew member
--                     was present. false covers both "checked and failed" and
--                     "not yet checkable" so callers get a safe default;
--                     check detail.status for the real reason.
```

- [ ] **Step 5: Confirm no reference to the old name survives**

Run:

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && grep -rn "furnishedDeclared\|furnished" two-man-crew/Contents/mods/TwoManCrew/42/media/lua/
```

Expected: no output. If anything matches, it is a caller that must be updated in this task -
`TwoManCrew_Tiers.lua` is the likely one.

- [ ] **Step 6: Verify it parses and is diagnostic-clean**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 7: Bump modversion to 0.1.7 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Make crew presence an explicit restoration rule, drop the furniture pretence"
```

- [ ] **Step 8: In-game check**

Behaviour should be identical to before. Confirm no regression:

1. Stand in a finished building, press **Check progress** - it should count as before.
2. Check `~/Zomboid/Logs/` for errors.

---

## Task 3: Add a per-building detail report on the server

**Why:** this is the task that answers the original question. Everything needed already exists -
`checkBuildingRestored` returns a full `detail` table per building and `recheckClaim` throws all of
it away, keeping only a count. This adds a function that keeps it.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua` (append before the `OnClientCommand` handler near line 391)
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Add `getClaimDetail()` above the existing `OnClientCommand` function**

Insert this immediately before the line `-- Handles an on-demand client request to rescan the
claim`:

```lua
-- Builds a per-building report of the whole claim, for display.
--
-- recheckClaim() deliberately returns only a count, because that is all the
-- tier logic needs. This returns everything the checker actually computed, so
-- the journal can show WHICH building failed and WHY - previously all four
-- conditions collapsed into one number and the crew had no way to tell a
-- broken window from an unloaded chunk.
--
-- Cost: this re-walks every claimed building's ground floor, the same as
-- recheckClaim(). Call it on demand from a button, never from a tick.
--
-- Returns an array, one entry per claimed building, each:
--   { id, units, x, y,
--     status     = "restored"|"not_restored"|"unknown",
--     alreadyDone = boolean,  -- true if previously banked (see below)
--     windowsOk, doorsOk, noCorpses, crewPresent,  -- may be nil when unknown
--     roomsSeen, roomsTotal, reason }
function TwoManCrew.Server.getClaimDetail()
	local state = TwoManCrew.Server.getState()
	local claim = state.claim
	if not claim or not claim.buildings then return {} end

	claim.restored = claim.restored or {}

	local report = {}
	for _, entry in ipairs(claim.buildings) do
		local row = {
			id = entry.id,
			units = entry.units,
			x = entry.x,
			y = entry.y,
		}

		if claim.restored[entry.id] then
			-- Already banked. Restoration is an achievement, not a live-held
			-- state, so do not re-walk it and do not let a wandering corpse
			-- un-restore it - matching recheckClaim's contract.
			row.status = "restored"
			row.alreadyDone = true
		else
			local _, detail = TwoManCrew.Server.checkBuildingRestored(entry)
			row.alreadyDone = false
			row.status = detail.status or "unknown"
			row.windowsOk = detail.windowsOk
			row.doorsOk = detail.doorsOk
			row.noCorpses = detail.noCorpses
			row.crewPresent = detail.crewPresent
			row.roomsSeen = detail.roomsSeen
			row.roomsTotal = detail.roomsTotal
			row.reason = detail.reason
		end

		table.insert(report, row)
	end

	return report
end
```

- [ ] **Step 2: Extend the existing `OnClientCommand` to serve the new command**

Replace the whole existing `OnClientCommand` function (currently lines 394-407) with:

```lua
local function OnClientCommand(module, command, player, args)
	if module ~= TwoManCrew.MODULE then return end
	if not player then return end

	if command == "requestRestorationCheck" then
		local restoredCount = TwoManCrew.Server.recheckClaim()
		local claim = TwoManCrew.Server.getClaim()

		sendServerCommand(player, TwoManCrew.MODULE, "restorationChecked", {
			ok = claim ~= nil,
			restored = restoredCount,
			total = claim and #claim.buildings or 0,
		})
		return
	end

	if command == "requestClaimDetail" then
		-- Rescan first, so the detail shown is current rather than a snapshot
		-- of whenever the last tick ran.
		TwoManCrew.Server.recheckClaim()
		local claim = TwoManCrew.Server.getClaim()

		sendServerCommand(player, TwoManCrew.MODULE, "claimDetail", {
			ok = claim ~= nil,
			buildings = TwoManCrew.Server.getClaimDetail(),
		})
		return
	end
end
```

- [ ] **Step 3: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 4: Commit (no modversion bump yet - no player-visible change until Task 4)**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua
git commit -m "Add a per-building claim detail report on the server"
```

This is the one commit in this plan with no `modversion` bump, because nothing player-visible
changes until the client renders it in Task 5. The repo rule requires a bump for any change to a
mod's **behaviour**; a server function with no caller has none yet. Task 5 bumps for the pair.

---

## Task 4: Cache the detail on the client

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_TierReport.lua`

- [ ] **Step 1: Add the two cache fields after `tierProgressReceived`**

Insert after line 28 (`TwoManCrew.Client.tierProgressReceived = false`):

```lua
-- Last per-building claim detail from the server, as an array of rows (see
-- TwoManCrew.Server.getClaimDetail for the row shape). nil until the first
-- reply arrives.
TwoManCrew.Client.lastClaimDetail = nil

-- True once a claimDetail reply has arrived, so the renderer can distinguish
-- "waiting for the server" from "the server says there is no claim".
TwoManCrew.Client.claimDetailReceived = false
```

- [ ] **Step 2: Add the request function after `requestTierProgress`**

Insert after the closing `end` of `requestTierProgress` (line 35):

```lua
function TwoManCrew.Client.requestClaimDetail(player)
	player = player or getPlayer()
	if not player then return end

	sendClientCommand(player, TwoManCrew.MODULE, "requestClaimDetail", {})
end
```

- [ ] **Step 3: Handle the reply in `onServerCommand`**

Insert this block immediately before the line `if command ~= "tierProgress" then return end`:

```lua
	if command == "claimDetail" then
		TwoManCrew.Client.claimDetailReceived = true
		TwoManCrew.Client.lastClaimDetail = args.ok and args.buildings or nil
		return
	end
```

- [ ] **Step 4: Also refresh the detail after a "Check progress" press**

Inside the existing `if command == "restorationChecked"` block, immediately after the
`requestTierProgress` call, add:

```lua
		if TwoManCrew.Client.requestClaimDetail then
			TwoManCrew.Client.requestClaimDetail(player)
		end
```

- [ ] **Step 5: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 6: Commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_TierReport.lua
git commit -m "Cache per-building claim detail on the client"
```

---

## Task 5: Render the Buildings view in the journal

**Why:** this is where the crew finally sees it. The window currently has a two-way toggle
(Journal / Campaign). This makes it a three-way cycle.

**Design note:** the existing toggle is a single button whose label names the view it will switch
TO. With three views the label becomes the NEXT view in the cycle: Journal → Campaign →
Buildings → Journal.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Replace `onToggleView` with a three-way cycle**

Replace the whole existing `onToggleView` function (and its comment) with:

```lua
-- Cycles Journal -> Campaign -> Buildings -> Journal. The button label names
-- the view the NEXT press will switch to.
local VIEW_ORDER = { "journal", "campaign", "buildings" }
local VIEW_LABEL = {
	journal = "View: Journal",
	campaign = "View: Campaign",
	buildings = "View: Buildings",
}

local function nextView(current)
	for i, name in ipairs(VIEW_ORDER) do
		if name == current then
			return VIEW_ORDER[(i % #VIEW_ORDER) + 1]
		end
	end
	return VIEW_ORDER[1]
end

function TwoManCrewJournalWindow:onToggleView()
	self.activeView = nextView(self.activeView)
	self.viewButton:setTitle(VIEW_LABEL[nextView(self.activeView)])

	if self.activeView == "buildings" then
		if TwoManCrew.Client and TwoManCrew.Client.requestClaimDetail then
			TwoManCrew.Client.requestClaimDetail(getPlayer())
		end
	end

	self.lastSeenReport = nil
	self.lastSeenTierProgress = nil
	self.lastSeenClaimDetail = nil
end
```

- [ ] **Step 2: Fix the initial button label to match the cycle**

In `createChildren`, the button is created with the title `"View: Campaign"`. With
`activeView == "journal"`, the next press lands on `campaign`, so `"View: Campaign"` is already
correct. Leave it, but add a clarifying comment above the `viewButton` creation:

```lua
	-- Label names the view the next press switches to. Starting view is
	-- "journal", so the first press goes to Campaign.
```

- [ ] **Step 3: Add the `populateBuildings` renderer**

Insert this function immediately before the existing `function TwoManCrewJournalWindow:populate()`:

```lua
-- Renders one line per claimed building plus an indented reason line, so the
-- crew can see which building is blocked and on what.
--
-- Three statuses, deliberately distinct: DONE (banked), WORK (a real condition
-- failed) and ?? (not checkable right now - usually the ground is not loaded
-- because nobody is near it). Collapsing "unknown" into "not restored" was the
-- original defect; a crew could not tell a broken window from a far-away
-- building.
function TwoManCrewJournalWindow:populateBuildings()
	local detail = TwoManCrew.Client and TwoManCrew.Client.lastClaimDetail
	local received = TwoManCrew.Client and TwoManCrew.Client.claimDetailReceived
	self.list:clear()

	if not received then
		self.list:addItem("Asking the server...", nil)
		return
	end
	if not detail or #detail == 0 then
		self.list:addItem("No claim yet - press Claim a block.", nil)
		return
	end

	local done = 0
	for _, row in ipairs(detail) do
		if row.status == "restored" then done = done + 1 end
	end
	self.list:addItem(string.format("-- %d of %d restored --", done, #detail), nil)

	for i, row in ipairs(detail) do
		local mark = "??"
		if row.status == "restored" then
			mark = "DONE"
		elseif row.status == "not_restored" then
			mark = "WORK"
		end

		self.list:addItem(
			string.format("[%s] Building %d  (%s work units)", mark, i, tostring(row.units)),
			row
		)

		local reason = TwoManCrewJournalWindow.describeRow(row)
		if reason then
			self.list:addItem("      " .. reason, row)
		end
	end
end
```

- [ ] **Step 4: Add the `describeRow` helper above `populateBuildings`**

Insert immediately before `populateBuildings`:

```lua
-- Turns one detail row into a single human line explaining its status.
-- Returns nil when there is nothing useful to add (an already-banked
-- building needs no explanation).
function TwoManCrewJournalWindow.describeRow(row)
	if row.status == "restored" then
		return nil
	end

	-- An explicit server-supplied reason always wins - it is more specific
	-- than anything reconstructed from the flags.
	if row.reason then
		return row.reason
	end

	if row.status == "unknown" then
		if row.roomsSeen and row.roomsTotal and row.roomsSeen < row.roomsTotal then
			return string.format(
				"can't see it all (%d of %d rooms loaded) - walk closer",
				row.roomsSeen, row.roomsTotal
			)
		end
		return "not checkable right now - walk closer and check again"
	end

	local todo = {}
	if row.windowsOk == false then table.insert(todo, "windows") end
	if row.doorsOk == false then table.insert(todo, "doors") end
	if row.noCorpses == false then table.insert(todo, "corpses") end
	if row.crewPresent == false then table.insert(todo, "nobody here") end

	if #todo == 0 then
		return "blocked, but no condition reported - check the logs"
	end
	return "needs: " .. table.concat(todo, ", ")
end
```

- [ ] **Step 5: Route `populate()` to the new view**

Replace the existing `populate` function with:

```lua
function TwoManCrewJournalWindow:populate()
	if self.activeView == "campaign" then
		self:populateCampaign()
	elseif self.activeView == "buildings" then
		self:populateBuildings()
	else
		self:populateJournal()
	end
end
```

- [ ] **Step 6: Make `prerender` notice when the detail changes**

In `prerender`, replace the change-detection block with one that also watches the claim detail:

```lua
	local report = TwoManCrew.Client and TwoManCrew.Client.lastReport
	local tierProgress = TwoManCrew.Client and TwoManCrew.Client.lastTierProgress
	local claimDetail = TwoManCrew.Client and TwoManCrew.Client.lastClaimDetail
	if report ~= self.lastSeenReport
		or tierProgress ~= self.lastSeenTierProgress
		or claimDetail ~= self.lastSeenClaimDetail
	then
		self.lastSeenReport = report
		self.lastSeenTierProgress = tierProgress
		self.lastSeenClaimDetail = claimDetail
		self:populate()
	end
```

- [ ] **Step 7: Request detail on refresh too**

In `onRefresh`, after the `requestTierProgress` block, add:

```lua
	if TwoManCrew.Client and TwoManCrew.Client.requestClaimDetail then
		TwoManCrew.Client.requestClaimDetail(getPlayer())
	end
```

- [ ] **Step 8: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 9: Bump modversion to 0.1.8 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Show per-building restoration detail in the journal"
```

- [ ] **Step 10: In-game check (the real test for Tasks 3-5)**

1. Open the Crew Journal. Press the view button twice to reach **Buildings**.
2. Expected: a header line `-- N of M restored --` then one line per claimed building.
3. Stand far from the claim and press **Check progress**.
   Expected: most buildings read `[??]` with a "walk closer" reason.
4. Walk into a claimed building and press **Check progress**.
   Expected: that building's line changes - either `[DONE]`, or `[WORK]` with a `needs:` line
   naming windows, doors or corpses.
5. Check `~/Zomboid/Logs/` for Lua errors.

If the list is empty but a claim exists, the server reply is not arriving - check for a typo in
the command string `requestClaimDetail`, which must match exactly on both sides.

---

## Task 6: Capture building footprints at claim time

**Why:** tier 2 claims to require "three adjacent buildings" but actually counts any three. Real
adjacency needs each building's footprint, and claim entries currently store only a single sampled
point inside the building (`TwoManCrew_Campaign.lua:120-124`) - which is not enough to tell whether
two buildings touch.

**Why it is safe:** footprints come from `RoomDef` bounds via `def:getRooms()`, which is MetaGrid
data. Verified in use at `shared/Util/BuildingHelper.lua:9-20` and
`client/ISUI/AdminPanel/LootZed/SpawnRateChecker.lua:55-56`. No chunk loading, so this works for
buildings nobody has visited. `scoreBuilding` in the same file already walks `getRooms()` and reads
`room:getW()/getH()`, so the pattern is established here.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Campaign.lua`

- [ ] **Step 1: Add a `buildingBounds` helper immediately above `scoreBuilding`**

```lua
-- Returns a building's ground-plane footprint as x1, y1, x2, y2, derived from
-- the min/max of its rooms' bounds.
--
-- BuildingDef itself exposes no bounds getter anywhere in the installed Lua
-- source, but RoomDef does (getX/getX2/getY/getY2, used at
-- client/ISUI/AdminPanel/LootZed/SpawnRateChecker.lua:55-56), and a building
-- is the union of its rooms. All MetaGrid data, so this is readable for
-- buildings nobody has ever loaded.
--
-- Returns nil when the def has no usable rooms, so callers must handle it.
local function buildingBounds(def)
	local rooms = def:getRooms()
	if not rooms then return nil end

	local count = rooms:size()
	if count == 0 then return nil end

	local x1, y1, x2, y2
	for i = 0, count - 1 do
		local room = rooms:get(i)
		if room then
			local rx1, rx2 = room:getX(), room:getX2()
			local ry1, ry2 = room:getY(), room:getY2()
			if rx1 and rx2 and ry1 and ry2 then
				if not x1 or rx1 < x1 then x1 = rx1 end
				if not y1 or ry1 < y1 then y1 = ry1 end
				if not x2 or rx2 > x2 then x2 = rx2 end
				if not y2 or ry2 > y2 then y2 = ry2 end
			end
		end
	end

	if not x1 then return nil end
	return x1, y1, x2, y2
end
```

- [ ] **Step 2: Store the footprint on each claim entry**

In the survey loop, the entry is built at lines 119-124 as
`{ id = id, units = units, x = centreX + dx, y = centreY + dy }`. Replace that table construction
with:

```lua
						local bx1, by1, bx2, by2 = buildingBounds(def)
						found[id] = {
							id = id,
							units = units,
							x = centreX + dx,
							y = centreY + dy,
							-- Footprint, for adjacency (tier 2). nil when the
							-- def had no usable rooms; adjacency treats a nil
							-- footprint as "cannot prove adjacency" rather
							-- than guessing.
							x1 = bx1,
							y1 = by1,
							x2 = bx2,
							y2 = by2,
						}
```

Keep the surrounding lines (the `local id`, the `units` call, and the `table.insert(order, ...)`)
exactly as they are - only the table literal changes.

- [ ] **Step 3: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 4: Commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Campaign.lua
git commit -m "Record each claimed building's footprint at claim time"
```

- [ ] **Step 5: Note the migration consequence**

Existing saves have claims without footprints. Task 7 must treat a missing footprint as "adjacency
unprovable", never as an error. This is why Task 7's helper checks for nil first. Do not add a
migration - re-claiming is the supported path, and the campaign is early enough that this is
acceptable.

---

## Task 7: Make tier 2 adjacency real, rename tiers 3 and 4

**Why:** tier 2 counts any three restored buildings, and tiers 3 and 4 are both silently identical
to "restore everything". Three tiers that secretly test one condition is worse than three honest
ones.

**Decision taken:** make tier-2 adjacency genuine; rename tiers 3 and 4 to match what they
actually test rather than building a large-public-building detector and a perimeter sweep.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua`
- Modify: `two-man-crew/GOALS.md`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Add adjacency helpers above `evaluateBuildingTier`**

```lua
-- Two buildings are adjacent when their footprints touch or overlap once each
-- is expanded by ADJACENCY_GAP tiles. A street-facing row has gaps of a few
-- tiles between structures, so exact edge contact would almost never fire.
local ADJACENCY_GAP = 3

-- Footprints are recorded at claim time (TwoManCrew_Campaign.lua). Claims made
-- before that existed have no bounds; those buildings simply cannot prove
-- adjacency, which keeps tier 2 honest rather than guessing from centre points.
local function isAdjacent(a, b)
	if not a or not b then return false end
	if not a.x1 or not b.x1 then return false end

	local ax1, ay1 = a.x1 - ADJACENCY_GAP, a.y1 - ADJACENCY_GAP
	local ax2, ay2 = a.x2 + ADJACENCY_GAP, a.y2 + ADJACENCY_GAP

	return ax1 <= b.x2 and ax2 >= b.x1 and ay1 <= b.y2 and ay2 >= b.y1
end

-- Largest group of mutually-reachable restored buildings, where "reachable"
-- means linked by a chain of adjacent neighbours. A row of three houses in a
-- line counts even though the end houses do not touch each other.
--
-- Plain flood fill over the restored set. Claims are dozens of buildings at
-- most, so the O(n^2) neighbour scan is not worth optimising.
local function largestAdjacentGroup(claim)
	if not claim or not claim.buildings then return 0 end
	claim.restored = claim.restored or {}

	local restored = {}
	for _, entry in ipairs(claim.buildings) do
		if claim.restored[entry.id] then
			table.insert(restored, entry)
		end
	end
	if #restored == 0 then return 0 end

	local seen = {}
	local best = 0

	for i = 1, #restored do
		if not seen[i] then
			local stack = { i }
			seen[i] = true
			local size = 0

			while #stack > 0 do
				local current = table.remove(stack)
				size = size + 1
				for j = 1, #restored do
					if not seen[j] and isAdjacent(restored[current], restored[j]) then
						seen[j] = true
						table.insert(stack, j)
					end
				end
			end

			if size > best then best = size end
		end
	end

	return best
end
```

- [ ] **Step 2: Rewrite tiers 2, 3 and 4 in `evaluateBuildingTier`**

Replace the `elseif tier == 2 then` through the end of the `elseif tier == 4 then` block with:

```lua
	elseif tier == 2 then
		-- Real check: three restored buildings that form a connected run,
		-- using footprints captured at claim time. Previously this counted
		-- any three restored buildings anywhere on the block, which made
		-- "The Row" a lie.
		return largestAdjacentGroup(claim) >= 3
	elseif tier == 3 then
		-- Renamed to "Half the Block": this tests what it can actually
		-- verify. Identifying "the large public building" needs a building
		-- category the MetaGrid does not expose, so rather than keep a goal
		-- that silently meant something else, the tier now honestly asks for
		-- half the claim restored.
		local half = math.ceil(totalBuildings / 2)
		return totalBuildings > 0 and restoredCount >= half
	elseif tier == 4 then
		-- Renamed to "Every Door and Window": all buildings restored, which
		-- by definition means every ground-floor window is boarded or
		-- replaced and every doorway has a door. That is as close to "the
		-- perimeter is sealed" as this codebase can verify - there is no
		-- block-boundary sweep in the engine's Lua API.
		return totalBuildings > 0 and restoredCount >= totalBuildings
```

- [ ] **Step 3: Rename tiers 3 and 4 in `BUILDING_TIER_NAMES`**

Replace the table at line 86 with:

```lua
local BUILDING_TIER_NAMES = {
	[1] = "One House",
	[2] = "The Row",
	[3] = "Half the Block",
	[4] = "Every Door and Window",
	[5] = "The Rebuilt Town",
}
```

- [ ] **Step 4: Update `BUILDING_REMAINING_TEXT` for the renamed tiers**

In the `BUILDING_REMAINING_TEXT` table (line 373), set entries 2, 3 and 4 to:

```lua
	[2] = "restore three buildings that sit next to each other",
	[3] = "restore half the buildings on the claimed block",
	[4] = "restore every claimed building",
```

Leave entries 1 and 5 as they are.

- [ ] **Step 5: Correct GOALS.md**

In `two-man-crew/GOALS.md`, replace the five-tier table rows for tiers 3 and 4:

```markdown
| 3 | Half the Block | half the claimed block's buildings restored |
| 4 | Every Door and Window | every building restored - all doors hung, all windows sound |
```

Then, in the "What 'restored' means, concretely" section, replace the four bullets with:

```markdown
- every broken window on its ground floor is boarded or replaced
- every doorway has a working door
- no zombie corpse remains inside it
- a crew member is present to witness it
```

And replace the sentence beneath them:

```markdown
Each condition is observable from the game's own state, so the mod checks rather than takes the
player's word for it. The original fourth condition - crew-built furniture in every room - was
dropped: the engine gives no way to tell crew-built furniture from furniture the map spawned.
```

- [ ] **Step 6: Verify markdown formatting**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && npx prettier --check "two-man-crew/*.md"
```

Expected: `All matched files use Prettier code style!` If it fails, run the same command with
`--write` and re-check.

- [ ] **Step 7: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 8: Bump modversion to 0.1.9 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua two-man-crew/GOALS.md two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Make tier 2 adjacency real and rename tiers 3 and 4 to match their checks"
```

- [ ] **Step 9: In-game check**

1. Open the Campaign view.
2. Expected: tiers 3 and 4 now read "Half the Block" and "Every Door and Window".
3. With three restored buildings that are NOT neighbours, tier 2 should NOT be reached.
4. Restore three that sit together; tier 2 should then fire.

Point 3 needs an existing claim. Note that a claim made before Task 6 has no footprints, so tier 2
will never fire on it - re-claim to test properly.

---

## Task 8: Show the tier-5 hold countdown

**Why:** tier 5 requires holding the block for `TIER5_HOLD_NIGHTS` (7) nights after full
restoration, tracked in `tiersState.allRestoredSinceHours`. The crew cannot see any of it.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Expose the hold progress from `getTierProgress`**

Inside `TwoManCrew.Server.getTierProgress`, immediately before the `return {` statement, add:

```lua
	-- Tier 5's hold stretch, surfaced so the crew can see it counting down
	-- rather than waiting blind. nil until every building is restored, which
	-- is when allRestoredSinceHours is first stamped.
	local holdNightsDone, holdNightsNeeded
	if tiersState.allRestoredSinceHours then
		local elapsed = getGameTime():getWorldAgeHours() - tiersState.allRestoredSinceHours
		holdNightsDone = math.floor(elapsed / 24)
		holdNightsNeeded = TIER5_HOLD_NIGHTS
		if holdNightsDone > holdNightsNeeded then
			holdNightsDone = holdNightsNeeded
		end
	end
```

Then add these two fields to the returned table, after `buildingRemaining`:

```lua
		holdNightsDone = holdNightsDone,
		holdNightsNeeded = holdNightsNeeded,
```

- [ ] **Step 2: Update the `getTierProgress` doc comment**

In the shape comment above the function, add after the `buildingRemaining` line:

```lua
--     holdNightsDone         = number|nil,  -- tier 5 hold progress, nil until
--     holdNightsNeeded       = number|nil,  --   every building is restored
```

- [ ] **Step 3: Render it in the Campaign view**

In `TwoManCrew_JournalWindow.lua`, inside `populateCampaign`, immediately before the
`buildingRemaining` block, add:

```lua
	-- Tier 5's hold countdown. Only present once every building is restored.
	if type(progress.holdNightsDone) == "number"
		and type(progress.holdNightsNeeded) == "number"
	then
		self.list:addItem(
			string.format(
				"Holding the block: %d of %d nights",
				progress.holdNightsDone, progress.holdNightsNeeded
			),
			nil
		)
	end
```

- [ ] **Step 4: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 5: Bump modversion to 0.1.10 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Show the tier 5 hold countdown in the campaign view"
```

- [ ] **Step 6: In-game check**

The line only appears once every claimed building is restored, so on a fresh campaign it will be
absent - that is correct, not a bug. Confirm the Campaign view still renders with no errors in
`~/Zomboid/Logs/`.

---

## Task 9: Make the feeding trough check real (L1)

**Why:** L1 "The Pen" claims to require a fenced enclosure with a working feeding trough. It
actually checks `pensBuilt` (a tally nothing ever populates) and then falls back to "at least one
animal is anywhere near a player". A crew that has never built a pen reaches L1 by standing next
to a wild deer.

**The discovery that makes this fixable:** the existing comment says structures are "anonymous
IsoObjects once built". That is **wrong for troughs**. Verified in the installed source:

- `IsoFeedingTrough` is a real class - `client/FeedingTrough/CFeedingTroughSystem.lua:11`
- It has a **server-side global object system**, `SFeedingTroughSystem`, whose singleton is
  `SFeedingTroughSystem.instance` - used at `server/FeedingTrough/BuildingObjects/ISFeedingTrough.lua:8`
- That system enumerates every trough on the map regardless of chunk loading:
  `getLuaObjectCount()` and `getLuaObjectByIndex(index)` -
  `server/Map/SGlobalObjectSystem.lua:40-46`

A global object system is map-wide persistent state, not per-square simulation, so this is
readable for troughs nobody is standing near. That is what makes L1 a genuine check rather than a
proximity guess.

**Scope limit, stated honestly:** this verifies a trough exists on the claimed block. It does NOT
verify the enclosure is fenced - there is no verified fence-enclosure test in the engine's Lua
surface, and flood-filling for enclosure is out of scope here. L1's description is corrected in
Task 12 to say what it really tests.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Add a claim-bounds helper above the livestock section**

Insert immediately above the `-- Livestock counting` comment block (around line 129):

```lua
-- Bounding box of the whole claim, from the per-building footprints recorded
-- at claim time (TwoManCrew_Campaign.lua). Used to ask "is this structure on
-- our block?" without needing the ground loaded.
--
-- Returns nil when no claim exists or no building carries a footprint - which
-- is the case for claims made before footprints were recorded. Callers must
-- treat nil as "cannot judge location" rather than as "not on the block".
local function claimBounds(claim)
	if not claim or not claim.buildings then return nil end

	local x1, y1, x2, y2
	for _, entry in ipairs(claim.buildings) do
		if entry.x1 and entry.y1 and entry.x2 and entry.y2 then
			if not x1 or entry.x1 < x1 then x1 = entry.x1 end
			if not y1 or entry.y1 < y1 then y1 = entry.y1 end
			if not x2 or entry.x2 > x2 then x2 = entry.x2 end
			if not y2 or entry.y2 > y2 then y2 = entry.y2 end
		end
	end

	if not x1 then return nil end

	-- Pens and hutches sit beside the buildings, not inside them, so the claim
	-- box is widened before asking whether a structure belongs to this crew.
	local margin = 20
	return x1 - margin, y1 - margin, x2 + margin, y2 + margin
end
```

- [ ] **Step 2: Add the trough counter directly below `claimBounds`**

```lua
-- Counts feeding troughs standing on (or just beside) the claimed block.
--
-- Reads SFeedingTroughSystem, a server-side global object system
-- (server/FeedingTrough/SFeedingTroughSystem.lua), enumerated via
-- getLuaObjectCount/getLuaObjectByIndex (server/Map/SGlobalObjectSystem.lua:40-46).
-- Global object state is map-wide and persistent, so unlike a square scan this
-- sees troughs nobody is standing near.
--
-- Returns nil when the system is unavailable or the claim has no footprints,
-- so the caller can tell "none built" from "cannot tell".
local function countTroughsOnClaim(claim)
	if not SFeedingTroughSystem or not SFeedingTroughSystem.instance then
		return nil
	end

	local x1, y1, x2, y2 = claimBounds(claim)
	if not x1 then return nil end

	local system = SFeedingTroughSystem.instance
	local ok, count = pcall(function()
		local total = 0
		for i = 1, system:getLuaObjectCount() do
			local obj = system:getLuaObjectByIndex(i)
			-- getLuaObjectByIndex returns the object's ModData table, which
			-- carries its world position.
			if obj and obj.x and obj.y then
				if obj.x >= x1 and obj.x <= x2 and obj.y >= y1 and obj.y <= y2 then
					total = total + 1
				end
			end
		end
		return total
	end)

	if not ok then return nil end
	return count
end
```

- [ ] **Step 3: Verify the ModData position fields before trusting them**

`getLuaObjectByIndex` returns a ModData table, and this code assumes it carries `x` and `y`.
Confirm that against the installed source rather than trusting this plan:

```bash
grep -n "\.x\b\|\.y\b\|newLuaObject" "D:/Games/Steam/steamapps/common/ProjectZomboid/media/lua/server/FeedingTrough/SFeedingTroughGlobalObject.lua" | head -20
```

If the fields are named differently (for example nested under a position table), adjust the two
`obj.x` / `obj.y` reads in Step 2 to match. Do not guess - the `pcall` will swallow a wrong field
name into a `nil` result, which silently reads as "cannot tell" and would quietly disable L1.

If no position is exposed on the ModData at all, fall back to
`system:getLuaObjectAt(x, y, z)` probing is NOT viable across a whole block. In that case, stop
and report it: L1 stays a fallback and Task 12 must describe it as such.

- [ ] **Step 4: Rewrite stage 1 in `evaluateLivestockStage`**

Replace the whole `if stage == 1 then` branch with:

```lua
	if stage == 1 then
		-- Real check: a feeding trough standing on the claimed block, read
		-- from the server-side global object system so it works whether or
		-- not anyone is nearby.
		--
		-- Deliberately does NOT verify the enclosure is fenced - no verified
		-- enclosure test exists in the engine's Lua surface. The stage
		-- description says so rather than implying more than is checked.
		local troughs = countTroughsOnClaim(claim)
		if troughs ~= nil then
			return troughs >= 1
		end

		-- Could not read the trough system, or the claim predates footprints.
		-- Fall back to the old tally rather than failing outright.
		local tally = TwoManCrew.Server.getTally and TwoManCrew.Server.getTally()
		if tally and tally.pensBuilt and tally.pensBuilt > 0 then return true end
		return false
	elseif stage == 2 then
```

Note the deliberate removal of `return animalTotal >= 1` from the fallback: reaching "The Pen" by
standing near a wild animal was the bug.

- [ ] **Step 5: Pass the claim into `evaluateLivestockStage`**

The function signature is currently
`evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies)` and has no `claim`. Change
the signature to:

```lua
local function evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies, claim)
```

Then update its call site (near line 349) to pass the claim. Find the line calling
`evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies)` and add `, claim` before
the closing paren. The surrounding function already has a `claim` local - confirm with:

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && grep -n "local claim\|evaluateLivestockStage(" two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua
```

`evaluateTiers` already declares `local claim = TwoManCrew.Server.getClaim()` above the tier loop
(verified in the current file), so no new local is needed - just pass it through.

- [ ] **Step 6: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`. A warning about the undefined global
`SFeedingTroughSystem` means it needs a stub in `types/pz.lua`:

```lua
---@class SFeedingTroughSystem
---@field instance SFeedingTroughSystem
SFeedingTroughSystem = {}

---@return number
function SFeedingTroughSystem:getLuaObjectCount() end

---@param index number
---@return table
function SFeedingTroughSystem:getLuaObjectByIndex(index) end
```

- [ ] **Step 7: Bump modversion to 0.1.11 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Check for a real feeding trough on the claim instead of any nearby animal"
```

Include `types/pz.lua` if Step 6 required it.

- [ ] **Step 8: In-game check**

1. On a claim with no trough built, confirm L1 is NOT reached even with animals nearby.
2. Build a feeding trough on the claimed block.
3. Wait for the ten-minute tier tick, or press **Check progress** then reopen the Campaign view.
4. Expected: L1 "The Pen" now reads as reached.
5. Check `~/Zomboid/Logs/` for errors mentioning `SFeedingTroughSystem`.

---

## Task 10: Make the hutch check real (L3)

**Why:** L3 "The Hutch" checks `hutchesBuilt` (never populated) and falls back to "at least 2
animals near a player". Two wild rabbits reach it.

**What the engine offers, and its limit:** `IsoHutch` is a real class
(`client/ISUI/Hutch/ISHutchMenu.lua:12`, constructed at `server/BuildingObjects/ISHutch.lua:9`)
and exposes `getAnimalInside()` (`client/ISUI/Animal/ISDesignationAnimalZoneUI.lua:286`).

But unlike troughs, **hutches have no global object system** - verified by searching the whole
installed tree for a hutch system and finding none. So a hutch is only findable on a **loaded**
square. That is a real constraint, not a shortcut: L3 can only be confirmed while a crew member is
near the hutch.

This is acceptable because L3 is about a hutch being _occupied_, which the crew will be present
for. It is documented in the code so the next reader does not "fix" it into a false map-wide scan.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Extend the census to also find occupied hutches**

Replace the whole `censusNearbyAnimals` function with a version that reports hutches too. Note it
now scans the squares around each player rather than only the exact square the player stands on -
the original only ever looked at `player:getSquare()`, which meant an animal one tile away was
invisible.

```lua
-- Counts living animals, babies, and occupied hutches near online crew.
--
-- Two separate engine limits are at work here, and both are deliberate:
--
--   Animals: IsoAnimal instances live on IsoGridSquare, so only loaded ground
--   can be counted. This is the fallback census GOALS.md allows.
--
--   Hutches: IsoHutch has NO global object system - unlike IsoFeedingTrough,
--   which does (SFeedingTroughSystem). The whole installed source was searched
--   and no hutch system exists. So a hutch is findable only on a loaded
--   square. Do not "improve" this into a map-wide scan; there is no API for
--   one. L3 is therefore confirmable only while a crew member is near it.
--
-- Returns total, babies, occupiedHutches.
local function censusNearbyAnimals()
	local players = IsoPlayer.getPlayers()
	if not players then return 0, 0, 0 end

	local cell = getCell()
	local seen = {}
	local seenHutch = {}
	local total, babies, occupiedHutches = 0, 0, 0

	-- How far around each player to sweep. The original version read only the
	-- single square the player stood on, so an animal one tile away did not
	-- count.
	local radius = TwoManCrew.CREW_RADIUS

	for i = 0, players:size() - 1 do
		local player = players:get(i)
		if player then
			local px, py = player:getX(), player:getY()
			local pz = player:getZ() or 0
			for dx = -radius, radius do
				for dy = -radius, radius do
					local square = cell and cell:getGridSquare(px + dx, py + dy, pz)
					if square then
						local movers = square:getMovingObjects()
						if movers then
							for j = 0, movers:size() - 1 do
								local obj = movers:get(j)
								if obj and instanceof(obj, "IsoAnimal") and not seen[obj] then
									seen[obj] = true
									total = total + 1
									if obj:isBaby() then
										babies = babies + 1
									end
								end
							end
						end

						local objects = square:getObjects()
						if objects then
							for j = 0, objects:size() - 1 do
								local obj = objects:get(j)
								if obj and instanceof(obj, "IsoHutch") and not seenHutch[obj] then
									seenHutch[obj] = true
									local inside = obj:getAnimalInside()
									if inside and inside:size() > 0 then
										occupiedHutches = occupiedHutches + 1
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return total, babies, occupiedHutches
end
```

**Performance note:** this sweeps `(2*radius+1)^2` squares per player, which at
`CREW_RADIUS = 12` is 625 squares each. It runs on the ten-minute tier tick only, never per frame.
Do not call it from a per-tick handler.

- [ ] **Step 2: Rewrite stage 3 in `evaluateLivestockStage`**

Replace the whole `elseif stage == 3 then` branch with:

```lua
	elseif stage == 3 then
		-- Real check: a hutch with at least one animal inside it. Only
		-- confirmable while a crew member is near the hutch - IsoHutch has no
		-- global object system, so it cannot be found on unloaded ground.
		if occupiedHutches >= 1 then return true end

		-- Fallback only if some other feature ever populates the tally.
		local tally = TwoManCrew.Server.getTally and TwoManCrew.Server.getTally()
		if tally and tally.hutchesBuilt and tally.hutchesBuilt > 0 then return true end
		return false
```

Note the removal of `return animalTotal >= 2`, which was the bug.

- [ ] **Step 3: Thread `occupiedHutches` through the signature and call site**

Change the signature to:

```lua
local function evaluateLivestockStage(stage, tiersState, animalTotal, animalBabies, claim, occupiedHutches)
```

At the census call site (around line 345), capture the third return value:

```lua
		local animalTotal, animalBabies, occupiedHutches = censusNearbyAnimals()
```

And at the evaluation call, pass it as the sixth argument. Verify both with:

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && grep -n "censusNearbyAnimals()\|evaluateLivestockStage(" two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua
```

Expected: the definition plus one call each, and the call passing six arguments.

- [ ] **Step 4: Add the `IsoHutch` stub if diagnostics require it**

If the language server flags `getAnimalInside`, add to `types/pz.lua`:

```lua
---@class IsoHutch : IsoObject
IsoHutch = {}

---@return ArrayList
function IsoHutch:getAnimalInside() end
```

- [ ] **Step 5: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 6: Bump modversion to 0.1.12 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Require an occupied hutch for L3 instead of two nearby animals"
```

- [ ] **Step 7: In-game check**

1. With two wild animals nearby and no hutch, confirm L3 is NOT reached.
2. Build a chicken hutch and put a chicken in it.
3. Stand near it and wait for the tier tick.
4. Expected: L3 "The Hutch" reads as reached.
5. Check `~/Zomboid/Logs/` for errors mentioning `getAnimalInside`.

---

## Task 11: Add a Livestock detail view

**Why:** this is the livestock half of the original complaint. The four stages show as
`DONE` / `...` / `?` with no indication of what the game actually saw - how many animals, whether
a trough exists, whether a hutch is occupied, how far the herd countdown has run.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Note the staleness trap before editing**

`evaluateTiers` deliberately skips the census once all four livestock stages are reached, to avoid
paying for the per-square scan forever:

```lua
	local livestockRemaining = not (tiersState.livestock[1] and tiersState.livestock[2]
		and tiersState.livestock[3] and tiersState.livestock[4])
	if livestockRemaining then
```

That optimisation is correct for tier evaluation but wrong for display: a crew that finished L4
would see a frozen animal count forever. So the cached census written below must be **cleared**
rather than left stale when the census does not run. Step 2 does both halves.

- [ ] **Step 2: Cache the last census on the tier state so it can be reported**

The census runs inside `evaluateTiers` and is discarded. In `evaluateTiers`, immediately after the
line capturing the census results, add:

```lua
		-- Stash what the census actually saw, so getTierProgress can report it.
		-- Without this the crew sees a stage marked incomplete with no way to
		-- tell whether the game saw zero animals or simply could not look.
		tiersState.lastCensus = {
			animals = animalTotal,
			babies = animalBabies,
			occupiedHutches = occupiedHutches,
			troughs = countTroughsOnClaim(claim),
		}
```

Then, so the display never shows a frozen count, add an `else` branch to the
`if livestockRemaining then` block - immediately before its closing `end`:

```lua
	else
		-- Every stage is done, so the census no longer runs. Clear the cached
		-- figures rather than leaving the crew staring at a count frozen at
		-- the moment L4 completed.
		tiersState.lastCensus = nil
	end
```

- [ ] **Step 3: Expose the census and the herd countdown from `getTierProgress`**

Inside `TwoManCrew.Server.getTierProgress`, before the `return {`, add:

```lua
	-- L4's herd hold stretch, surfaced like tier 5's.
	local herdNightsDone, herdNightsNeeded
	if tiersState.herdSinceHours then
		local elapsed = getGameTime():getWorldAgeHours() - tiersState.herdSinceHours
		herdNightsDone = math.floor(elapsed / 24)
		herdNightsNeeded = L4_HERD_HOLD_NIGHTS
		if herdNightsDone > herdNightsNeeded then
			herdNightsDone = herdNightsNeeded
		end
	end

	local census = tiersState.lastCensus
```

Then add these fields to the returned table, after `livestockRemaining`:

```lua
		herdNightsDone = herdNightsDone,
		herdNightsNeeded = herdNightsNeeded,
		censusAnimals = census and census.animals,
		censusBabies = census and census.babies,
		censusHutches = census and census.occupiedHutches,
		censusTroughs = census and census.troughs,
```

- [ ] **Step 4: Update the `getTierProgress` shape comment**

Add after the `livestockRemaining` line in the doc comment:

```lua
--     herdNightsDone         = number|nil,  -- L4 hold progress, nil until a
--     herdNightsNeeded       = number|nil,  --   baby animal is present
--     censusAnimals          = number|nil,  -- what the last census saw; nil
--     censusBabies           = number|nil,  --   before the first census runs
--     censusHutches          = number|nil,  -- occupied hutches seen
--     censusTroughs          = number|nil,  -- troughs on the claim, nil if
--                                           --   the trough system was unreadable
```

- [ ] **Step 5: Render the livestock detail in the Campaign view**

In `populateCampaign`, immediately after the livestock stage loop and before the
`buildingRemaining` block, add:

```lua
	-- What the last census actually saw. Without this a stage reads as
	-- incomplete with no way to tell "saw zero animals" from "could not look".
	if type(progress.censusAnimals) == "number" then
		local line = string.format(
			"Last count: %d animals (%d young)",
			progress.censusAnimals, progress.censusBabies or 0
		)
		self.list:addItem(line, nil)
	end

	if type(progress.censusTroughs) == "number" then
		self.list:addItem(
			string.format("Feeding troughs on the block: %d", progress.censusTroughs),
			nil
		)
	elseif progress.censusAnimals ~= nil then
		self.list:addItem("Feeding troughs: could not read", nil)
	end

	if type(progress.censusHutches) == "number" then
		self.list:addItem(
			string.format("Occupied hutches seen: %d", progress.censusHutches),
			nil
		)
	end

	if type(progress.herdNightsDone) == "number"
		and type(progress.herdNightsNeeded) == "number"
	then
		self.list:addItem(
			string.format(
				"Herd held: %d of %d nights",
				progress.herdNightsDone, progress.herdNightsNeeded
			),
			nil
		)
	end
```

- [ ] **Step 6: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 7: Bump modversion to 0.1.13 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Show what the livestock census actually saw in the campaign view"
```

- [ ] **Step 8: In-game check**

1. Open the Campaign view with animals nearby.
2. Expected: a "Last count:" line naming a real number, and a trough count.
3. Move away from all animals, wait for the tier tick, reopen.
4. Expected: the count drops - proving it reflects a live census rather than a stored guess.
5. Check `~/Zomboid/Logs/` for errors.

---

## Task 12: Rename the livestock stages to match what they check

**Why:** the same honesty problem the building tiers had. L1 promises "a fenced enclosure with a
working feeding trough" but only verifies the trough. L2 promises an animal "kept inside the
claimed block" but the census counts any animal near a player, anywhere. L4 promises "a full
season, second generation born" but measures a fixed 30-night stretch with a baby present.

**Decision:** rename to what is verified, exactly as tiers 3 and 4 were.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua`
- Modify: `two-man-crew/GOALS.md`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Rename the stages**

Replace `LIVESTOCK_STAGE_NAMES` (line 94) with:

```lua
local LIVESTOCK_STAGE_NAMES = {
	[1] = "The Trough",
	[2] = "First Stock",
	[3] = "The Hutch",
	[4] = "The Herd",
}
```

Only L1 changes: "The Pen" implied a fenced enclosure that is never checked. L2, L3 and L4 keep
their names because, after Tasks 9 and 10, they now mean what they say.

- [ ] **Step 2: Update `LIVESTOCK_REMAINING_TEXT` to describe the real checks**

Replace the table (line 380) with:

```lua
local LIVESTOCK_REMAINING_TEXT = {
	[1] = "build a feeding trough on the claimed block",
	[2] = "keep at least one living animal near the crew",
	[3] = "build a hutch and put an animal in it, then stand near it",
	[4] = "keep a young animal alive near the crew for " .. L4_HERD_HOLD_NIGHTS .. " nights",
}
```

- [ ] **Step 3: Correct GOALS.md's livestock table**

Replace the four-stage table rows with:

```markdown
| L1 | The Trough | a feeding trough built on the claimed block |
| L2 | First Stock | at least one living animal kept near the crew |
| L3 | The Hutch | a hutch built and occupied, confirmed while standing near |
| L4 | The Herd | a young animal kept alive near the crew for 30 nights |
```

Then add this paragraph immediately below that table:

```markdown
These stages name what the mod can actually verify. Two engine limits shape them. Feeding troughs
have a server-side global object system, so a trough is detectable anywhere on the claim; hutches
do not, so a hutch is only detectable while a crew member is near it. Animals live on simulated
ground, so the animal count is a proximity census rather than a true block-wide survey - an animal
in an unloaded corner of the block is invisible, not absent.
```

- [ ] **Step 4: Verify markdown formatting**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && npx prettier --check "two-man-crew/*.md"
```

Expected: `All matched files use Prettier code style!` Run with `--write` and re-check if it fails.

- [ ] **Step 5: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 6: Bump modversion to 0.1.14 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Tiers.lua two-man-crew/GOALS.md two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Rename livestock stages to match what they actually verify"
```

- [ ] **Step 7: In-game check**

1. Open the Campaign view.
2. Expected: L1 reads "The Trough", and the "Next:" hint names building a trough.
3. Check `~/Zomboid/Logs/` for errors.

---

## Task 14: Fit the content without scrolling

**Why:** the list holds about 15 rows at the default window size. Seven claimed buildings rendered
as a header plus two lines each is 15 rows exactly - the last building falls off the bottom, and
the campaign view with its new census lines overflows too. The list box does support a scroll wheel
(`ISScrollingListBox:onMouseWheel`, `client/ISUI/ISScrollingListBox.lua:347`, wired up by
`instantiate()` calling `addScrollBars()` at `:53-64`), but reaching for the wheel to read a status
panel is friction the panel should not need. Fit the content instead.

Two changes, together roughly doubling what fits:

1. **Compact font.** `setFont(UIFont.NewSmall, 1)` shrinks both the glyphs and the row height.
   Verified: `ISScrollingListBox:setFont(font, padY)` sets `font`, `fontHgt` and `itemheight`
   together (`client/ISUI/ISScrollingListBox.lua:703-708`); vanilla passes `UIFont.Small` with a
   pad at `client/DebugUIs/DebugChunkState/DebugChunkStateUI.lua:115`, and puts `UIFont.NewSmall`
   on list boxes at `client/DebugUIs/DebugMenu/GlobalModData/GlobalModData.lua:42`.
2. **One-line reasons.** The Buildings view currently emits a row per building plus an indented
   reason row. Folding the reason onto the same line halves the row count.

Expected result at the default 440x320 window: about 19 rows visible instead of 15, and seven
buildings occupying 8 rows instead of 15.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Set the compact font on the list**

In `createChildren`, immediately after `self.list.drawBorder = true`, add:

```lua
	-- Compact font so a full claim fits without reaching for the scroll wheel.
	-- setFont sets the font, its height and the row height together
	-- (ISScrollingListBox.lua:703-708), so ROW must not be used for row height
	-- after this point - the list owns it now.
	self.list:setFont(UIFont.NewSmall, 1)
```

Then delete the line `self.list.itemheight = ROW` immediately above it. Leaving both would set the
row height twice, and the `ROW` value would win or lose depending on ordering - exactly the kind of
silent conflict that is hard to spot later.

- [ ] **Step 2: Fold the reason onto the building's own line**

In `populateBuildings`, replace the per-building loop body with:

```lua
	for i, row in ipairs(detail) do
		local mark = "??"
		if row.status == "restored" then
			mark = "DONE"
		elseif row.status == "not_restored" then
			mark = "WORK"
		end

		-- Reason goes on the same line rather than an indented second row.
		-- Two rows per building overflowed the list at seven buildings, and
		-- the panel should not need scrolling to be read.
		local line = string.format("[%s] %d. %s units", mark, i, tostring(row.units))
		local reason = TwoManCrewJournalWindow.describeRow(row)
		if reason then
			line = line .. " - " .. reason
		end

		self.list:addItem(line, row)
	end
```

- [ ] **Step 3: Shorten the reason strings so the folded line fits**

With the reason now sharing the line, the long forms clip at the panel edge. Replace the body of
`describeRow` with:

```lua
function TwoManCrewJournalWindow.describeRow(row)
	if row.status == "restored" then
		return nil
	end

	if row.reason then
		return row.reason
	end

	if row.status == "unknown" then
		if row.roomsSeen and row.roomsTotal and row.roomsSeen < row.roomsTotal then
			return string.format("only %d/%d rooms seen - walk closer", row.roomsSeen, row.roomsTotal)
		end
		return "too far - walk closer"
	end

	local todo = {}
	if row.windowsOk == false then table.insert(todo, "windows") end
	if row.doorsOk == false then table.insert(todo, "doors") end
	if row.noCorpses == false then table.insert(todo, "corpses") end
	if row.crewPresent == false then table.insert(todo, "nobody here") end

	if #todo == 0 then
		return "blocked - check the logs"
	end
	return "needs " .. table.concat(todo, ", ")
end
```

- [ ] **Step 4: Shorten the server-supplied reason to match**

The one server-side reason string is long enough to clip. In
`two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua`,
inside `checkBuildingRestored`, change:

```lua
		detail.reason = "no crew member present - stand near the building and check again"
```

to:

```lua
		detail.reason = "nobody here - stand inside it"
```

- [ ] **Step 5: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`. If `setFont` or `UIFont.NewSmall` is flagged,
add the stub to `types/pz.lua` rather than silencing it:

```lua
---@param font any
---@param padY number|nil
function ISScrollingListBox:setFont(font, padY) end
```

- [ ] **Step 6: Bump modversion to 0.1.15 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/TwoManCrew_Restoration.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Fit the journal list without scrolling: compact font, one-line reasons"
```

- [ ] **Step 7: In-game check**

1. Open the Buildings view on a claim of at least six buildings.
2. Expected: every building visible at once, no scrolling needed.
3. Expected: each line reads like `[WORK] 3. 6 units - needs windows, corpses`, with nothing
   clipped at the right edge.
4. Open the Campaign view.
5. Expected: all nine tier and stage rows plus the census lines fit without scrolling.
6. If anything still clips, the panel is too narrow for the longest reason - report the exact line
   rather than trimming text further, so the fix can be a wider default window instead.

---

## Task 15: Remove the redundant Check progress button

**Why:** the button forces an immediate rescan, which was genuinely the only way to avoid waiting
for the ten-minute tick. But Task 5 makes opening the Buildings view request that same rescan, so
the button now duplicates it. Removing it leaves three buttons sharing the width, which also gives
every label room to breathe.

**Important, so this is not "simplified" back later:** neither `Refresh` nor the Campaign view
rescans anything. `getTierProgress` only reads stored state, and `requestCrewReport` only re-sends
the last report. The rescan must keep happening somewhere, and after this task that somewhere is
the Buildings view. Do not remove the rescan from `onToggleView`.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Delete the button's creation**

In `createChildren`, delete the whole `self.checkButton` block, including its comment:

```lua
	-- Forces an immediate rescan of the claim. Without this button the server's
	-- requestRestorationCheck handler had no caller at all: restoration only
	-- ever updated on the ten-minute tick, and a crew that had just finished a
	-- house had no way to see it counted.
	self.checkButton = ISButton:new(
		PAD, 0, BUTTON_W, ROW,
		"Check progress", self, TwoManCrewJournalWindow.onCheckRestoration
	)
	self.checkButton:initialise()
	self:addChild(self.checkButton)
```

- [ ] **Step 2: Drop it from the layout row**

In `layout()`, change the buttons list from four entries to three:

```lua
	local buttons = { self.refreshButton, self.claimButton, self.viewButton }
```

- [ ] **Step 3: Keep the handler, and say why**

Do NOT delete `onCheckRestoration`. Replace its comment block with:

```lua
-- Asks the server to rescan the claim now rather than waiting for the ten-minute
-- tick. The server owns the verdict; this only requests it.
--
-- No longer bound to a button - opening the Buildings view triggers the rescan
-- instead (see onToggleView). Kept because it is the only on-demand rescan
-- entry point, and because the server's requestRestorationCheck handler would
-- otherwise have no caller at all.
```

- [ ] **Step 4: Have the Buildings view force the rescan, not just fetch detail**

In `onToggleView`, replace the Buildings branch with:

```lua
	-- Entering the Buildings view forces a fresh rescan, which is what the
	-- removed "Check progress" button used to do. Requesting the detail alone
	-- would render whatever the last ten-minute tick happened to leave behind.
	if self.activeView == "buildings" then
		self:onCheckRestoration()
		if TwoManCrew.Client and TwoManCrew.Client.requestClaimDetail then
			TwoManCrew.Client.requestClaimDetail(getPlayer())
		end
	end
```

Note `requestClaimDetail` already rescans server-side before replying (Task 3, Step 2), so this is
belt and braces; the explicit call also makes the halo message appear, which tells the crew the
scan happened.

- [ ] **Step 5: Confirm nothing still references the deleted button**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && grep -rn "checkButton" two-man-crew/Contents/mods/TwoManCrew/42/media/lua/
```

Expected: no output.

- [ ] **Step 6: Verify parse and diagnostics**

```bash
cd two-man-crew && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

- [ ] **Step 7: Bump modversion to 0.1.16 in both files and commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "Drop the Check progress button now the Buildings view rescans on open"
```

- [ ] **Step 8: In-game check**

1. Expected: three buttons - Refresh, Claim a block, View - each noticeably wider than before.
2. Switch to the Buildings view.
3. Expected: the "Checking the claim..." halo message appears, and the list reflects a fresh scan.
4. Finish a building, switch away from Buildings and back.
5. Expected: it counts immediately rather than after up to ten minutes.

---

## Task 16: Final verification pass

- [ ] **Step 1: Run all three gates one final time**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && node check-lua.mjs
```

Expected: `29/29 parsed`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && "C:/Users/ionut/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: `Diagnosis completed, no problems found`.

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && npx prettier --check "*.md" "docs/*.md" "two-man-crew/*.md"
```

Expected: `All matched files use Prettier code style!`

- [ ] **Step 2: Confirm both mod.info files agree and read 0.1.16**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && diff two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info && grep modversion two-man-crew/Contents/mods/TwoManCrew/mod.info
```

Expected: no diff output, then `modversion=0.1.16`.

- [ ] **Step 3: Confirm no Claude attribution entered any commit**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && git log --format='%B' 4e8980c..HEAD | grep -i -E "claude|co-authored|generated with" && echo "FOUND - REMOVE IT" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 4: Confirm the installed game copy was never touched**

```bash
grep modversion "$USERPROFILE/Zomboid/mods/TwoManCrew/mod.info"
```

Expected: `modversion=0.1.0`. If this reads anything else, the pinned install was overwritten -
restore it from commit `84a7152` per the process in `CLAUDE.md`.

- [ ] **Step 5: Full in-game pass**

Load the game and walk the whole feature:

1. Claim a block (re-claim if the existing claim predates Task 6).
2. Journal view: entries render as before.
3. Campaign view: tiers 3 and 4 show their new names.
4. Buildings view: one line per building, with a status and a reason.
5. Walk to a building, press **Check progress**, confirm its line updates.
6. Campaign view: L1 reads "The Trough", and the census lines show real numbers.
7. Confirm L1 is not reached without a trough built, and L3 is not reached without an
   occupied hutch.
8. `~/Zomboid/Logs/` contains no Lua errors from this session.

Only after step 7 passes is this plan complete. Everything before it is a syntax-level claim.

---

## Deliberately out of scope

- **Crew-built furniture detection.** Dropped by decision. Would need a build-time hook the Build
  42 entity path does not offer, plus a separate singleplayer path, and could never credit
  anything already built.
- **A unit test harness.** The code under change calls PZ engine globals that do not exist outside
  the running game. Building a mock layer is its own project.
- **Upper floors.** Every check here is ground floor only, matching the existing checker and
  GOALS.md's wording.
- **A real perimeter sweep for tier 4.** No block-boundary barricade API exists in the engine's
  Lua surface; the tier was renamed instead.
- **Fenced-enclosure detection for L1.** Verifying that a pen is actually enclosed needs a
  flood-fill over fence segments with no engine support behind it. L1 checks for a real feeding
  trough instead, and is named "The Trough" so it does not imply more.
- **A map-wide hutch scan.** `IsoFeedingTrough` has a server-side global object system;
  `IsoHutch` has none - the whole installed tree was searched. L3 is therefore only confirmable
  while a crew member is near the hutch, and the code says so.
- **A true block-wide animal survey.** Animals live on simulated ground, so an animal in an
  unloaded corner of the claim is invisible. The census stays a proximity count, now reported
  honestly rather than presented as a full survey.
- **Real season length for L4.** No verified season-length getter exists, so L4 keeps its fixed
  30-night stretch and the goal text says nights rather than seasons.
