# Lua event reference — verified subset

Fetched 2026-08-13 from `https://demiurgequantified.github.io/ProjectZomboidLuaDocs/md_Events.html`
(the actual current LuaDocs site — see `luadocs-wiki-note.md` for why the
PZwiki `LuaDocs` page itself is not the source of truth).

This is not a full event dump — only what was looked up and confirmed for this
workspace's scaffold. **Add to this file as more events get verified; don't
add an event here from memory.**

## Game start / initialization sequence

Fires in this order:

1. **`OnGameBoot`** — triggered after the game finishes starting up. Fires
   before character loading on clients. No parameters.
2. **`OnInitWorld`** — triggered after the world has initialised. No parameters.
3. **`OnGameStart`** — triggered upon finishing loading and entering the game.
   Client-side, marks when the player enters gameplay. No parameters.
4. **`OnCreatePlayer`** — fires every time a local player loads into the
   world. Parameters: `(int playerIndex, IsoPlayer player)`.
5. **`OnNewGame`** — fires when a local player character is created for the
   first time (new character, not a load). Parameters: player character and
   spawn location.

`example-mod/` uses `OnGameStart` since it needs no parameters and is the
simplest "the game is playable now" hook, matching the request for an
OnGameStart-style example.

## Registration pattern (from pz-modding-guide/lua-scripting.md, corroborated
## by the wiki's own example on Lua_(API))

```lua
local function myHandler(...)
    -- logic
end

Events.EventName.Add(myHandler)
Events.EventName.Remove(myHandler)  -- when no longer needed
```
