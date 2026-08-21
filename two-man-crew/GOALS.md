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
