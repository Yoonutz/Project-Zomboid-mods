// Behavioural test for the crew widget and the journal window.
//
// Runs the mod's real Lua under a Lua 5.3 VM (fengari) against a stub of the
// bits of Project Zomboid the UI touches. It exists because the earlier
// "verification" on this UI was a parser and a language server, and neither
// executes a single line - both passed while the widget was unclickable, the
// drag snapped out, and Claim never answered.
//
// The stub models the one thing those checks could not: PZ keeps the mouse
// hitbox on the JAVA object, and the Java object only learns a new size
// through setWidth/setHeight. Writing self.width does not reach it. So the
// harness tracks javaW/javaH separately from the Lua fields, and hit-tests
// against the Java pair exactly as the engine does.
//
// Run: node test-ui.mjs

import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const LUA_DIR = join(ROOT, "Contents/mods/TwoManCrew/42/media/lua");

const results = [];
function check(name, pass, detail) {
  results.push({ name, pass, detail });
}

// ---------------------------------------------------------------------------
// The PZ stub, written in Lua so the mod's own require/derive chain works.
// ---------------------------------------------------------------------------
const STUB = String.raw`
-- Kahlua (Lua 5.1) compatibility shim.
--
-- fengari is a Lua 5.3 VM, but Project Zomboid embeds Kahlua, which is 5.1.
-- Left alone the harness would happily run code the game rejects. These two
-- lines close the gap that actually bites: 5.1 has a global unpack and no
-- table.unpack, and its integer division is math.floor, not //.
--
-- The mod is also scanned for 5.2+ syntax before any of this runs - see
-- assertLua51Dialect in the JS below. Kahlua provides pcall but NOT xpcall
-- (verified by reading se/krka/kahlua/stdlib/BaseLib.class in
-- projectzomboid.jar), so xpcall is removed here to make its absence real.
unpack = unpack or table.unpack
table.unpack = nil
xpcall = nil

-- Mouse/UI state the harness drives from the test script below.
MOUSE = { x = 0, y = 0, down = false }

-- Every element registered with the "UIManager". Each carries javaW/javaH,
-- the size the engine would hit-test against.
UI_ELEMENTS = {}

local function newElement(o)
  o.children = o.children or {}
  return o
end

ISUIElement = {}
ISUIElement.__index = ISUIElement

function ISUIElement:derive(name)
  local c = setmetatable({}, { __index = self })
  c.__index = c
  c.Type = name
  return c
end

function ISUIElement:new(x, y, w, h)
  local o = newElement({
    x = x or 0, y = y or 0, width = w or 0, height = h or 0,
    -- The Java-side rectangle. Deliberately a SEPARATE pair: this is the
    -- whole point of the harness.
    javaX = x or 0, javaY = y or 0, javaW = w or 0, javaH = h or 0,
    javaObject = nil,
    wantMouseEvents = true,
  })
  return setmetatable(o, self)
end

function ISUIElement:initialise() end
function ISUIElement:instantiate() self.javaObject = true end

function ISUIElement:addToUIManager()
  -- Creating the Java object stamps the CURRENT size. Later raw assignments
  -- to self.width never update it; only setWidth/setHeight do.
  self.javaObject = true
  self.javaW = self.width
  self.javaH = self.height
  self.javaX = self.x
  self.javaY = self.y
  table.insert(UI_ELEMENTS, self)
end

function ISUIElement:removeFromUIManager()
  for i, e in ipairs(UI_ELEMENTS) do
    if e == self then table.remove(UI_ELEMENTS, i) break end
  end
  self.javaObject = nil
end

function ISUIElement:setVisible(v) self.visible = v end
function ISUIElement:getIsVisible() return self.visible end

function ISUIElement:setX(v)
  self.x = v
  if self.javaObject then self.javaX = v end
end
function ISUIElement:setY(v)
  self.y = v
  if self.javaObject then self.javaY = v end
end
function ISUIElement:getX() return self.x end
function ISUIElement:getY() return self.y end
function ISUIElement:getWidth() return self.width end
function ISUIElement:getHeight() return self.height end

-- Mirrors ISUIElement.lua:1136-1160 - these are the ONLY paths to Java.
function ISUIElement:setWidth(w)
  self.width = w
  if self.javaObject then self.javaW = w end
end
function ISUIElement:setHeight(h)
  self.height = h
  if self.javaObject then self.javaH = h end
end

function ISUIElement:getAbsoluteX() return self.x end
function ISUIElement:getAbsoluteY() return self.y end
function ISUIElement:addChild(c) table.insert(self.children, c) c.parent = self end
function ISUIElement:bringToTop() end

-- Hit-test the way the engine does: against the JAVA rectangle.
function ISUIElement:isMouseOver()
  if not self.javaObject then return false end
  return MOUSE.x >= self.javaX and MOUSE.x < self.javaX + self.javaW
     and MOUSE.y >= self.javaY and MOUSE.y < self.javaY + self.javaH
end

-- Drawing is recorded, not rendered, so tests can assert what was painted.
DRAWN = {}
function ISUIElement:drawRect(x, y, w, h, a, r, g, b)
  table.insert(DRAWN, { kind = "rect", x = x, y = y, w = w, h = h, a = a })
end
function ISUIElement:drawText(t, x, y)
  table.insert(DRAWN, { kind = "text", text = t, x = x, y = y })
end
function ISUIElement:drawTextureScaled(tex, x, y, w, h)
  table.insert(DRAWN, { kind = "tex", x = x, y = y, w = w, h = h })
end
function ISUIElement:drawTexture(...) end
function ISUIElement:drawTextureScaledAspect(...) end

ISPanel = ISUIElement:derive("ISPanel")
ISCollapsableWindow = ISPanel:derive("ISCollapsableWindow")
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:prerender() end
function ISCollapsableWindow:titleBarHeight() return 17 end
function ISCollapsableWindow:resizeWidgetHeight() return 9 end
function ISCollapsableWindow:onResize() end
function ISCollapsableWindow:close() self:setVisible(false) end

ISButton = ISUIElement:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
  local o = ISUIElement.new(self, x, y, w, h)
  o.title = title; o.target = target; o.onclick = onclick
  return o
end
function ISButton:setImage(i) self.image = i end
function ISButton:setTitle(t) self.title = t end

ISScrollingListBox = ISUIElement:derive("ISScrollingListBox")
function ISScrollingListBox:new(x, y, w, h)
  local o = ISUIElement.new(self, x, y, w, h)
  o.items = {}
  return o
end
function ISScrollingListBox:setFont() end
function ISScrollingListBox:clear() self.items = {} end
function ISScrollingListBox:addItem(t, d) table.insert(self.items, { text = t, data = d }) end

ISContextMenu = { get = function() return {
  addOption = function() return {} end, getNew = function() return {} end,
  addSubMenu = function() end, setOptionChecked = function() end,
} end }
ISToolTip = {}

-- Engine globals.
UIManager = { getMillisSinceLastRender = function() return 16 end }
UIFont = { Small = "small", NewSmall = "newsmall", Medium = "medium" }

local TEXTURES = {}
function REGISTER_TEXTURE(p) TEXTURES[p] = true end
function getTexture(p) if TEXTURES[p] then return { path = p } end return nil end

function getTextManager()
  return { MeasureStringX = function(_, _, s) return #tostring(s) * 6 end,
           getFontHeight = function() return 16 end }
end

function getCore() return {
  getScreenWidth = function() return 1920 end,
  getScreenHeight = function() return 1080 end,
} end

local TIME = 0
function ADVANCE_TIME(ms) TIME = TIME + ms end
function getTimestampMs() return TIME end
function getGameTime() return { getWorldAgeHours = function() return 100 end } end

HALO = {}
HaloTextHelper = {
  addText = function(_, t) table.insert(HALO, { good = true, text = t }) end,
  addBadText = function(_, t) table.insert(HALO, { good = false, text = t }) end,
}

SAID = {}
local PLAYER = {
  getUsername = function() return "Bob" end,
  getX = function() return 100 end, getY = function() return 100 end,
  Say = function(_, t) table.insert(SAID, t) end,
  getModData = function() return MODDATA end,
}
MODDATA = {}
function getPlayer() return PLAYER end
function getSpecificPlayer(i) if i == 0 then return PLAYER end return nil end
function getNumActivePlayers() return 1 end
function getOnlinePlayers() return nil end

SENT = {}
function sendClientCommand(p, m, c, a) table.insert(SENT, { module = m, command = c, args = a }) end

-- sendServerCommand models the REAL engine behaviour that caused the bug:
-- it is a network send, so in singleplayer (isClient and isServer both
-- false) it reaches nobody and OnServerCommand never fires. Recording the
-- attempt without delivering it is exactly what the game does, and is what
-- lets the suite catch code that relies on the reply arriving solo.
REPLIES_ATTEMPTED = {}
function sendServerCommand(player, m, c, a)
  table.insert(REPLIES_ATTEMPTED, { module = m, command = c, args = a })
  if isClient() or isServer() then
    FIRE("OnServerCommand", m, c, a)
  end
  -- Singleplayer: deliberately dropped, like the engine.
end

-- triggerEvent fires a registered event directly, with no network involved.
-- Verified in the shipped source (85 call sites), e.g.
-- client/DebugUIs/DebugMenu/General/ISDebugBlood.lua:74.
function triggerEvent(name, ...)
  if EVENTS[name] then FIRE(name, ...) end
end

EVENTS = {}
local function mkEvent(name)
  EVENTS[name] = { handlers = {} }
  return {
    Add = function(f) table.insert(EVENTS[name].handlers, f) end,
    Remove = function(f)
      for i, h in ipairs(EVENTS[name].handlers) do
        if h == f then table.remove(EVENTS[name].handlers, i) return end
      end
    end,
  }
end
Events = {
  OnGameStart = mkEvent("OnGameStart"),
  OnServerCommand = mkEvent("OnServerCommand"),
  OnTick = mkEvent("OnTick"),
  OnPlayerUpdate = mkEvent("OnPlayerUpdate"),
  EveryOneMinute = mkEvent("EveryOneMinute"),
  EveryTenMinutes = mkEvent("EveryTenMinutes"),
  OnClientCommand = mkEvent("OnClientCommand"),
}
function FIRE(name, ...)
  -- unpack, not table.unpack: PZ runs Lua 5.1 (Kahlua), where table.unpack
  -- does not exist. The harness deliberately uses the 5.1 spelling so stub
  -- code cannot drift into a dialect the game will not run.
  for _, h in ipairs({ unpack(EVENTS[name].handlers) }) do h(...) end
end

function isClient() return false end
function isServer() return false end

-- require() maps to the mod's lua tree, matching PZ's flat module paths.
-- fengari has no io library, so the harness pre-loads every source into
-- SOURCES from JS and require() just runs the matching entry once.
SOURCES = {}
local loaded = {}
function require(name)
  if loaded[name] then return true end
  loaded[name] = true
  local key = name:gsub("%\\", "/"):gsub("%.lua$", "")
  local src = SOURCES[key]
  if not src then return true end
  local chunk, err = load(src, "@" .. key)
  if not chunk then error("parse " .. key .. ": " .. tostring(err)) end
  chunk()
  return true
end
`;

