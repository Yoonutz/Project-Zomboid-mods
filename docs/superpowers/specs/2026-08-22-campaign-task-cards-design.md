# Campaign view: task cards with an expandable checklist

> **STATUS: design approved, NOT IMPLEMENTED.** Branch `master`, 2026-08-22, repo
> version `0.3.1`.
>
> Nothing in this document has been built or executed. No Project Zomboid session
> has loaded any of it.

## The problem

The Campaign view of the Crew Journal renders every fact it has as an
undifferentiated 20px row in one flat `ISScrollingListBox`: tier headlines,
livestock stages, census counts and the two "what to do next" hints all share the
same weight, colour and position.

Four faults follow from that, reported by the player as "I have tasks to do, but I
have no idea what to do":

1. **No hierarchy.** A headline and a diagnostic look identical.
2. **The task is last.** Both `Next:` lines render at the bottom, under the census
   block. The only actionable sentences sit where a reader has stopped looking.
3. **Two tracks, one column.** Buildings and livestock advance independently, so
   interleaving them means neither reads as a sequence.
4. **Counts without meaning.** `Last count: 2 animals (0 young)` is a measurement.
   It never says that 0 young is exactly what blocks L4.

The data needed to fix all four is already on the client. The panel discards most
of it into single summary lines.

## The design

Three changes, in order of how much they carry:

### 1. Tabs replace the cycling View button

`ISTabPanel` with four views: **Orders**, **Buildings**, **Livestock**,
**Journal**. Orders is the default and holds the task cards.

The current single View button cycles Journal to Campaign to Buildings. Its third
state is undiscoverable, and reaching a view means pressing a button until it
appears. Tabs make every view one click and name themselves.

### 2. Each objective becomes a task card

A card is a variable-height list row drawn by a custom `doDrawItem`, carrying:

| Part          | Content                                                              |
| ------------- | -------------------------------------------------------------------- |
| Spine         | 3px left bar, colour = state (active/done/blocked/locked)            |
| Chevron       | `>` collapsed, `v` expanded                                          |
| Task          | The mod's own wording from the `*_REMAINING_TEXT` tables             |
| Count         | `2 / 3`, right-aligned, tabular                                      |
| Ladder or bar | One cell per required unit, or a continuous bar (see the rule below) |
| Context       | One line naming the tier, so the ladder is never anonymous           |

**Ladder rule.** When the target is 12 or fewer, draw one cell per required unit.
Above 12, draw a continuous bar. The counts here are small whole numbers (2 of 3
buildings, 0 of 1 hutch) and a smooth fill implies a resolution the data does not
have; the 30-night holds are the only targets that exceed the threshold. The
number 12 is a fixed constant in the code, not a judgement made at draw time.

### 3. A card expands into its checks

Clicking a card toggles an `expanded` flag and rebuilds the list. An open card's
individual checks are appended as their own short rows, each carrying one of three
marks:

| Mark  | Meaning                                                           |
| ----- | ----------------------------------------------------------------- |
| Tick  | The condition is met.                                             |
| Cross | The condition genuinely failed, with the reason on the same line. |
| `?`   | The ground was not loaded, so nothing could be read.              |

The third mark is load-bearing and must not be collapsed into the second.
Collapsing "unreadable" into "not restored" was the original defect in the
Buildings view: a crew could not tell a broken window from a building nobody had
walked near. Chunk loading makes "unknown" a real, permanent third state, not an
edge case.

More than one card may be open at once. Expansion state is client-side only and
is not persisted across a window close.

### 4. A custom skin replaces the default chrome

Default PZ chrome is neutral grey on grey with a hairline border. This replaces it
with a "work order" treatment: warm near-black ground, an amber rule beneath a
stencilled title, status carried on the card spine. It stays dark because the
panel opens over a night-time game screen.

| Token   | Hex       | Role                       |
| ------- | --------- | -------------------------- |
| ground  | `#14120E` | Window body                |
| panel   | `#1E1B15` | List background, title bar |
| rule    | `#3A3225` | Dividers                   |
| text    | `#DCD5C4` | Primary text               |
| active  | `#C8913C` | Current task, accent rule  |
| done    | `#7FA85C` | Met conditions             |
| blocked | `#B4574A` | Failed conditions          |
| unread  | `#6E8AA0` | Unknown / not surveyed     |

**Drawing constraint.** The engine paints filled rectangles, one-pixel borders,
text and textures. There are no gradients, rounded corners or shadows in its
drawing calls, so the skin is built only from what exists. Any effect outside that
set would silently do nothing.

**The alpha trap.** `drawRect` takes alpha _before_ the rgb triplet;`drawText`
takes it _last_. The two are inconsistent and this repo has been bitten by it
before. Every new draw call must be written against the signature, not from
memory.

## Where every mark comes from

No server change is required. All fields below are already computed and already
sent to the client.

