---@meta
--- Project Zomboid Build 42 API stubs for the Lua language server.
---
--- These declarations exist ONLY to stop the language server reporting every
--- engine-provided global as `undefined-global`. Nothing here is loaded or run
--- by the game: `---@meta` marks the file as definitions only, and it lives
--- outside any mod's `Contents/` folder so it is never packaged or shipped.
---
--- Scope is deliberately narrow: only the globals this repo's mods actually
--- use, with the shapes those call sites rely on. It is not an attempt at a
--- complete PZ API. Add an entry when a mod starts using a new global, and
--- verify the signature against the installed game source
--- (`<steam>/steamapps/common/ProjectZomboid/media/lua`) before adding it -
--- an invented signature is worse than a missing one, because it turns a
--- harmless warning into a confident wrong answer.
---
--- Types are intentionally loose (mostly `any`). The Java-backed objects PZ
--- hands to Lua have large surfaces, and modelling them precisely here would
--- be a second, drifting source of truth next to the real game source.
--- `any` silences the noise without ever claiming a method exists.

---@class IsoPlayer
---@class IsoGridSquare
---@class IsoObject
---@class IsoAnimal
---@class BuildingDef
---@class RoomDef
---@class Texture

--- Server-side global object system for feeding troughs. Derives
--- SGlobalObjectSystem (server/FeedingTrough/SFeedingTroughSystem.lua:5), so it
--- exposes getLuaObjectCount()/getLuaObjectByIndex(i) from
--- server/Map/SGlobalObjectSystem.lua:40-46. The `.instance` singleton is real
--- and used by vanilla at server/FeedingTrough/BuildingObjects/ISFeedingTrough.lua:8.
--- Declared `any` like every other engine class above: the mod calls it
--- defensively behind a nil check and a pcall, so a typed surface would claim
--- more than this stub can honestly verify.
---@type any
SFeedingTroughSystem = nil

--- Engine globals ---------------------------------------------------------

--- Returns the local player (client only). Nil before a game is loaded.
---@param index? number
---@return any
function getPlayer(index) end

---@param index number
---@return any
function getSpecificPlayer(index) end

--- The Java-backed list of connected players (:size() / :get(i), 0-indexed).
--- Available in ANY multiplayer context, host and client alike - not
--- dedicated-server only. Verified client-side at client/Chat/ISChat.lua:560
--- and client/DebugUIs/ISTriggerThunderUI.lua:13, shared at
--- shared/RadioCom/ISRadioInteractions.lua:263, server-side at
--- server/Foraging/forageServer.lua:463, server/XpSystem/XpUpdate.lua:300,
--- server/ClientCommands.lua:628. Singleplayer has no online list; use
--- getNumActivePlayers() + getSpecificPlayer() there.
---@return any
function getOnlinePlayers() end

--- Number of players active on THIS machine (1, or more with split-screen).
--- Verified at client/Fishing/FishingHandler.lua:6 and
--- server/XpSystem/XpUpdate.lua:301.
---@return number
function getNumActivePlayers() end

---@return any
function getGameTime() end

---@return any
function getWorld() end

---@return any
function getCell() end

---@return any
function getCore() end

--- Loads a texture by path, e.g. "media/ui/Foo.png". Returns nil if missing.
---@param path string
---@return any
function getTexture(path) end

--- Text metrics. `getTextManager():MeasureStringX(font, text)` returns the
--- pixel width a string will occupy in that font, which is what right-aligned
--- and centred UI text is positioned from.
--- Verified: client/Chat/ISChat.lua:422, client/DebugUIs/AnimationClipViewer.lua:63.
---@return any
function getTextManager() end

--- True on a game client, including a listen-server host's client half.
---@return boolean
function isClient() end

--- True on a server: dedicated, or a listen-server host.
---@return boolean
function isServer() end

---@return boolean
function isMultiplayer() end

--- Java instanceof bridge, e.g. instanceof(obj, "IsoDoor").
---@param object any
---@param className string
---@return boolean
function instanceof(object, className) end

--- Random integer in 0..n-1.
---@param n number
---@return number
function ZombRand(n) end

---@param min number
---@param max number
---@return number
function ZombRandFloat(min, max) end

---@param text string
function print(text) end

--- Client -> server command. Handled by an Events.OnClientCommand listener.
---@param player any
---@param module string
---@param command string
---@param args table
function sendClientCommand(player, module, command, args) end

--- Server -> client command. Handled by an Events.OnServerCommand listener.
---@param player any
---@param module string
---@param command string
---@param args table
function sendServerCommand(player, module, command, args) end

--- Engine namespaces ------------------------------------------------------

