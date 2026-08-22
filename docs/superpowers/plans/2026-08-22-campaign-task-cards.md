# Campaign Task Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat Campaign list in the Crew Journal with tabbed task cards that expand into a per-condition checklist, under a custom skin.

**Architecture:** One client file changes. A pure `buildCards()` function turns the server data the client already holds into card tables; a custom `doDrawItem` paints each card and sets its own row height; a click handler toggles expansion and rebuilds the list. `ISTabPanel` replaces the cycling View button. The test stub is extended first, because it currently disagrees with the real engine API.

**Tech Stack:** Lua 5.1 (Kahlua), Project Zomboid Build 42.20.3 UI classes, fengari-based test harness in `two-man-crew/test-ui.mjs`.

---

> **STATUS: written, NOT TESTED. Branch `feature/campaign-task-cards`, 2026-08-22, version `0.3.1` at start.**
>
> **This code has never been executed.** No Project Zomboid session has loaded
> it. Nothing below is known to work.
>
> What actually ran: nothing yet. When the tasks below are done, what will have
> run is `npm run check` (luaparse) and `npm test` (the UI under fengari). None
> of that executes a line of the mod inside the game. It is proofreading, not
> testing: it cannot catch a wrong method name, a nil at runtime, a wrong event,
> or a UI that draws garbage.
>
> Every in-game check is OPEN.

## Context for the implementer

**What the mod is.** TwoManCrew is a Project Zomboid Build 42 co-op mod. Two
players claim a block and restore its buildings while keeping livestock alive.
Multiplayer is the default assumption: code paths differ between host and remote
client, `sendServerCommand` reaches nobody in singleplayer, and files under
`server/` are also loaded on clients.

**The design this implements.** Read
`docs/superpowers/specs/2026-08-22-campaign-task-cards-design.md` first. It
carries the palette, the three-mark rule, the ladder threshold and the full API
citation table. Do not re-derive those decisions.

**The constraint that will be violated if you forget it.** Chunk loading. A
building far from any player is _unreadable_, not unrestored:
`getCell():getGridSquare(x, y, z)` returns `nil` for unloaded ground. The
three-state verdict (`restored` / `not_restored` / `unknown`) is load-bearing and
must never be collapsed to a boolean. In the UI this is the `?` mark, and it is
not decoration.

**The language is Lua 5.1.** No `goto`, no `table.unpack` (use `unpack`), no
integer division `//`, no bitwise operators. The harness deliberately removes
`xpcall` because Kahlua lacks it.

**How verification works here.** There is no unit-test harness for engine code in
the general case, because it calls globals that exist only inside the running
game. What does exist is `two-man-crew/test-ui.mjs`, which runs the mod's real Lua
under fengari against a hand-written stub of PZ. Extending that stub is Task 1 and
is not optional: the stub currently disagrees with the real engine, so tests
written against it today would prove the wrong thing. Do not invent a second
harness.

**Repo rules that bind you.**

- Adding cases to `test-ui.mjs` is authoring a test. Invoke
  `superpowers:test-driven-development` before the first one.
- Never run `lua-language-server` from a subagent: it is whole-repo and reports
  other agents' in-progress edits as phantom errors.
- Do not edit `mod.info` or commit if you are a subagent. The controller does
  both, once, at the end.
- Every draw call is written against the cited signature. `drawRect` takes alpha
  **before** rgb; `drawText` takes it **last**. They are inconsistent.

**Which sub-skill implements this plan.** `superpowers:executing-plans`
(sequential; every task touches the same file) or
`superpowers:subagent-driven-development`. Because this is a single-file change,
parallel file-partitioned agents do not apply.

## File structure

| File                                                              | Responsibility                                 | Change |
| ----------------------------------------------------------------- | ---------------------------------------------- | ------ |
| `two-man-crew/test-ui.mjs`                                        | PZ stub + behavioural tests                    | Modify |
| `.../42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua` | Window, skin, cards, tabs, expansion           | Modify |
| `two-man-crew/Contents/mods/TwoManCrew/mod.info`                  | `modversion`                                   | Modify |
| `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`               | `modversion`, must stay identical to the above | Modify |

No server file changes. Every field the cards read is already sent.

---

### Task 0: Branch

**Files:** none