// ---------------------------------------------------------------------------
// VM helpers
// ---------------------------------------------------------------------------
function runLua(L, src, name) {
  const status = lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(name));
  if (status !== lua.LUA_OK) throw new Error(`load ${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(`run ${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
  }
}

// Every mod source, keyed the way the mod's own require() calls name them
// (e.g. "TwoManCrew/TwoManCrew_Config"). PZ flattens client, shared and
// server into one module namespace, so the harness does too.
function collectSources() {
  const out = {};
  for (const side of ["shared", "client", "server"]) {
    const dir = join(LUA_DIR, side, "TwoManCrew");
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir)) {
      if (!f.endsWith(".lua")) continue;
      out["TwoManCrew/" + f.slice(0, -4)] = readFileSync(join(dir, f), "utf8");
    }
  }
  return out;
}

const SOURCES = collectSources();

// PZ embeds Kahlua, a Lua 5.1 VM. fengari is 5.3, so a construct the game
// cannot run would pass here silently. Scan the mod's own sources for the
// 5.2+ features Kahlua lacks before executing anything.
//
// Checked against the shipped game source, which uses table.unpack zero
// times, goto zero times, and pcall zero times while Kahlua's BaseLib does
// implement pcall - so pcall is allowed and xpcall is not.
function assertLua51Dialect() {
  const banned = [
    [/\btable\.unpack\b/, "table.unpack (5.1 has the global unpack)"],
    [/\bxpcall\b/, "xpcall (not in Kahlua's BaseLib)"],
    [/\bgoto\s+\w/, "goto (5.2+)"],
    [/::\w+::/, "goto label (5.2+)"],
    [/<\s*(const|close)\s*>/, "attribute syntax (5.4)"],
  ];

  const problems = [];
  for (const [key, src] of Object.entries(SOURCES)) {
    src.split(/\r?\n/).forEach((line, i) => {
      // Ignore comments - prose about these features is fine.
      if (/^\s*--/.test(line)) return;
      for (const [re, what] of banned) {
        if (re.test(line)) problems.push(key + ":" + (i + 1) + " uses " + what);
      }
    });
  }

  check(
    "mod code stays inside Lua 5.1, which is what the game runs",
    problems.length === 0,
    problems.slice(0, 3).join("; ")
  );
}