--- Event registry. Every event exposes .Add(fn) and .Remove(fn).
---@class EventHook
---@field Add fun(callback: function)
---@field Remove fun(callback: function)

---@class Events
---@field OnGameStart EventHook
---@field OnGameBoot EventHook
---@field OnPlayerUpdate EventHook
---@field OnTick EventHook
---@field EveryOneMinute EventHook
---@field EveryTenMinutes EventHook
---@field EveryHours EventHook
---@field EveryDays EventHook
---@field OnClientCommand EventHook
---@field OnServerCommand EventHook
---@field OnKeyStartPressed EventHook
---@field OnKeyPressed EventHook
---@field OnFillWorldObjectContextMenu EventHook
---@field OnCreatePlayer EventHook
---@field OnPlayerDeath EventHook
---@field OnRenderTick EventHook
Events = {}

--- Persistent world data, keyed by name. Survives save/load.
---@class ModData
ModData = {}

---@param key string
---@return table
function ModData.getOrCreate(key) end

---@param key string
---@return table|nil
function ModData.get(key) end

---@param key string
---@param value table
function ModData.add(key, value) end

--- Floating on-screen text above a character.
---@class HaloTextHelper
HaloTextHelper = {}

---@param player any
---@param text string
function HaloTextHelper.addText(player, text) end

---@param player any
---@param text string
function HaloTextHelper.addGoodText(player, text) end

---@param player any
---@param text string
function HaloTextHelper.addBadText(player, text) end

---@param player any
---@param text string
---@param arrow? any
function HaloTextHelper.addTextWithArrow(player, text, arrow) end

--- Skill/perk constants, e.g. Perks.Woodwork.
---@class Perks
---@field Woodwork any
---@field Carpentry any
---@field Axe any
---@field Carving any
---@field Strength any
---@field Fitness any
---@field Maintenance any
---@field Farming any
---@field Cooking any
---@field Tailoring any
---@field Blunt any
---@field Sprinting any
---@field Nimble any
---@field Sneak any
Perks = {}

---@class IsoPlayerStatic
IsoPlayer = {}

--- Java-backed list of connected players: :size() and :get(i), 0-indexed.
---@return any
function IsoPlayer.getPlayers() end

--- Moodle identifiers, e.g. MoodleType.HEAVY_LOAD.
---@class MoodleType
---@field HEAVY_LOAD any
---@field ENDURANCE any
---@field Panic any
---@field Hungry any
---@field Thirst any
---@field Tired any
MoodleType = {}

--- Keyboard scancodes, e.g. Keyboard.KEY_F9.
---@class Keyboard
---@field KEY_F1 number
---@field KEY_F2 number
---@field KEY_F3 number
---@field KEY_F4 number
---@field KEY_F5 number
---@field KEY_F6 number
---@field KEY_F7 number
---@field KEY_F8 number
---@field KEY_F9 number
---@field KEY_F10 number
---@field KEY_F11 number
---@field KEY_F12 number
---@field KEY_ESCAPE number
Keyboard = {}

--- Font handles accepted by the drawText family.
---@class UIFont
---@field Small any
---@field Medium any
---@field Large any
---@field NewSmall any
---@field NewMedium any
---@field NewLarge any
---@field Title any
---@field MainMenu1 any
UIFont = {}

---@class UIManager
UIManager = {}

---@return number
function UIManager.getMillisSinceLastRender() end

--- Shared action helpers (shared/ActionManager.lua).
---@class Actions
Actions = {}

---@param character any
---@param item any
function Actions.addOrDropItem(character, item) end

--- ISUI classes ------------------------------------------------------------
--- Declared as `any` so :derive() chains and the large inherited draw surface
--- (drawText, drawRect, drawTextureScaled, setX/setY/setWidth, addChild, ...)
--- never produce undefined-field noise. The real definitions live in
--- <steam>/ProjectZomboid/media/lua/client/ISUI/.

---@type any
ISUIElement = {}

---@type any
ISPanel = {}

---@type any
ISCollapsableWindow = {}

---@type any
ISButton = {}

---@type any
ISScrollingListBox = {}

---@type any
ISContextMenu = {}

---@type any
ISToolTip = {}

--- Timed actions -----------------------------------------------------------
--- Mods wrap these (save the original, replace the method, call through), so
--- they are `any`: the language server must accept both reading the existing
--- method and assigning a new one.

---@type any
ISBaseTimedAction = {}

---@type any
ISChopTreeAction = {}

---@type any
ISCraftAction = {}

---@type any
ISBuildAction = {}

---@type any
ISTimedActionQueue = {}