- [ ] **Step 1: Create the branch**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
git checkout -b feature/campaign-task-cards
```

- [ ] **Step 2: Confirm the gates pass before any edit**

```bash
cd two-man-crew && npm run check && npm test
```

Expected: both exit 0. If they do not, stop and report - you are not starting from
a clean baseline.

---

### Task 1: Make the test stub match the real engine

The stub's list box disagrees with the game: `addItem` stores a `data` key,
returns nothing, and never sets `height`. The real one stores `item`, returns the
row table, and sets `i.height = self.itemheight`
(`ISScrollingListBox.lua:141-152`). Tests written against today's stub would pass
while the mod broke in-game.

**Files:**

- Modify: `two-man-crew/test-ui.mjs` (the `STUB` string, near lines 174-183)

- [ ] **Step 1: Invoke the TDD skill**

Adding cases to `test-ui.mjs` is authoring a test. Invoke
`superpowers:test-driven-development` now, before writing any of it.

- [ ] **Step 2: Replace the list box stub**

Find the block beginning `ISScrollingListBox = ISUIElement:derive` and replace it
through the `addItem` line with:

```lua
ISScrollingListBox = ISUIElement:derive("ISScrollingListBox")
function ISScrollingListBox:new(x, y, w, h)
  local o = ISUIElement.new(self, x, y, w, h)
  o.items = {}
  o.itemheight = 20
  o.selected = -1
  o.drawBorder = false
  o.scrollHeight = 0
  return o
end
function ISScrollingListBox:setFont(f, pad)
  self.fontHgt = 16
  self.itemheight = self.fontHgt + (pad or 0) * 2
end
function ISScrollingListBox:clear()
  self.items = {}
  self.scrollHeight = 0
end

-- Mirrors ISScrollingListBox.lua:141-152 - stores `item`, sets `height`,
-- and RETURNS the row table so callers can override the height.
function ISScrollingListBox:addItem(name, item)
  local i = { text = name, item = item, height = self.itemheight }
  table.insert(self.items, i)
  self.scrollHeight = self.scrollHeight + i.height
  return i
end

-- Mirrors ISScrollingListBox.lua:66 - walks per-item heights.
function ISScrollingListBox:rowAt(x, y)
  local y0 = 0
  for i, v in ipairs(self.items) do
    if not v.height then v.height = self.itemheight end
    if y >= y0 and y < y0 + v.height then return i end
    y0 = y0 + v.height
  end
  return -1
end

-- Mirrors ISScrollingListBox.lua:277 and :287.
function ISScrollingListBox:setOnMouseDownFunction(target, fn)
  self.target = target
  self.onmousedown = fn
end
function ISScrollingListBox:invokeOnMouseDownFunction()
  if self.onmousedown and self.items[self.selected] then
    self.onmousedown(self.target, self.items[self.selected].item)
  end
end
function ISScrollingListBox:onMouseDown(x, y)
  if #self.items == 0 then return end
  local row = self:rowAt(x, y)
  if row > #self.items then row = #self.items end
  if row < 1 then return end
  self.selected = row
  self:invokeOnMouseDownFunction()
end
function ISScrollingListBox:doDrawItem(y, item, alt)
  return y + (item.height or self.itemheight)
end
```

- [ ] **Step 3: Add the missing draw primitive and text measure**

`drawRectBorder` is never stubbed, and `MeasureStringY` is missing. Add
`drawRectBorder` next to `drawRect`:

```lua
function ISUIElement:drawRectBorder(x, y, w, h, a, r, g, b)
  table.insert(DRAWN, { kind = "border", x = x, y = y, w = w, h = h, a = a })
end
```

And replace the `getTextManager` stub with:

```lua
function getTextManager()
  return { MeasureStringX = function(_, _, s) return #tostring(s) * 6 end,
           MeasureStringY = function() return 16 end,
           getFontHeight = function() return 16 end }
end
```

- [ ] **Step 4: Add the ISTabPanel stub**

Add after the `ISButton` block. Mirrors `ISTabPanel.lua:484` and `:438`.

```lua
ISTabPanel = ISUIElement:derive("ISTabPanel")
function ISTabPanel:new(x, y, w, h)
  local o = ISUIElement.new(self, x, y, w, h)
  o.viewList = {}
  o.tabHeight = 20
  o.equalTabWidth = false
  return o
