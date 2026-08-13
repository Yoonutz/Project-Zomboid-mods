-- Verified against docs/lua-events-reference.md: OnGameStart fires once,
-- client-side, no parameters, "upon finishing loading and entering the game."
-- Source: https://demiurgequantified.github.io/ProjectZomboidLuaDocs/md_Events.html

local function onGameStart()
    print("[ExampleMod] OnGameStart fired -- player has entered the game.")
end

Events.OnGameStart.Add(onGameStart)