assertLua51Dialect();

function makeVM() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  runLua(L, STUB, "stub");

  // Push each source into the stub's SOURCES table, which its require()
  // reads. Done from JS because fengari ships no io library.
  for (const [k, v] of Object.entries(SOURCES)) {
    lua.lua_getglobal(L, to_luastring("SOURCES"));
    lua.lua_pushstring(L, to_luastring(v));
    lua.lua_setfield(L, -2, to_luastring(k));
    lua.lua_pop(L, 1);
  }
  return L;
}

function loadFile(L, rel) {
  const src = readFileSync(join(LUA_DIR, rel), "utf8");
  runLua(L, src, rel);
}

// Evaluate a Lua expression and return it as a JS number/string/boolean.
function evalLua(L, expr) {
  runLua(L, `__R = ${expr}`, "eval");
  lua.lua_getglobal(L, to_luastring("__R"));
  const t = lua.lua_type(L, -1);
  let v;
  if (t === lua.LUA_TBOOLEAN) v = lua.lua_toboolean(L, -1);
  else if (t === lua.LUA_TNUMBER) v = lua.lua_tonumber(L, -1);
  else if (t === lua.LUA_TSTRING) v = to_jsstring(lua.lua_tostring(L, -1));
  else if (t === lua.LUA_TNIL) v = null;
  else v = `<${t}>`;
  lua.lua_pop(L, 1);
  return v;
}

