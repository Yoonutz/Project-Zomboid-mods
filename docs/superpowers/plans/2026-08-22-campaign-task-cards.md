# Campaign Task Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat Campaign list in the Crew Journal with tabbed task cards that expand into a per-condition checklist, under a custom skin.

**Architecture:** One client file changes. A pure `buildCards()` turns the server data the client already holds into card tables; a custom `doDrawItem` paints each card and sets its own row height; a click handler toggles expansion and rebuilds the list. `ISTabPanel` replaces the cycling View button.

**Tech Stack:** Lua 5.1 (Kahlua), Project Zomboid Build 42.20.3 UI classes.

---

> **STATUS: all tasks written, NOT TESTED. Branch `feature/campaign-task-cards`, 2026-08-22, version `0.4.0`.**
>
> **This code has never been executed.** No Project Zomboid session has loaded
> it. Nothing here is known to work.
>
> What actually ran: `npm run check` (luaparse, 29/29 parsed) and `prettier`
> over this repo's own markdown. Neither executes a line of the mod. They are
> proofreading: they cannot catch a wrong method name, a nil at runtime, a wrong
> event, or a UI that draws garbage.
>
> `lua-language-server` did NOT run - it is not on PATH in this environment.
> That gate is unchecked, not passed.
>
> Every in-game check is OPEN. Specifically unverified: whether the tabs appear
> and switch, whether a click opens a card, whether the ladder and the skin draw
> correctly, and whether the Livestock tab has contents.

## Change of approach, 2026-08-22

This plan originally carried a test task and per-task test steps, written against
`two-man-crew/test-ui.mjs` - a fengari harness that ran the mod's Lua against a
hand-written fake of the engine.

**That harness was deleted by the owner's decision** partway through execution, on
the grounds that a fake engine only proves the fake agrees with itself. The `test`
script and the `fengari` dependency went with it.

Consequences, and they are not cosmetic:

- There is no local suite. `npm run check` is the only gate, and it executes
  nothing.
- Do **not** rebuild a harness, a mock, or a probe file. See
  `.claude/memory/pz-verification-is-ingame-only.md`.
- Every remaining task is verified by parser plus reading the diff, and the work
  is reported `Unverified` until a real game run.

Tasks 0 to 4 were completed while the harness still existed, so they were
red-green tested at the time. Those tests no longer exist. Treat that code as
unverified like everything else.

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
integer division `//`, no bitwise operators, no `xpcall`.

**Every draw call is written against the cited signature.** `drawRect` takes alpha
**before** rgb (`ISUIElement.lua:1191`); `drawText` takes it **last**
(`ISUIElement.lua:1293`). They are inconsistent and this repo has been bitten.

## File structure

| File                                                              | Responsibility                                 | Change |
| ----------------------------------------------------------------- | ---------------------------------------------- | ------ |
| `.../42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua` | Window, skin, cards, tabs, expansion           | Modify |
| `two-man-crew/Contents/mods/TwoManCrew/mod.info`                  | `modversion`                                   | Modify |
| `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`               | `modversion`, must stay identical to the above | Modify |

No server file changes. Every field the cards read is already sent.

---

## Completed

- [x] **Task 0: Branch.** `feature/campaign-task-cards` created off `master`.
- [x] **Task 1: Test harness.** Done, then deleted with the harness. Void.
- [x] **Task 2: Skin palette.** `SKIN` table plus `CARD_PAD`, `SPINE_W`,
      `LADDER_H`, `CHECK_ROW_H`, `LADDER_MAX`. Commit `ee42a8a`.
- [x] **Task 3: `buildCards()`.** Pure model turning tier progress and claim
      detail into cards with per-condition checks. Commit `c0bd122`.
- [x] **Task 4: `drawCard()` and `cardHeight()`.** Custom row rendering with the
      state spine, the ladder-or-bar rule, and the expanded checklist. Commit
      `9d59bcc`.

---

### Task 5: Click to expand - DONE

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [x] **Step 1: Add the handler**

Place it directly above `populateCampaign`.

```lua
-- Toggles a card open or shut and rebuilds the list.
--
-- The scroll offset is captured and restored around the rebuild, because
-- clearing a list resets its scroll: without this, opening the last card would
-- jump the view back to the top and hide the very thing just clicked.
function TwoManCrewJournalWindow:onCardClicked(card)
	if not card or card.expanded == nil then return end
	card.expanded = not card.expanded

	local offset = self.list.yScroll or 0
	self:populateCampaign()
	self.list.yScroll = offset
end
```