end
function ISTabPanel:setEqualTabWidth(v) self.equalTabWidth = v end
function ISTabPanel:setCenterTabs(v) self.centerTabs = v end
function ISTabPanel:addView(name, view)
  local vo = { name = name, id = #self.viewList + 1, view = view }
  table.insert(self.viewList, vo)
  view:setY(self.tabHeight)
  self:addChild(view)
  view.parent = self
  view:setVisible(#self.viewList == 1)
  if #self.viewList == 1 then self.activeView = vo end
end
function ISTabPanel:activateView(name)
  for _, vo in ipairs(self.viewList) do
    vo.view:setVisible(vo.name == name)
    if vo.name == name then self.activeView = vo end
  end
end
function ISTabPanel:getActiveView()
  return self.activeView and self.activeView.view
end
```

- [ ] **Step 5: Run the existing tests to prove the stub change broke nothing**

```bash
cd two-man-crew && npm test
```

Expected: PASS. The current window calls `addItem(text, data)` and never reads
back the return value, so the key rename from `data` to `item` cannot affect it.
If anything fails, the failure is real - fix it before continuing.

- [ ] **Step 6: Commit**

```bash
git add two-man-crew/test-ui.mjs
git commit -m "test: make the PZ list box stub match the real engine API"
```

---

### Task 2: The skin token table

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [ ] **Step 1: Add the palette near the other constants**

Insert after the `local ICON = 28` line. Values are the spec's hex converted to
the 0..1 floats the engine takes.

```lua
-- Work Order skin. The engine takes colour components as 0..1 floats, so each
-- entry below is the spec's hex divided by 255. Kept in one table because a
-- colour repeated inline in twenty draw calls is a colour that drifts.
--
-- See docs/superpowers/specs/2026-08-22-campaign-task-cards-design.md for the
-- hex values and what each role means.
local SKIN = {
	ground  = { r = 0.078, g = 0.071, b = 0.055 }, -- #14120E window body
	panel   = { r = 0.118, g = 0.106, b = 0.082 }, -- #1E1B15 list background
	rule    = { r = 0.227, g = 0.196, b = 0.145 }, -- #3A3225 dividers
	ruleLit = { r = 0.353, g = 0.294, b = 0.196 }, -- #5A4B32 borders
	text    = { r = 0.863, g = 0.835, b = 0.769 }, -- #DCD5C4 primary text
	dim     = { r = 0.549, g = 0.514, b = 0.443 }, -- #8C8371 secondary text
	faint   = { r = 0.384, g = 0.357, b = 0.298 }, -- #625B4C locked
	active  = { r = 0.784, g = 0.569, b = 0.235 }, -- #C8913C current task
	done    = { r = 0.498, g = 0.659, b = 0.361 }, -- #7FA85C met
	blocked = { r = 0.706, g = 0.341, b = 0.290 }, -- #B4574A failed
	unread  = { r = 0.431, g = 0.541, b = 0.627 }, -- #6E8AA0 unknown
}

-- Card geometry.
local CARD_PAD = 6
local SPINE_W = 3
local LADDER_H = 7
local CHECK_ROW_H = 14

-- Above this many required units a ladder stops being readable, so the card
-- draws a continuous bar instead. Only the 7- and 30-night holds exceed it.
local LADDER_MAX = 12
```

- [ ] **Step 2: Run the parser**

```bash
cd two-man-crew && npm run check
```

Expected: PASS, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: add the work order skin palette to the journal window"
```

---

### Task 3: `buildCards()` - the pure model

This is the one genuinely testable unit: server fields in, card tables out, no
engine calls. Everything the UI draws comes from here.

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Test: `two-man-crew/test-ui.mjs`

- [ ] **Step 1: Write the failing test**

Add to `test-ui.mjs`, in the Lua test script section alongside the existing
window tests:

```lua
-- buildCards turns server data into cards. Pure: no engine calls, so it is
-- the one part of this UI that can be tested for real.
local cards = TwoManCrewJournalWindow.buildCards({
  buildingRemaining = "restore three buildings that sit next to each other",
  buildingTier = 3,
  livestockRemaining = "build a hutch and put an animal in it, then stand near it",
  livestockStage = 3,
  censusAnimals = 2, censusBabies = 0, censusHutches = 0, censusTroughs = 1,
}, {
  { status = "restored",     units = 12 },
  { status = "restored",     units = 8 },
  { status = "not_restored", units = 15, windowsOk = false, doorsOk = false },
  { status = "unknown",      units = 6,  roomsSeen = 2, roomsTotal = 5 },
})

TEST("buildCards returns a building card first", cards[1] and cards[1].track == "building")
TEST("building card counts only restored", cards[1].done == 2 and cards[1].target == 3)
TEST("building card carries one check per building", #cards[1].checks == 4)
TEST("restored building is marked yes", cards[1].checks[1].mark == "yes")
TEST("failed building is marked no", cards[1].checks[3].mark == "no")
TEST("failed building names its reason", cards[1].checks[3].why == "needs windows, doors")
TEST("unreadable building is marked unknown, not failed", cards[1].checks[4].mark == "unknown")
TEST("livestock card is present", cards[2] and cards[2].track == "livestock")
TEST("occupied hutch check fails at zero", cards[2].checks[3].mark == "no")
TEST("cards start collapsed", cards[1].expanded == false)
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd two-man-crew && npm test
```

Expected: FAIL, `attempt to call field 'buildCards' (a nil value)` or the TEST
lines reporting false.

- [ ] **Step 3: Implement `buildCards`**

Add above `populateCampaign`. `describeRow` already exists in this file and is
reused rather than reimplemented.

```lua
-- Turns the two server payloads the client already holds into a list of cards.
--
-- Pure by design: no getCell, no getPlayer, no drawing. That is what makes it
-- testable under the fengari harness, and it is why every engine-touching
-- decision below is a field read rather than a lookup.
--
-- A card is:
--   { key, track, task, context, state, done, target, checks = {...}, expanded }
-- A check is:
--   { mark = "yes"|"no"|"unknown", label = string, why = string|nil }
--
-- The three marks are not two. "unknown" means the ground was not loaded and
-- nothing could be read, which is a different fact from a failed condition -
-- see the chunk-loading note in the plan's context section.
function TwoManCrewJournalWindow.buildCards(progress, detail)
	local cards = {}
	progress = progress or {}

	-- Building track. One check per claimed building, so the card explains
	-- itself rather than asserting a number.
	if type(progress.buildingRemaining) == "string" and progress.buildingRemaining ~= "" then
		local checks = {}
		local done = 0
		for i, row in ipairs(detail or {}) do
			local mark = "unknown"
			if row.status == "restored" then
				mark = "yes"
				done = done + 1
			elseif row.status == "not_restored" then
				mark = "no"
			end
			table.insert(checks, {
				mark = mark,
				label = string.format("Building %d - %s units", i, tostring(row.units)),
				why = TwoManCrewJournalWindow.describeRow(row),
			})
		end

		local tier = progress.buildingTier or 0
		table.insert(cards, {
			key = "building",
			track = "building",
			task = progress.buildingRemaining,
			context = "Tier " .. tostring(tier) .. " of 5",
			state = "active",
			done = done,
			target = math.max(#checks, done),
			checks = checks,
			expanded = false,
		})
	end

	-- Livestock track. The census numbers stop being a free-floating block and
	-- become the conditions they actually gate.
	if type(progress.livestockRemaining) == "string" and progress.livestockRemaining ~= "" then
		local function countCheck(value, label, singular)
			if type(value) ~= "number" then
				return { mark = "unknown", label = label, why = "could not read" }
			end
			if value > 0 then
				return { mark = "yes", label = label, why = value .. " " .. singular }
			end
			return { mark = "no", label = label, why = "0 " .. singular }
		end

		local checks = {
			countCheck(progress.censusTroughs, "A feeding trough on the block", "seen"),
			countCheck(progress.censusAnimals, "A living animal near the crew", "seen"),
			countCheck(progress.censusHutches, "An occupied hutch", "seen"),
			countCheck(progress.censusBabies, "A young animal", "seen"),
		}

		local done = 0
		for _, c in ipairs(checks) do
			if c.mark == "yes" then done = done + 1 end
		end

		table.insert(cards, {
			key = "livestock",
			track = "livestock",
			task = progress.livestockRemaining,
			context = "Stage " .. tostring(progress.livestockStage or 0) .. " of 4",
			state = done > 0 and "blocked" or "active",
			done = done,
			target = #checks,
			checks = checks,
			expanded = false,
		})
	end

	return cards
end
```

- [ ] **Step 4: Run the tests**

```bash
cd two-man-crew && npm test
```

Expected: PASS, all ten new TEST lines true.

- [ ] **Step 5: Commit**

```bash
git add two-man-crew/test-ui.mjs "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: derive campaign task cards from the data the client already holds"
```

---

### Task 4: Draw a card

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [ ] **Step 1: Add the card renderer**

`doDrawItem` receives `(y, item, alt)` and must return the y of the next row.
Setting `item.height` inside it is exactly what vanilla's recipe list does at
`ISRecipeScrollingListBox.lua:191`.

```lua
-- Colour for a card's spine and its task text, by state.
local STATE_COLOUR = {
	active  = SKIN.active,
	done    = SKIN.done,
	blocked = SKIN.blocked,
	locked  = SKIN.faint,
}

local MARK_GLYPH = { yes = "x", no = "!", unknown = "?" }
local MARK_COLOUR = { yes = SKIN.done, no = SKIN.blocked, unknown = SKIN.unread }

-- Draws one card, and its checks when it is open.
--
-- Returns the next row's y, and sets item.height so rowAt() can hit-test a
-- tall card correctly - the same contract vanilla's recipe list uses
-- (ISRecipeScrollingListBox.lua:191).
--
-- Alpha positions differ between the two calls used here and that is not a
-- typo: drawRect takes alpha BEFORE rgb (ISUIElement.lua:1191), drawText takes
-- it LAST (ISUIElement.lua:1293).
function TwoManCrewJournalWindow:drawCard(y, item, alt)
	local card = item.item
	if not card then
		return y + (item.height or self.itemheight)
	end

	local lineH = getTextManager():getFontHeight(UIFont.NewSmall)
	local top = y
	local x = CARD_PAD + SPINE_W + 4
	local w = self.width

	-- Body, alternating so adjacent cards separate without a heavy rule.
	local bg = alt and SKIN.panel or SKIN.ground
	self:drawRect(0, y, w, self:cardHeight(card), 1, bg.r, bg.g, bg.b)

	local state = STATE_COLOUR[card.state] or SKIN.faint

	-- Spine: the card's state as colour, read before anything is parsed.
	self:drawRect(CARD_PAD, y + 2, SPINE_W, self:cardHeight(card) - 4, 1, state.r, state.g, state.b)

	-- Chevron plus the task itself.
	local chevron = card.expanded and "v" or ">"
	self:drawText(chevron, x, y + 2, SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)

	local taskColour = (card.state == "locked" or card.state == "done") and SKIN.dim or SKIN.text
	self:drawText(card.task, x + 12, y + 2, taskColour.r, taskColour.g, taskColour.b, 1, UIFont.NewSmall)

	-- Count, right-aligned.
	local count = card.state == "locked" and "locked"
		or (tostring(card.done) .. " / " .. tostring(card.target))
	local cw = getTextManager():MeasureStringX(UIFont.NewSmall, count)
	self:drawText(count, w - CARD_PAD - cw, y + 2, SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)

	y = y + lineH + 4

	-- Progress. A ladder while the target is small enough to count, a
	-- continuous bar once it is not - see LADDER_MAX.
	local barW = w - x - CARD_PAD
	local target = card.target or 0
	if target > 0 and target <= LADDER_MAX then
		local gap = 2
		local cellW = (barW - (target - 1) * gap) / target
		for i = 1, target do
			local cx = x + (i - 1) * (cellW + gap)
			local filled = i <= (card.done or 0)
			local c = filled and SKIN.done or SKIN.ground
			self:drawRect(cx, y, cellW, LADDER_H, 1, c.r, c.g, c.b)
			self:drawRectBorder(cx, y, cellW, LADDER_H, 1, SKIN.ruleLit.r, SKIN.ruleLit.g, SKIN.ruleLit.b)
		end
	else
		self:drawRect(x, y, barW, LADDER_H, 1, SKIN.ground.r, SKIN.ground.g, SKIN.ground.b)
		if target > 0 and (card.done or 0) > 0 then
			local fw = barW * (card.done / target)
			self:drawRect(x, y, fw, LADDER_H, 1, SKIN.active.r, SKIN.active.g, SKIN.active.b)
		end
		self:drawRectBorder(x, y, barW, LADDER_H, 1, SKIN.ruleLit.r, SKIN.ruleLit.g, SKIN.ruleLit.b)
	end
	y = y + LADDER_H + 3

	-- Context line, so the ladder is never anonymous.
	if card.context then
		self:drawText(card.context, x, y, SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)
		y = y + lineH
	end

	-- The checks, only while the card is open.
	if card.expanded then
		for _, chk in ipairs(card.checks or {}) do
			local mc = MARK_COLOUR[chk.mark] or SKIN.dim
			self:drawText(MARK_GLYPH[chk.mark] or "?", x + 8, y, mc.r, mc.g, mc.b, 1, UIFont.NewSmall)
			self:drawText(chk.label, x + 22, y, SKIN.dim.r, SKIN.dim.g, SKIN.dim.b, 1, UIFont.NewSmall)
			if chk.why then
				local ww = getTextManager():MeasureStringX(UIFont.NewSmall, chk.why)
				self:drawText(chk.why, w - CARD_PAD - ww, y, SKIN.faint.r, SKIN.faint.g, SKIN.faint.b, 1, UIFont.NewSmall)
			end
			y = y + CHECK_ROW_H
		end
	end

	-- Bottom rule.
	self:drawRect(0, y + 1, w, 1, 1, SKIN.rule.r, SKIN.rule.g, SKIN.rule.b)

	item.height = self:cardHeight(card)
	return top + item.height
end

-- How tall a card is, open or closed. Height is computed in one place so the
-- drawing and the hit-testing can never disagree about where a card ends.
function TwoManCrewJournalWindow:cardHeight(card)
	local lineH = getTextManager():getFontHeight(UIFont.NewSmall)
	local h = lineH + 4 + LADDER_H + 3 + 2
	if card.context then h = h + lineH end
	if card.expanded then
		h = h + #(card.checks or {}) * CHECK_ROW_H
	end
	return h
end
```

- [ ] **Step 2: Run the parser**

```bash
cd two-man-crew && npm run check
```

Expected: PASS, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: draw campaign objectives as task cards with a progress ladder"
```

---

### Task 5: Click to expand

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Test: `two-man-crew/test-ui.mjs`

- [ ] **Step 1: Write the failing test**

```lua
-- Clicking a card toggles it open, and the row grows so the next click still
-- lands on the right card.
local w = OPEN_JOURNAL()
w.activeView = "campaign"
w.cards = TwoManCrewJournalWindow.buildCards(
  { buildingRemaining = "restore one building fully", buildingTier = 1 },
  { { status = "not_restored", units = 9, doorsOk = false } })
w:populateCampaign()

local firstHeight = w.list.items[1].height
TEST("card starts collapsed", w.cards[1].expanded == false)

w:onCardClicked(w.cards[1])
TEST("clicking a card opens it", w.cards[1].expanded == true)

w:populateCampaign()
TEST("an open card is taller", w.list.items[1].height > firstHeight)

w:onCardClicked(w.cards[1])
TEST("clicking again closes it", w.cards[1].expanded == false)
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd two-man-crew && npm test
```

Expected: FAIL, `attempt to call method 'onCardClicked' (a nil value)`.

- [ ] **Step 3: Implement the handler**

```lua
-- Toggles a card open or shut and rebuilds the list.
--
-- The scroll offset is captured and restored around the rebuild: clearing a
-- list resets its scroll, so without this, opening the last card would jump the
-- view back to the top and hide the thing just clicked.
function TwoManCrewJournalWindow:onCardClicked(card)
	if not card or card.expanded == nil then return end
	card.expanded = not card.expanded

	local offset = self.list.yScroll or 0
	self:populateCampaign()
	self.list.yScroll = offset
end
```

- [ ] **Step 4: Run the tests**

```bash
cd two-man-crew && npm test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add two-man-crew/test-ui.mjs "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: open a task card into its checklist on click"
```

---

### Task 6: Rewrite `populateCampaign` to emit cards

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [ ] **Step 1: Replace the body of `populateCampaign`**

Replace the whole existing function - the tier list, the census block and both
`Next:` lines all go. Their content now reaches the player through cards.

```lua
-- Rebuilds the Orders list from the last server reply.
--
-- Everything the old flat version printed is still shown, but as structure
-- rather than as nineteen equal rows: the task is the card's headline, the
-- census numbers are the checks inside it, and the tier name is the context
-- line under the ladder.
function TwoManCrewJournalWindow:populateCampaign()
	local progress = TwoManCrew.Client and TwoManCrew.Client.lastTierProgress
	local received = TwoManCrew.Client and TwoManCrew.Client.tierProgressReceived
	local detail = TwoManCrew.Client and TwoManCrew.Client.lastClaimDetail

	self.list:clear()

	if not received then
		self.list:addItem("Requesting campaign progress...", nil)
		return
	end
	if not progress then
		self.list:addItem("No claim yet - press the flag button to claim a block.", nil)
		return
	end

	-- Rebuild the cards only when there are none, so an open card stays open
	-- across a redraw. A server refresh replaces them via onRefresh.
	if not self.cards then
		self.cards = TwoManCrewJournalWindow.buildCards(progress, detail)
	end

	if #self.cards == 0 then
		self.list:addItem("Every objective is complete. Hold the block.", nil)
		return
	end

	for _, card in ipairs(self.cards) do
		local row = self.list:addItem(card.task, card)
		row.height = self:cardHeight(card)
	end
end
```

- [ ] **Step 2: Wire the list to the card renderer and the click handler**

In `createChildren`, after `self.list.drawBorder = true`, add:

```lua
	-- Cards are drawn by this window, not by the default row renderer, and a
	-- click has to reach the card it landed on. Both are engine hooks:
	-- ISScrollingListBox.lua:304 for the draw, :277 for the click.
	self.list.doDrawItem = function(listSelf, y, item, alt)
		if item.item and item.item.checks then
			return TwoManCrewJournalWindow.drawCard(listSelf, y, item, alt)
		end
		return ISScrollingListBox.doDrawItem(listSelf, y, item, alt)
	end

	self.list:setOnMouseDownFunction(self, function(target, item)
		if item and item.checks then
			target:onCardClicked(item)
		end
	end)
```

- [ ] **Step 3: Drop the stale card set whenever fresh data arrives**

In `onRefresh`, and in `onToggleView`, add alongside the existing
`self.lastSeenTierProgress = nil` lines:

```lua
	self.cards = nil
```

- [ ] **Step 4: Run both gates**

```bash
cd two-man-crew && npm run check && npm test
```

Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: render the campaign view as task cards"
```

---

### Task 7: Tabs replace the View button

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`
- Test: `two-man-crew/test-ui.mjs`

- [ ] **Step 1: Write the failing test**

```lua
local w2 = OPEN_JOURNAL()
TEST("the window has a tab panel", w2.tabs ~= nil)
TEST("four tabs are registered", w2.tabs and #w2.tabs.viewList == 4)
TEST("Orders is the first tab", w2.tabs.viewList[1].name == "Orders")
TEST("the cycling View button is gone", w2.viewButton == nil)
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd two-man-crew && npm test
```

Expected: FAIL - `w2.tabs` is nil and `viewButton` still exists.

- [ ] **Step 3: Build the tab panel**

In `createChildren`, delete the `self.viewButton = self:makeIconButton(...)`
block entirely, then add after the list is created:

```lua
	-- Four named views instead of one button cycling through three states.
	-- The old button's third state was undiscoverable: reaching Buildings meant
	-- pressing until it appeared. addView/activateView verified at
	-- ISTabPanel.lua:484 and :438; vanilla drives it the same way in ISChat.lua:830.
	self.tabs = ISTabPanel:new(PAD, top + ROW, self.width - PAD * 2, ROW)
	self.tabs:initialise()
	self.tabs:setEqualTabWidth(true)
	self:addChild(self.tabs)

	self.tabs:addView("Orders", self.list)
	self.tabs:addView("Buildings", self.buildingsList)
	self.tabs:addView("Livestock", self.livestockList)
	self.tabs:addView("Journal", self.journalList)
```

Create the three extra lists immediately before that block, each built exactly
like `self.list` but without being added to the window directly - `addView`
re-parents them:

```lua
	local function makeList()
		local l = ISScrollingListBox:new(0, 0, self.width - PAD * 2, ROW)
		l:initialise()
		l:instantiate()
		l:setFont(UIFont.NewSmall, 1)
		l.selected = -1
		l.drawBorder = true
		return l
	end

	self.buildingsList = makeList()
	self.livestockList = makeList()
	self.journalList = makeList()
```

- [ ] **Step 4: Point the populate functions at their own lists**

`populateJournal` currently writes to `self.list`. Change its first line to use
`self.journalList`, and `populateBuildings` to use `self.buildingsList`. Replace
the `populate` dispatcher with one that fills every tab, since a tab switch is
handled by the panel rather than by rebuilding:

```lua
-- Fills every tab. The tab panel decides which one is visible, so all four are
-- kept current rather than rebuilt on switch.
function TwoManCrewJournalWindow:populate()
	self:populateCampaign()
	self:populateBuildings()
	self:populateJournal()
end
```

- [ ] **Step 5: Delete the now-dead toggle code**

Remove `VIEW_ORDER`, `VIEW_LABEL`, `nextView`, `onToggleView` and every reference
to `self.activeView`. The tab panel owns which view is showing.

Keep `onCheckRestoration`. It is still the rescan entry point and is now called
from `onRefresh`.

- [ ] **Step 6: Update `layout()` for two buttons and the tab strip**

In `layout`, change the button list and give the tab panel the space the list
used to take:

```lua
	local buttons = { self.refreshButton, self.claimButton }
```

and, after the list geometry is computed, size the panel rather than the list:

```lua
	self.tabs:setX(PAD)
	self.tabs:setY(listY)
	self.tabs:setWidth(self.width - PAD * 2)
	self.tabs:setHeight(listH)

	-- Every view sits below the tab strip and fills what is left.
	local innerH = listH - self.tabs.tabHeight
	if innerH < ROW then innerH = ROW end
	for _, vo in ipairs(self.tabs.viewList) do
		vo.view:setX(0)
		vo.view:setY(self.tabs.tabHeight)
		vo.view:setWidth(self.width - PAD * 2)
		vo.view:setHeight(innerH)
	end
```

- [ ] **Step 7: Run both gates**

```bash
cd two-man-crew && npm run check && npm test
```

Expected: both PASS, including the four new tab tests.

- [ ] **Step 8: Commit**

```bash
git add two-man-crew/test-ui.mjs "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: replace the cycling view button with four named tabs"
```

---

### Task 8: Skin the window chrome

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [ ] **Step 1: Set the base colours**

At the top of `createChildren`, right after
`ISCollapsableWindow.createChildren(self)`:

```lua
	-- The base class paints its title bar and body from these two tables
	-- (ISCollapsableWindow.lua:152-166 and :179-197), so restyling the chrome
	-- is an assignment rather than an override fight.
	self.backgroundColor = { r = SKIN.ground.r, g = SKIN.ground.g, b = SKIN.ground.b, a = 0.95 }
	self.borderColor = { r = SKIN.ruleLit.r, g = SKIN.ruleLit.g, b = SKIN.ruleLit.b, a = 1 }
```

- [ ] **Step 2: Add the amber rule under the title**

In `prerender`, after the existing header text is drawn, add:

```lua
	-- A single amber rule under the title, the one bright line in the window.
	-- It is what makes the panel read as a posted work order rather than a
	-- system dialog.
	local ty = self:titleBarHeight()
	self:drawRect(0, ty, self.width, 1, 1, SKIN.active.r, SKIN.active.g, SKIN.active.b)
	self:drawRect(0, ty + 1, self.width, 1, 1, SKIN.rule.r, SKIN.rule.g, SKIN.rule.b)
```

- [ ] **Step 3: Recolour the existing header text**

In `prerender`, change the three `drawText` colour triplets that currently use
literals to draw from `SKIN` instead: the claim line uses `SKIN.active`, the
refusal line `SKIN.blocked`, and the no-claim hint `SKIN.dim`. Keep alpha last -
that is `drawText`'s signature.

- [ ] **Step 4: Run both gates**

```bash
cd two-man-crew && npm run check && npm test
```

Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: skin the journal window as a work order"
```

---

### Task 9: Version bump and close out

**Controller only.** A subagent must not perform this task.

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [ ] **Step 1: Bump both copies to 0.4.0**

New behaviour, so minor rather than patch. Both files must match - they have
drifted once already.

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew/Contents/mods/TwoManCrew"
sed -i 's/^modversion=0\.3\.1$/modversion=0.4.0/' mod.info 42/mod.info
grep -H modversion mod.info 42/mod.info
```

Expected: both print `modversion=0.4.0`.

- [ ] **Step 2: Run every gate one final time**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && npm run check && npm test
cd "d:/Dropbox/Apps/Project Zomboid" && npx prettier --check "docs/superpowers/plans/*.md" "docs/superpowers/specs/*.md"
```

Expected: all pass.

- [ ] **Step 3: Run the language server, from the repo root**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && lua-language-server --check=. --checklevel=Warning
```

Expected: no new diagnostics. Never "fix" the pre-existing atan2 or
duplicate-set-field warnings.

- [ ] **Step 4: Commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "chore: bump modversion to 0.4.0 for the campaign task cards"
```

- [ ] **Step 5: Update this plan's status banner**

Change the banner to record what actually ran. Name the checks; do not imply the
mod works. Every in-game check stays OPEN until a real load.

- [ ] **Step 6: Report honestly**

The closing report says `Unverified: not loaded in Project Zomboid`. The gates
that ran are proofreading. Do not claim the panel works, looks right, or that the
click targets land - none of that has been observed.

Ask the player for one run with the Journal open on the Orders tab, and for a
screenshot. If a fault appears, the repo rule applies: instrumentation first, fix
second. `npm run diagnose` reads the newest log and prints the command chain.

---

## Deployment note

Do **not** run `node deploy.mjs` without asking. The install is deliberately
pinned at `0.1.0` to match the other player in a co-op save, and deploying
replaces it. Deploying while the game is running replaces the mod folder under a
live session.

## Self-review

**Spec coverage.** Tabs: Task 7. Task cards: Tasks 3, 4, 6. Ladder rule and the
12-unit threshold: Task 2 (constant), Task 4 (both branches). Expand/collapse:
Task 5. Three marks including `unknown`: Task 3, asserted by test. Skin tokens:
Task 2; chrome: Task 8. Scroll restoration risk: Task 5. Offsets derived from the
text manager rather than constants: Task 4. Version bump in both `mod.info`
copies: Task 9. No server file is touched by any task, matching the spec's scope.

**Placeholders.** None. Every code step carries the code, every command carries
its expected output.

**Type consistency.** `buildCards` returns cards with `checks`, and the click
filter, the draw dispatcher and `cardHeight` all key off `checks` being present.
`drawCard` and `cardHeight` are the only two functions computing card geometry,
and `drawCard` calls `cardHeight` rather than recomputing, so they cannot
disagree. Card fields used in Task 4 (`state`, `task`, `context`, `done`,
`target`, `expanded`, `checks`) are all set in Task 3.

**Known gap, deliberate.** `describeRow` returns `nil` for a restored building,
so a `yes` check carries no `why`. Task 4 already guards on `chk.why` before
drawing it.