// ---------------------------------------------------------------------------
// Crew widget tests
// ---------------------------------------------------------------------------
function crewPanelVM() {
  const L = makeVM();
  runLua(L, `
    REGISTER_TEXTURE("media/ui/TwoManCrew_Crew.png")
    TwoManCrew = TwoManCrew or {}
    TwoManCrew.getPartner = function() return nil end
    TwoManCrew.Client = { lastReport = nil, requestCrewReport = function() end }
  `, "pre");
  loadFile(L, "shared/TwoManCrew/TwoManCrew_Config.lua");
  loadFile(L, "client/TwoManCrew/TwoManCrew_PanelPrefs.lua");
  loadFile(L, "client/TwoManCrew/TwoManCrew_CrewPanel.lua");
  runLua(L, `FIRE("OnGameStart") PANEL = TwoManCrewPanel.instance`, "start");
  return L;
}

{
  const L = crewPanelVM();
  // Render one frame with the mouse away from the widget (collapsed state).
  runLua(L, `MOUSE.x = 900 MOUSE.y = 900 DRAWN = {} PANEL:prerender()`, "frame");

  const lw = evalLua(L, "PANEL.width");
  const jw = evalLua(L, "PANEL.javaW");
  const lh = evalLua(L, "PANEL.height");
  const jh = evalLua(L, "PANEL.javaH");

  check(
    "collapsed: Java hitbox matches the Lua size",
    lw === jw && lh === jh,
    `lua ${lw}x${lh} vs java ${jw}x${jh}`
  );

  // The size must stay in step with Java when it CHANGES after creation, not
  // merely at startup. This is the case that actually catches the original
  // defect: a journal line arriving grows the widget by one row, and a raw
  // `self.height = ...` grows only the drawing while Java keeps the old
  // rectangle. Without this step the suite passed against the broken code,
  // because setup() happened to create the element at the right size.
  runLua(L, `
    TwoManCrew.Client.lastReport = {
      tally = { felled = 3 },
      journal = { { text = "felled a tree", playerName = "Bob", worldAgeHours = 30 } },
    }
    PANEL.refreshTimer = 0
    MOUSE.x = 900 MOUSE.y = 900
    PANEL:prerender()
  `, "grow");

  const gw = evalLua(L, "PANEL.width");
  const gjw = evalLua(L, "PANEL.javaW");
  const gh = evalLua(L, "PANEL.height");
  const gjh = evalLua(L, "PANEL.javaH");
  check(
    "widget grows: Java hitbox follows the new size",
    gw === gjw && gh === gjh,
    `lua ${gw}x${gh} vs java ${gjw}x${gjh}`
  );

  // And the grown widget must be hoverable across its whole drawn body,
  // including the rows that only exist after it grew.
  runLua(L, `MOUSE.x = PANEL.x + 150 MOUSE.y = PANEL.y + PANEL.height - 3`, "pos");
  check(
    "widget grows: the new area is still clickable",
    evalLua(L, "PANEL:isMouseOver()") === true,
    `bottom-right of ${gw}x${gh}`
  );

  // The reported bug: hover the middle of the drawn widget and see whether
  // the engine agrees the mouse is over it.
  runLua(L, `MOUSE.x = PANEL.x + 90 MOUSE.y = PANEL.y + 8 DRAWN = {} PANEL:prerender()`, "hover");
  const over = evalLua(L, "PANEL:isMouseOver()");
  const expanded = evalLua(L, "PANEL.expanded");
  check(
    "hovering the widget body registers and expands it",
    over === true && expanded === true,
    `isMouseOver=${over} expanded=${expanded}`
  );

  // Collapsed frame must paint no background plate - that was the complaint.
  runLua(L, `MOUSE.x = 900 MOUSE.y = 900 DRAWN = {} PANEL:prerender()`, "frame2");
  const plate = evalLua(L, `(function()
      for _, d in ipairs(DRAWN) do
        if d.kind == "rect" and d.w and d.w > 100 then return true end
      end
      return false
    end)()`);
  check("collapsed: no wide background box is painted", plate === false, `wideRect=${plate}`);

  const badge = evalLua(L, `(function()
      for _, d in ipairs(DRAWN) do if d.kind == "tex" then return true end end
      return false
    end)()`);
  check("collapsed: the crew badge icon is painted", badge === true, `texture drawn=${badge}`);
}

