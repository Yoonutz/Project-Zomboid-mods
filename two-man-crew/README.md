# Two-Man Crew

Co-op bonuses for a Lumberjack and a Carpenter working as a crew in Project
Zomboid **Build 42**. Working together pays; splitting up costs.

Ten features. Everything degrades to nothing when you play alone, so the mod is
harmless in single-player.

## Installing

1. Download this repository (green **Code** button, then **Download ZIP**), or
   `git clone https://github.com/Yoonutz/Project-Zomboid-mods.git`.
2. Copy the folder `two-man-crew/Contents/mods/TwoManCrew` into your Zomboid
   mods folder:

   ```
   C:\Users\<yourname>\Zomboid\mods\
   ```

   You should end up with `C:\Users\<yourname>\Zomboid\mods\TwoManCrew\42\...`.

3. Start Project Zomboid, open **Mods**, enable **Two-Man Crew**.
4. Both players need it installed, and a dedicated server needs it too.

## What it does

| Feature               | Effect                                               |
| --------------------- | ---------------------------------------------------- |
| Felling Bonus         | Trees cut near your partner reward both of you       |
| Master's Mark         | A skilled carpenter's crafts carry a quality mark    |
| Shared Apprenticeship | Work beside someone better and you learn their trade |
| Crew Tally            | A shared count of everything the crew has done       |
| Watch My Back         | You are warned when zombies close on your partner    |
| Two-Man Carry         | Hauling heavy beside your partner builds strength    |
| Site Radius           | Building together on one site rewards both           |
| Shift Change          | Night work pays only when you share the watch        |
| Crew Journal          | A running log of who did what, and when              |
| Distress Call         | **F9** marks your position for your partner          |

## On-screen crew panel

A small panel sits in the top-left corner while you play. No key needed - it
shows, at a glance:

- whether your partner is nearby, or that you are working alone
- a red warning when your partner has zombies on them
- how many crew deeds you have racked up
- the latest line from the crew journal

Project Zomboid does not let mods add a real moodle - that list is fixed in the
game itself - so this is a custom panel instead.

## Controls

- **F9** - send a distress call. Your partner sees your direction and distance.
- **F7** - print the full crew tally and journal, more detail than the panel fits.

## Requirements

- Project Zomboid Build 42 (built and checked against 42.20.3)
- Two players. Single-player is safe but nothing triggers.

## Status

All ten features are written and pass a Lua 5.1 syntax check. **Not yet loaded
in a running game** - if it misbehaves, check `C:\Users\<yourname>\Zomboid\Logs\`
and report what the log says.

## For developers

`SPEC.md` holds the build contract and the verified Build 42 API list.
`GOALS.md` designs a campaign layer that is not yet implemented.

Check every Lua file parses:

```
npm install --no-save luaparse
node check-lua.mjs Contents
```
