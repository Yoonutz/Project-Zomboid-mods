# The Rebuilt Town - goal design

A campaign layer for Two-Man Crew. The crew picks one ruined town block and makes
it whole again: barricades cleared, walls repaired, rooms refurnished, the block
sealed against the dead.

Not a new mod. It reads the counters the crew already keeps and adds its own.

## Why this goal and not another

The two roles supply it end to end. The Lumberjack turns forest into material;
the Carpenter turns material into a restored street. Nothing in the goal asks
either player to leave their trade.

Restoration also differs from building a fresh base in one useful way: the map
chooses the shape of the work. You inherit a footprint and must honour it, which
makes progress legible - a house is either whole or it is not.

## The five tiers

| Tier | Name             | Condition                                            |
| ---- | ---------------- | ---------------------------------------------------- |
| 1    | One House        | one building fully repaired and refurnished          |
| 2    | The Row          | three adjacent buildings restored                    |
| 3    | The Square       | one large public building made whole                 |
| 4    | The Walls        | the block's perimeter sealed - every gap barricaded  |
| 5    | The Rebuilt Town | all buildings on the claimed block restored and held |

Tier 5 additionally requires the crew to hold the block for a stretch of nights,
so the campaign ends on survival rather than on a final hammer blow.

### What "restored" means, concretely

A building counts as restored when all of these hold:

- every broken window on its ground floor is boarded or replaced
- every doorway has a working door
- each of its rooms contains at least one crew-built furniture piece
- no zombie corpse remains inside it

Each condition is observable from the game's own state, so the mod can check
rather than take the player's word for it.

## The livestock track

A restored street with nothing living on it is a film set. This second track
runs alongside the building tiers and finishes the same campaign: the town is
rebuilt when it is inhabited, not merely repaired.

It belongs to the same two trades. Every structure an animal needs is carpentry
work, verified in the game's own scripts:

| Structure      | Requirement  | Source                                                   |
| -------------- | ------------ | -------------------------------------------------------- |
| Log fence      | `Woodwork:1` | `entities/fences_low/entity_logfenceopen.txt`            |
| Chicken hutch  | `Woodwork:3` | `entities/animals/workstations/entity_chickenhutch.txt`  |
| Feeding trough | `Woodwork:3` | `entities/animals/workstations/entity_feedingtrough.txt` |

The Lumberjack supplies the timber, the Carpenter raises the pen. Neither leaves
their trade to keep animals, which is the same test every other tier had to pass.

### The four livestock stages

| Stage | Name        | Condition                                                |
| ----- | ----------- | -------------------------------------------------------- |
| L1    | The Pen     | a fenced enclosure with a working feeding trough         |
| L2    | First Stock | at least one living animal kept inside the claimed block |
| L3    | The Hutch   | a chicken hutch built and occupied                       |
| L4    | The Herd    | animals surviving a full season, second generation born  |

L4 pairs naturally with the block-holding requirement of tier 5: a herd that
lasts a season proves the town works, not just that it stands.

### Where livestock meets the buildings

Tier 5 gains one extra condition: **the claimed block supports living animals**.
A crew that restores every wall but keeps nothing alive has built a monument,
not a town.

### Verified animal APIs

```lua
-- identifying and inspecting an animal
animal:getAnimalType()                   -- client/ISUI/Animal/ISAnimalContextMenu.lua:1134
animal:getBreed()                        -- client/ISUI/Animal/ISAnimalContextMenu.lua:34
animal:isBaby()                          -- client/ISUI/Animal/ISAnimalUI.lua:161
body:isAnimal()                          -- client/DebugUIs/DebugContextMenu.lua:492
instanceof(obj, "IsoAnimal")             -- client/DebugUIs/DebugContextMenu.lua:619
```

`isBaby()` is what makes "second generation born" checkable rather than a claim -
a baby animal inside the claimed block is direct evidence the herd bred.

**Unverified, check before relying on it:** a way to enumerate every animal
within an area, and a direct read of an animal zone's contents. If absent, L2
and L4 fall back to counting animals seen near the crew, which is weaker but
still evidence rather than a self-report.

## How progress is measured

The crew state already counts `treesFelled`, `mastersMarkCrafted`,
`siteRadiusBonus`, `heavyHauls` and `nightShifts`. The campaign adds:

| Key                 | Meaning                                        |
| ------------------- | ---------------------------------------------- |
| `claimedBlockX/Y`   | the block the crew claimed, set once           |
| `buildingsRestored` | count of buildings meeting all four conditions |
| `windowsBoarded`    | barricades raised inside the claimed block     |
| `doorsHung`         | doorways given a working door                  |
| `roomsFurnished`    | rooms holding at least one crew-built piece    |
| `perimeterSealed`   | boolean, set when tier 4 passes                |
| `nightsHeld`        | nights survived inside the claimed block       |
| `pensBuilt`         | fenced enclosures with a working trough        |
| `hutchesBuilt`      | chicken hutches raised and occupied            |
| `animalsKept`       | living animals counted inside the block        |
| `animalsBorn`       | babies seen inside the block - proof of a herd |

## Verified API basis

Every check below was read from the installed Build 42.20.3 source. No invented
functions.

```lua
-- claiming and identifying a building
square:getBuilding()                     -- client/ISUI/ISWorldObjectContextMenu.lua:1694
player:getBuilding()                     -- same line
building:getDef()                        -- verify before use
room:getRoomDef():getName()              -- server/Farming/SFarmingSystem.lua:164

-- barricade state
object:getBarricadeOnSameSquare()        -- server/BuildRecipeCode/buildRecipeCode.lua:30

-- position, for block bounds
player:getX()  player:getY()  player:getZ()
player:DistTo(x, y)                      -- client/Farming/CFarmingSystem.lua:47

-- survival stretch
getGameTime():getNightsSurvived()        -- server/radio/ISWeatherChannel.lua:132
getGameTime():getWorldAgeHours()         -- server/Farming/SFarmingSystem.lua:258

-- crew state, already built
TwoManCrew.Server.addTally(key, n, player)
TwoManCrew.Server.addJournal(text, player)
TwoManCrew.Server.getTally()
```

**Unverified, needs checking before it is relied on:** a direct way to enumerate
every building on a map block, and a corpse-presence check for a room. If either
turns out to be absent, the affected condition falls back to a crew-declared
claim confirmed by proximity, which is weaker but honest.

## Feedback to the players

- A tier completing announces itself to both players and writes a journal entry.
- A `/crew goal` style request reports the current tier and what remains.
- The journal becomes the campaign's record: who restored what, and when.

## Deliberately excluded

- No timer. The crew sets its own pace.
- No failure state. A campaign that can be lost turns a co-op evening sour.
- No reward beyond the tally, the journal, and the existing XP nudges. The goal
  supplies motivation; it should not also supply power.

## Status

Design only. Nothing built. The base mod's ten features are complete and parse
clean, but none of this campaign layer exists yet in code.