| Display                  | Source field                                       | Where                                |
| ------------------------ | -------------------------------------------------- | ------------------------------------ |
| Building check: windows  | `windowsOk`                                        | `TwoManCrew_Restoration.lua:249`     |
| Building check: doors    | `doorsOk`                                          | `TwoManCrew_Restoration.lua:250`     |
| Building check: corpses  | `noCorpses`                                        | `TwoManCrew_Restoration.lua:251`     |
| Building check: crew     | `crewPresent`                                      | `TwoManCrew_Restoration.lua:293`     |
| The `?` mark             | `roomsSeen` / `roomsTotal`                         | `TwoManCrew_Restoration.lua:252-253` |
| Livestock ticks          | `censusAnimals` / `Babies` / `Hutches` / `Troughs` | `TwoManCrew_Tiers.lua:710+`          |
| Task wording (buildings) | `BUILDING_REMAINING_TEXT`                          | `TwoManCrew_Tiers.lua:619-625`       |
| Task wording (livestock) | `LIVESTOCK_REMAINING_TEXT`                         | `TwoManCrew_Tiers.lua:627-632`       |
| Hold targets 7 / 30      | `TIER5_HOLD_NIGHTS`, `L4_HERD_HOLD_NIGHTS`         | `TwoManCrew_Tiers.lua:151-152`       |

**One gap.** The server sends unit counts and status per building, not names. The
expanded building checklist therefore numbers its rows (`Building 3 - 15 units`)
rather than naming them. Adding names is out of scope here.

## Verified engine APIs

Read this session from `ProjectZomboid/media/lua` at Build 42.20.3. Nothing below
is proposed from memory.

| Needed for           | API                                         | Source                                |
| -------------------- | ------------------------------------------- | ------------------------------------- |
| Variable row height  | `item.height`, honoured per item            | `ISScrollingListBox.lua:147, 305-308` |
| Click hits tall rows | `rowAt(x, y)` walks per-item heights        | `ISScrollingListBox.lua:66`           |
| Click callback       | `setOnMouseDownFunction(target, fn)`        | `ISScrollingListBox.lua:277, 287`     |
| Custom row drawing   | `doDrawItem(y, item, alt)` override         | `ISScrollingListBox.lua:304`          |
| Tabs                 | `addView(name, view)`, `activateView(name)` | `ISTabPanel.lua:484, 438`             |
| Equal tab widths     | `setEqualTabWidth(bool)`                    | `ISTabPanel.lua:535`                  |
| Rect fill            | `drawRect(x,y,w,h,a,r,g,b)`                 | `ISUIElement.lua:1191`                |
| Rect border          | `drawRectBorder(x,y,w,h,a,r,g,b)`           | `ISUIElement.lua:1219`                |
| Text                 | `drawText(s,x,y,r,g,b,a,font)`              | `ISUIElement.lua:1293`                |
| Overridable chrome   | `prerender()` / `render()`                  | `ISCollapsableWindow.lua:152, 179`    |

**Ruled out.** No tree-view widget ships with the game, so the expand/collapse is
built from list rows rather than a tree.

**Vanilla precedent.** Tabs: `ISChat.lua:830`, `ISFluidDebugWindow.lua:55-67`.
Custom rows: `AttachmentEditorUI.lua:691`, `AnimationClipViewer.lua:24`.

## Scope

**In scope**

- `TwoManCrew_JournalWindow.lua`: tabs, task cards, expand/collapse, skin.
- Deriving per-check marks client-side from fields already received.
- Bumping `modversion` in both `mod.info` copies, in the same commit.

**Out of scope**

- Any server file. No new field, no new command, no protocol change.
- Building names in the expanded checklist.
- Persisting expansion state across sessions.
- The Journal tab's own contents, which keep their current rendering.

## How this gets verified, and what stays open

The repo's only gate is `npm run check` (luaparse over every Lua file). The
fengari UI harness was deleted by decision on 2026-08-22, because it tested the
mod against a hand-written fake of the engine.

That gate is not evidence about the game. They cannot catch a wrong method name, a nil
at runtime, a wrong event, or a UI that draws garbage. This workspace cannot load
Project Zomboid.

Therefore: **whether the panel looks right, and whether the click targets land,
stays OPEN until one real game run.** That is reported as unverified rather than
propped up with scaffolding built to manufacture proof. If a fault appears
in-game, the repo rule applies: instrumentation first, fix second.

## Risks

| Risk                                                      | Mitigation                                                                  |
| --------------------------------------------------------- | --------------------------------------------------------------------------- |
| Hand-drawn rows misalign at a font size we cannot preview | Derive every offset from `getTextManager():MeasureStringY`, never constants |
| The alpha argument order is written from memory           | Each call written against the cited signature; checked in review            |
| Rebuilding the list on click loses scroll position        | Capture and restore the scroll offset around the rebuild                    |
| Tabs change the window's minimum usable width             | `layout()` stays the single owner of geometry, as it is today               |