// Drag: press, move far and fast, release outside. This is the exact
// "I keep my mouse down and drag and it snaps out" report.
{
  const L = crewPanelVM();
  runLua(L, `MOUSE.x = 900 MOUSE.y = 900 PANEL:prerender()`, "f");
  runLua(L, `
    START_X = PANEL:getX()
    START_Y = PANEL:getY()
    MOUSE.x = PANEL.x + 5 MOUSE.y = PANEL.y + 5
    PANEL:onMouseDown(5, 5)
  `, "down");

  // Small in-bounds drag, then a large one that outruns the element so the
  // engine switches to the "outside" handlers.
  runLua(L, `PANEL:onMouseMove(10, 10)`, "m1");
  runLua(L, `PANEL:onMouseMoveOutside(200, 150)`, "m2");
  runLua(L, `PANEL:onMouseUpOutside(0, 0)`, "up");

  const moved = evalLua(L, "PANEL:getX() - START_X");
  const movedY = evalLua(L, "PANEL:getY() - START_Y");
  check(
    "drag survives leaving the widget and keeps the full distance",
    moved === 210 && movedY === 160,
    `moved ${moved},${movedY} of expected 210,160`
  );

  const savedX = evalLua(L, "TwoManCrew.Prefs.get(getPlayer()).x");
  check(
    "position released outside the widget is still saved",
    savedX === evalLua(L, "PANEL:getX()"),
    `pref ${savedX} vs panel ${evalLua(L, "PANEL:getX()")}`
  );
}