- [x] **Step 2: Run the parser**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && npm run check
```

Expected: `29/29 parsed`.

- [x] **Step 3: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: open a task card into its checklist on click"
```

---

### Task 6: Rewrite `populateCampaign` to emit cards - DONE

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [x] **Step 1: Replace the whole existing function**

The tier list, the census block and both `Next:` lines all go. Their content
still reaches the player, as cards rather than as undifferentiated rows.

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

	-- Rebuilt only when absent, so an open card stays open across a redraw.
	-- Fresh server data clears self.cards, which is what forces a rebuild.
	if not self.cards then
		self.cards = TwoManCrewJournalWindow.buildCards(progress, detail)
	end

	if #self.cards == 0 then
		self.list:addItem("Every objective is complete. Hold the block.", nil)
		return
	end

	for _, card in ipairs(self.cards) do
		local row = self.list:addItem(card.task, card)
		if row then row.height = self:cardHeight(card) end
	end
end
```

- [x] **Step 2: Wire the list to the renderer and the click handler**

In `createChildren`, immediately after `self.list.drawBorder = true`:

```lua
	-- Cards are drawn by this window, not by the default row renderer, and a
	-- click has to reach the card it landed on. Both are engine hooks:
	-- ISScrollingListBox.lua:304 for the draw, :277 for the click.
	--
	-- Rows carrying a plain string (the "no claim yet" placeholders) still fall
	-- through to the stock renderer, so an empty state cannot crash the panel.
	local window = self
	self.list.doDrawItem = function(listSelf, y, item, alt)
		if item and item.item and item.item.checks then
			return window.drawCard(window, y, item, alt)
		end
		return ISScrollingListBox.doDrawItem(listSelf, y, item, alt)
	end

	self.list:setOnMouseDownFunction(self, function(target, item)
		if item and item.checks then
			target:onCardClicked(item)
		end
	end)
```

- [x] **Step 3: Drop the stale card set when fresh data arrives**

In `onRefresh`, beside the existing `self.lastSeenTierProgress = nil`:

```lua
	self.cards = nil
```

- [x] **Step 4: Run the parser**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && npm run check
```

Expected: `29/29 parsed`.

- [x] **Step 5: Read the diff**

With no suite, the diff is the evidence. Confirm by eye that `populateCampaign`
no longer emits tier or census rows, that `drawCard` is reached only for rows
whose item has `checks`, and that `self.cards` is cleared in `onRefresh`.

```bash
git diff -- "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
```

- [x] **Step 6: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: render the campaign view as task cards"
```

---

### Task 7: Tabs replace the cycling View button - DONE

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [x] **Step 1: Create the three extra lists**

In `createChildren`, before the tab panel. Each is built exactly like
`self.list`; `addView` re-parents them, so none is added to the window directly.

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

- [x] **Step 2: Build the tab panel**

```lua
	-- Four named views instead of one button cycling through three states. The
	-- old button's third state was undiscoverable: reaching Buildings meant
	-- pressing until it appeared. addView/activateView verified at
	-- ISTabPanel.lua:484 and :438; vanilla drives it the same way at
	-- ISChat.lua:830 and ISFluidDebugWindow.lua:55-67.
	self.tabs = ISTabPanel:new(PAD, top + ROW, self.width - PAD * 2, ROW)
	self.tabs:initialise()
	self.tabs:setEqualTabWidth(true)
	self:addChild(self.tabs)

	self.tabs:addView("Orders", self.list)
	self.tabs:addView("Buildings", self.buildingsList)
	self.tabs:addView("Livestock", self.livestockList)
	self.tabs:addView("Journal", self.journalList)
```

- [x] **Step 3: Delete the View button and the toggle machinery**

Remove the `self.viewButton = self:makeIconButton(...)` block, and remove
`VIEW_ORDER`, `VIEW_LABEL`, `nextView`, `onToggleView`, and every reference to
`self.activeView`. The tab panel owns which view is showing.

Keep `onCheckRestoration`: it is still the rescan entry point.

- [x] **Step 4: Point each populate function at its own list**

`populateJournal` writes to `self.journalList`; `populateBuildings` writes to
`self.buildingsList`. Replace the dispatcher:

```lua
-- Fills every tab. The tab panel decides which one is visible, so all four are
-- kept current rather than rebuilt on switch.
function TwoManCrewJournalWindow:populate()
	self:populateCampaign()
	self:populateBuildings()
	self:populateJournal()
end
```

- [x] **Step 5: Update `layout()`**

Two buttons now, and the tab panel takes the space the list used to have:

```lua
	local buttons = { self.refreshButton, self.claimButton }
