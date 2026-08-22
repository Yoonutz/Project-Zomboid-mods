---
name: pz-journal-campaign-is-task-cards
description: "The Crew Journal's Campaign view is a tabbed task-card panel built from data the client already had - no server change was needed, and the three-mark rule (done/failed/unreadable) is load-bearing in the UI"
metadata:
  node_type: memory
  type: project
---

The Crew Journal was redesigned on 2026-08-22 (`0.4.0`, branch
`feature/campaign-task-cards`) because the player said "I have tasks to do, but I have no idea
what to do". The old Campaign view printed every fact it had as an identical 20px row, with the
two actionable `Next:` hints rendering **last**, underneath the diagnostics.

The fix needed **no server change at all**. Every field was already being sent and then
discarded into a summary line:

| The panel shows     | Field already on the client                           |
| ------------------- | ----------------------------------------------------- |
| Per-building checks | `windowsOk`, `doorsOk`, `noCorpses`, `crewPresent`    |
| The unreadable mark | `roomsSeen` / `roomsTotal`                            |
| Livestock checks    | `censusAnimals` / `Babies` / `Hutches` / `Troughs`    |
| The task wording    | `BUILDING_REMAINING_TEXT`, `LIVESTOCK_REMAINING_TEXT` |

**Why this matters beyond this one panel:** the instinct when a UI cannot explain itself is to
add a server field. Check what the client already receives first - here the answer was
everything, and the panel was the only thing at fault.

Shape of the code in `TwoManCrew_JournalWindow.lua`:

- `buildCards(progress, detail)` is **pure** - no `getCell`, no `getPlayer`, no drawing. Keep it
  that way. It is the only part of this panel that could ever be checked without launching the
  game, now that there is no harness ([[pz-verification-is-ingame-only]]).
- `cardHeight(card)` is the **single owner of card geometry**. `drawCard` calls it rather than
  recomputing. If the two ever disagree, clicks land on the wrong card, because `rowAt` walks
  per-item heights (`ISScrollingListBox.lua:66`).
- Variable-height rows work by stamping `item.height` inside `doDrawItem`, exactly as vanilla's
  recipe list does at `ISRecipeScrollingListBox.lua:191`.
- Tabs are a real `ISTabPanel`. There is **no tree-view widget** in the game - checked.

**The three-mark rule is not cosmetic.** A check renders as done, failed, or **unreadable**.
"Unreadable" means the chunk was never loaded, which is a different fact from a failed
condition. Collapsing it into "failed" was the original defect in the Buildings view: a crew
could not tell a broken window from a building nobody had walked near. Any future edit that
turns this into a boolean reintroduces that bug.

**The ladder threshold:** one cell per required unit while the target is 12 or fewer, a
continuous bar above that. The counts here are small integers, and a smooth fill implies a
resolution the data does not have. Only the 7- and 30-night holds exceed the threshold.

Related: [[pz-verification-is-ingame-only]], [[pz-ui-size-must-go-through-setters]],
[[pz-vanilla-source-is-the-api-reference]].