// "Always show text" must not break clicking - the reported freeze.
{
  const L = crewPanelVM();
  runLua(L, `
    TwoManCrew.Prefs.get(getPlayer()).alwaysExpanded = true
    PANEL:applyPrefs()
    MOUSE.x = 900 MOUSE.y = 900
    PANEL:prerender()
  `, "always");

  const lw = evalLua(L, "PANEL.width");
  const jw = evalLua(L, "PANEL.javaW");
  check(
    "always-expanded: Java hitbox still matches the drawn size",
    lw === jw,
    `lua ${lw} vs java ${jw}`
  );

  runLua(L, `MOUSE.x = PANEL.x + 90 MOUSE.y = PANEL.y + 8`, "pos");
  const clickable = evalLua(L, "PANEL:isMouseOver()");
  check("always-expanded: the widget is still clickable", clickable === true, `isMouseOver=${clickable}`);

  // And it must still open the journal on a clean click.
  runLua(L, `
    OPENED = false
    TwoManCrewJournalWindow = { toggle = function() OPENED = true end }
    PANEL:onMouseDown(90, 8)
    PANEL:onMouseUp(90, 8)
  `, "click");
  check("always-expanded: a click opens the journal", evalLua(L, "OPENED") === true, "");
}

// ---------------------------------------------------------------------------
// Claim round trip: the "spams Surveying the block..." report.
// ---------------------------------------------------------------------------
{
  const L = makeVM();
  loadFile(L, "shared/TwoManCrew/TwoManCrew_Config.lua");
  loadFile(L, "client/TwoManCrew/TwoManCrew_Campaign.lua");

  // DISPATCHED counts requests that actually left requestClaim, by whichever
  // route applies: a network send in multiplayer, a direct handler call solo.
  // Counting sendClientCommand alone would assert the transport rather than
  // the behaviour, and would read "broken" for a singleplayer game that is
  // working perfectly.
  runLua(L, `
    DISPATCHED = 0
    TwoManCrew.LocalHandlers["requestClaim"] = function() DISPATCHED = DISPATCHED + 1 end
    local realSend = sendClientCommand
    sendClientCommand = function(...) DISPATCHED = DISPATCHED + 1 return realSend(...) end
    HALO = {} SENT = {}
    TwoManCrew.Client.requestClaim(getPlayer())
  `, "c1");
  check(
    "claim: one press dispatches exactly one request",
    evalLua(L, "DISPATCHED") === 1,
    `dispatched ${evalLua(L, "DISPATCHED")}`
  );

  // Press three more times with no reply. Only the first may print the
  // optimistic line; the rest must be told to wait.
  runLua(L, `TwoManCrew.Client.requestClaim(getPlayer())
             TwoManCrew.Client.requestClaim(getPlayer())`, "c2");
  const sent = evalLua(L, "DISPATCHED");
  const surveying = evalLua(L, `(function()
      local n = 0
      for _, h in ipairs(HALO) do
        if h.text:find("Surveying") then n = n + 1 end
      end
      return n
    end)()`);
  check(
    "claim: repeat presses do not spam Surveying or re-dispatch",
    sent === 1 && surveying === 1,
    `dispatched=${sent} surveyingLines=${surveying}`
  );

  // No reply ever arrives. After the timeout the player must be told.
  runLua(L, `ADVANCE_TIME(11000) FIRE("OnTick")`, "timeout");
  const badLast = evalLua(L, `HALO[#HALO].text`);
  const pending = evalLua(L, `TwoManCrew.Client.claimPending`);
  check(
    "claim: a silent server produces a failure message, not endless waiting",
    pending === false && String(badLast).includes("No answer"),
    `pending=${pending} last="${badLast}"`
  );

  // And a later successful reply is still handled.
  runLua(L, `
    HALO = {}
    TwoManCrew.Client.requestClaim(getPlayer())
    FIRE("OnServerCommand", TwoManCrew.MODULE, "claimAssigned",
      { ok = true, count = 7, totalUnits = 22, restored = 0 })
  `, "reply");
  check(
    "claim: a real answer clears the pending state",
    evalLua(L, "TwoManCrew.Client.claimPending") === false &&
      evalLua(L, "TwoManCrew.Client.claimSummary.count") === 7,
    ""
  );

  // A refusal must be retained for the journal header, not just flashed.
  runLua(L, `
    TwoManCrew.Client.claimSummary = nil
    TwoManCrew.Client.requestClaim(getPlayer())
    FIRE("OnServerCommand", TwoManCrew.MODULE, "claimAssigned",
      { ok = false, reason = "no buildings in range" })
  `, "refuse");
  check(
    "claim: a refusal is kept on screen, not only flashed",
    String(evalLua(L, "TwoManCrew.Client.lastClaimRefusal")).includes("no buildings"),
    `refusal=${evalLua(L, "TwoManCrew.Client.lastClaimRefusal")}`
  );
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// SINGLEPLAYER round trip. This is the fault the user actually hit: Refresh
// did nothing and Claim only ever said "Surveying the block...".
//
// Root cause, found by instrumenting the live game rather than reading code:
// sendServerCommand is a network send and reaches nobody in singleplayer, so
// the server received every request (14 of them in the log) and not one reply
// was ever delivered. The stub above models that faithfully - solo, a
// sendServerCommand is recorded and dropped.
//
// These tests load the real client AND server files together, exactly as
// singleplayer does, and assert the player ends up with data.
// ---------------------------------------------------------------------------
{
  const L = makeVM();
  runLua(L, `
    ModData = {
      getOrCreate = function(k)
        MODDATA_STORE = MODDATA_STORE or {}
        MODDATA_STORE[k] = MODDATA_STORE[k] or {}
        return MODDATA_STORE[k]
      end,
    }
    function getWorld() return { getMetaGrid = function() return nil end } end
  `, "server-stubs");

  loadFile(L, "shared/TwoManCrew/TwoManCrew_Config.lua");
  loadFile(L, "server/TwoManCrew/TwoManCrew_CrewState.lua");
  loadFile(L, "server/TwoManCrew/TwoManCrew_CrewReport.lua");
  loadFile(L, "client/TwoManCrew/TwoManCrew_CrewReport.lua");

  check(
    "singleplayer is detected as not networked",
    evalLua(L, "TwoManCrew.isNetworked()") === false,
    `isClient/isServer both false`
  );

  // Press Refresh exactly as the journal window does.
  runLua(L, `
    HALO = {}
    TwoManCrew.Client.lastReport = nil
    TwoManCrew.Client.requestCrewReport(getPlayer())
  `, "refresh");

  check(
    "singleplayer Refresh actually delivers a report to the client",
    evalLua(L, "TwoManCrew.Client.lastReport ~= nil") === true,
    `lastReport is ${evalLua(L, "TwoManCrew.Client.lastReport ~= nil") ? "set" : "STILL NIL"}`
  );

  // Record something, refresh again, and confirm the client sees it. This is
  // the user-visible fact: the button changes what is on screen.
  runLua(L, `
    TwoManCrew.Server.addTally("felled", 2, getPlayer())
    TwoManCrew.Server.addJournal("felled a tree", getPlayer())
    TwoManCrew.Client.lastReport = nil
    TwoManCrew.Client.requestCrewReport(getPlayer())
  `, "refresh2");

  const tally = evalLua(L, `(TwoManCrew.Client.lastReport and
    TwoManCrew.Client.lastReport.tally and
    TwoManCrew.Client.lastReport.tally.felled) or 0`);
  const entries = evalLua(L, `(TwoManCrew.Client.lastReport and
    TwoManCrew.Client.lastReport.journal and
    #TwoManCrew.Client.lastReport.journal) or 0`);

  check(
    "singleplayer Refresh returns the real tally and journal",
    tally === 2 && entries === 1,
    `felled=${tally} (want 2), journal entries=${entries} (want 1)`
  );
}

// Claim, singleplayer, end to end.
{
  const L = makeVM();
  runLua(L, `
    ModData = {
      getOrCreate = function(k)
        MODDATA_STORE = MODDATA_STORE or {}
        MODDATA_STORE[k] = MODDATA_STORE[k] or {}
        return MODDATA_STORE[k]
      end,
    }
    -- No MetaGrid: the survey finds nothing and must REFUSE, which is still
    -- an answer. Silence is the failure being tested for.
    function getWorld() return { getMetaGrid = function() return nil end } end
  `, "server-stubs");

  loadFile(L, "shared/TwoManCrew/TwoManCrew_Config.lua");
  loadFile(L, "server/TwoManCrew/TwoManCrew_CrewState.lua");
  loadFile(L, "server/TwoManCrew/TwoManCrew_Campaign.lua");
  loadFile(L, "client/TwoManCrew/TwoManCrew_Campaign.lua");

  runLua(L, `
    HALO = {}
    TwoManCrew.Client.requestClaim(getPlayer())
  `, "claim");

  check(
    "singleplayer Claim gets a verdict instead of hanging on Surveying",
    evalLua(L, "TwoManCrew.Client.claimPending") === false,
    `claimPending=${evalLua(L, "TwoManCrew.Client.claimPending")}`
  );

  const last = evalLua(L, `(HALO[#HALO] and HALO[#HALO].text) or ""`);
  check(
    "singleplayer Claim's last message is the answer, not the optimistic line",
    !String(last).includes("Surveying"),
    `last message: "${last}"`
  );
}


// Journal window: button row must sit inside the window, below the list.
// ---------------------------------------------------------------------------
{
  const L = makeVM();
  runLua(L, `
    for _, p in ipairs({ "Refresh", "Claim", "View", "Journal" }) do
      REGISTER_TEXTURE("media/ui/TwoManCrew_" .. p .. ".png")
      REGISTER_TEXTURE("media/ui/TwoManCrew_" .. p .. "_16.png")
    end
    TwoManCrew = TwoManCrew or {}
    TwoManCrew.Client = {
      requestCrewReport = function() end, requestTierProgress = function() end,
      requestClaimDetail = function() end, requestClaim = function() end,
    }
  `, "pre");
  loadFile(L, "shared/TwoManCrew/TwoManCrew_Config.lua");
  loadFile(L, "client/TwoManCrew/TwoManCrew_JournalWindow.lua");

  for (const [w, h] of [[440, 320], [300, 160], [900, 700]]) {
    runLua(L, `
      W = TwoManCrewJournalWindow:new(0, 0, ${w}, ${h})
      W:initialise() W:instantiate() W:addToUIManager()
      W:createChildren()
    `, `win${w}`);

    const fits = evalLua(L, `(function()
        local bs = { W.refreshButton, W.claimButton, W.viewButton }
        for _, b in ipairs(bs) do
          if b:getX() < 0 or b:getX() + b:getWidth() > W.width then return false end
          if b:getY() < 0 or b:getY() + b:getHeight() > W.height then return false end
        end
        return true
      end)()`);
    check(`journal ${w}x${h}: every button sits inside the window`, fits === true, "");

    const clear = evalLua(L, `(W.list:getY() + W.list:getHeight()) <= W.refreshButton:getY()`);
    check(`journal ${w}x${h}: the list never covers the button row`, clear === true, "");

    const belowTitle = evalLua(L, `W.list:getY() >= W:titleBarHeight()`);
    check(`journal ${w}x${h}: content starts below the title bar`, belowTitle === true, "");

    const hasIcons = evalLua(L, `W.refreshButton.image ~= nil and W.claimButton.image ~= nil`);
    check(`journal ${w}x${h}: buttons carry icons, not text labels`, hasIcons === true, "");

    // Size floor. The first icon pass shipped 28x22 buttons holding a 14px
    // icon and came back as "bugged and small" - and the suite passed it,
    // because every assertion was about POSITION and none about whether the
    // result was usable. A button smaller than the text label it replaced is
    // a regression however neatly it is placed.
    //
    // 32px is the floor for a comfortable pointer target; the drawn icon must
    // fill most of that face rather than floating in it.
    const bw = evalLua(L, `W.refreshButton:getWidth()`);
    const bh = evalLua(L, `W.refreshButton:getHeight()`);
    check(
      `journal ${w}x${h}: buttons are big enough to hit`,
      bw >= 32 && bh >= 32,
      `${bw}x${bh}, floor 32x32`
    );

    const iconW = evalLua(L, `W.refreshButton.forcedWidthImage or 0`);
    check(
      `journal ${w}x${h}: the icon fills its button`,
      iconW >= bw * 0.6,
      `icon ${iconW} in ${bw} (needs >= ${Math.round(bw * 0.6)})`
    );
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------
let failed = 0;
for (const r of results) {
  if (!r.pass) failed++;
  const mark = r.pass ? "ok  " : "FAIL";
  console.log(`${mark} ${r.name}${r.detail ? `  [${r.detail}]` : ""}`);
}
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed === 0 ? 0 : 1);