```

After the list geometry is computed, size the panel and its views:

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

- [x] **Step 6: Run the parser and read the diff**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && npm run check
```

Expected: `29/29 parsed`. Then confirm no reference to the removed machinery
survives:

```bash
grep -n "viewButton\|activeView" "Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
```

Expected: no output.

- [x] **Step 7: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: replace the cycling view button with four named tabs"
```

---

### Task 8: Skin the window chrome - DONE

**Files:**

- Modify: `.../client/TwoManCrew/TwoManCrew_JournalWindow.lua`

- [x] **Step 1: Set the base colours**

At the top of `createChildren`, right after `ISCollapsableWindow.createChildren(self)`:

```lua
	-- The base class paints its title bar and body from these two tables
	-- (ISCollapsableWindow.lua:152-166 and :179-197), so restyling the chrome is
	-- an assignment rather than an override fight.
	self.backgroundColor = { r = SKIN.ground.r, g = SKIN.ground.g, b = SKIN.ground.b, a = 0.95 }
	self.borderColor = { r = SKIN.ruleLit.r, g = SKIN.ruleLit.g, b = SKIN.ruleLit.b, a = 1 }
```

- [x] **Step 2: Add the amber rule under the title**

In `prerender`, after the header text is drawn:

```lua
	-- One amber rule under the title, the single bright line in the window. It
	-- is what makes the panel read as a posted work order rather than a system
	-- dialog. drawRect takes alpha BEFORE rgb (ISUIElement.lua:1191).
	local ruleY = self:titleBarHeight()
	self:drawRect(0, ruleY, self.width, 1, 1, SKIN.active.r, SKIN.active.g, SKIN.active.b)
	self:drawRect(0, ruleY + 1, self.width, 1, 1, SKIN.rule.r, SKIN.rule.g, SKIN.rule.b)
```

- [x] **Step 3: Recolour the header text**

In `prerender`, replace the literal colour triplets in the three `drawText` calls:
the claim line takes `SKIN.active`, the refusal line `SKIN.blocked`, the no-claim
hint `SKIN.dim`. Alpha stays LAST - that is `drawText`'s signature.

- [x] **Step 4: Run the parser**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && npm run check
```

Expected: `29/29 parsed`.

- [x] **Step 5: Commit**

```bash
git add "two-man-crew/Contents/mods/TwoManCrew/42/media/lua/client/TwoManCrew/TwoManCrew_JournalWindow.lua"
git commit -m "feat: skin the journal window as a work order"
```

---

### Task 9: Version bump and close out - DONE

**Controller only.**

**Files:**

- Modify: `two-man-crew/Contents/mods/TwoManCrew/mod.info`
- Modify: `two-man-crew/Contents/mods/TwoManCrew/42/mod.info`

- [x] **Step 1: Bump both copies to 0.4.0**

New behaviour, so minor rather than patch. Both files must match; they have
drifted once already.

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew/Contents/mods/TwoManCrew"
sed -i 's/^modversion=0\.3\.1$/modversion=0.4.0/' mod.info 42/mod.info
grep -H modversion mod.info 42/mod.info
```

Expected: both print `modversion=0.4.0`.

- [x] **Step 2: Run every gate**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew" && npm run check
cd "d:/Dropbox/Apps/Project Zomboid" && npx prettier --check "*.md" "docs/**/*.md" ".claude/memory/*.md"
```

- [x] **Step 3: Run the language server, from the repo root**

```bash
cd "d:/Dropbox/Apps/Project Zomboid" && lua-language-server --check=. --checklevel=Warning
```

Expected: no new diagnostics. Never "fix" the pre-existing atan2 or
duplicate-set-field warnings.

- [x] **Step 4: Commit**

```bash
git add two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
git commit -m "chore: bump modversion to 0.4.0 for the campaign task cards"
```

- [x] **Step 5: Update this plan's status banner**

Record what actually ran. Name the gates; do not imply the mod works.

- [x] **Step 6: Report honestly**

The closing report says `Unverified: not loaded in Project Zomboid`. Do not claim
the panel works, looks right, or that the click targets land. None of that has
been observed, and there is no longer any local suite that could observe it.

Ask the player for one run with the Journal open on the Orders tab, and for a
screenshot. If a fault appears: instrumentation first, fix second.
`npm run diagnose` reads the newest log and prints the command chain in order.

---

## Deployment note

Do **not** run `node deploy.mjs` without asking. The install is deliberately
pinned at `0.1.0` to match the other player in a co-op save, and deploying
replaces it. Deploying while the game is running replaces the mod folder under a
live session.
