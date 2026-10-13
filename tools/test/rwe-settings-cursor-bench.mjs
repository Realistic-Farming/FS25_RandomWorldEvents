// rwe-settings-cursor-bench.mjs - the Random World Events settings panel keeps the
// mouse cursor and holds the camera while it is open (tester blue_bally, RWE-52 check
// thread: Shift+O opened the panel but the cursor could not reach any toggle).
//
// ENTRY POINT. The real files are loaded into a fengari Lua VM in modDesc order
// (utils/RWEContextInput.lua, RandomWorldEvents.lua, gui/RWESettingsPanel.lua) over a
// minimal engine surface, and the bench then goes where production goes: the real
// Mission00.load and Mission00.loadMission00Finished wrappers RandomWorldEvents.lua
// installs (which create the manager and, in loadGUI, the panel), the manager's real
// onToggleSettingsInput (what Shift+O and the Control Center action call), and the real
// FSBaseMission.update wrapper, frame by frame. Nothing creates the panel or the manager
// by hand. The engine surface records what the mod asks of it: setShowMouseCursor calls,
// camera rotation writes, GUI visibility.
//
// Test-side substitutions, none in the code under test: the engine input binding,
// camera and GUI (recorders), the event HUD (absent), settings persistence (a counter),
// and console-command registration (a no-op).
//
// Usage: node tools/test/rwe-settings-cursor-bench.mjs [repoRoot]
import { readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = process.argv[2] || ".";
let pass = 0;
let failCount = 0;
const ok = (msg) => { pass++; console.log(`  ✓ ${msg}`); };
const fail = (msg) => { failCount++; console.error(`  ✗ ${msg}`); };

const { lua, lauxlib, lualib, to_luastring } = await import("fengari");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(chunk, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(chunk), null, to_luastring(name)) !== 0
      || lua.lua_pcall(L, 0, 0, 0) !== 0) {
    const msg = lua.lua_tostring(L, -1);
    lua.lua_pop(L, 1);
    throw new Error(`${name}: ${msg ? Buffer.from(msg).toString() : "unknown error"}`);
  }
}
function evalBool(expr) {
  run(`__rwe_result = (${expr}) and true or false`, "expr");
  lua.lua_getglobal(L, to_luastring("__rwe_result"));
  const v = lua.lua_toboolean(L, -1);
  lua.lua_pop(L, 1);
  return v;
}
function evalStr(expr) {
  run(`__rwe_result = tostring(${expr})`, "expr");
  lua.lua_getglobal(L, to_luastring("__rwe_result"));
  const v = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return v;
}
const check = (name, expr) => { try { evalBool(expr) ? ok(name) : fail(`${name}  [${expr} -> ${evalStr(expr)}]`); } catch (e) { fail(`${name}: ${e.message}`); } };

// ── the engine surface ─────────────────────────────────────────────────────────
const PRELUDE = `
getfenv = getfenv or function() return _G end
unpack = unpack or table.unpack
function Class(base)
  local mt = { __index = {} }
  local cls = base or {}
  mt.__index = cls
  return mt
end
Utils = {
  prependedFunction = function(old, new) return function(...) new(...); if old then return old(...) end end end,
  appendedFunction  = function(old, new) return function(...) local r = old and old(...); new(...); return r end end,
}
Logging = { info = function() end, warning = function() end, error = function() end, devInfo = function() end }
function addConsoleCommand() end
function removeConsoleCommand() end
g_currentModName = "FS25_RandomWorldEvents"
g_currentModDirectory = "./"
g_modManager = nil
createImageOverlay = nil

-- recorders
REC = { cursor = {}, rotWrites = {}, camRot = { 0.1, 0.2, 0.3 }, saves = 0 }
g_inputBinding = {
  setShowMouseCursor = function(_self, doShow, save) REC.cursor[#REC.cursor + 1] = { show = doShow, save = save } end,
  registerActionEvent = function() return false, nil end,
  beginActionEventsModification = function() end, endActionEventsModification = function() end,
  removeActionEvent = function() end, setActionEventTextVisibility = function() end,
  setActionEventText = function() end, setActionEventActive = function() end,
  contexts = {}, nameActions = {},
}
function getCamera() return 42 end
function getRotation(_cam) return REC.camRot[1], REC.camRot[2], REC.camRot[3] end
function setRotation(cam, x, y, z) REC.rotWrites[#REC.rotWrites + 1] = { cam = cam, x = x, y = y, z = z } end
GUI_VISIBLE = false
g_gui = { getIsGuiVisible = function() return GUI_VISIBLE end, getIsDialogVisible = function() return false end }

RWEEventHUD = { new = function() return nil end }
REC.watch = 0
InputAction = setmetatable({}, { __index = function(_, k) return k end })
PlayerInputComponent = { INPUT_CONTEXT_NAME = "PLAYER", registerActionEvents = function() end }
Vehicle = { INPUT_CONTEXT_NAME = "VEHICLE", registerActionEvents = function() end }
InputBinding = { endActionEventsModification = function() end }

Mission00 = { load = function() end, loadMission00Finished = function() end, saveToXMLFile = function() end }
FSBaseMission = {
  INGAME_NOTIFICATION_OK = 1, INGAME_NOTIFICATION_INFO = 2, INGAME_NOTIFICATION_CRITICAL = 3,
  update = function() end, draw = function() end, mouseEvent = function() end, delete = function() end,
}
MISSION = {
  missionInfo = {}, isServer = true,
  getIsServer = function() return true end, getIsClient = function() return true end,
  addIngameNotification = function() end,
  environment = { currentDay = 1, currentMonotonicDay = 1, dayTime = 0 },
  time = 0,
}
g_currentMission = MISSION
g_server = {}
`;

try {
  run(PRELUDE, "prelude");
  for (const f of ["utils/RWEContextInput.lua", "RandomWorldEvents.lua", "gui/RWESettingsPanel.lua"]) {
    run(readFileSync(join(ROOT, f), "utf8"), f);
  }
  ok("the real files load in modDesc order");
} catch (e) {
  fail("load: " + e.message);
}

// ── production's load path creates the manager and the panel ──────────────────
try {
  run(`Mission00.load(MISSION); Mission00.loadMission00Finished(MISSION)`, "mission load");
  ok("Mission00.load and loadMission00Finished ran through the mod's wrappers");
} catch (e) {
  fail("mission load: " + e.message);
}
check("A1 the load path created the manager", `g_RandomWorldEvents ~= nil and g_RandomWorldEvents.isInitialized == true`);
check("A2 loadGUI created the settings panel", `g_RandomWorldEvents.settingsPanel ~= nil and g_RandomWorldEvents.settingsPanel.isOpen == false`);
try {
  run(`g_RandomWorldEvents.saveSettings = function() REC.saves = REC.saves + 1 end`, "save counter");
} catch (e) { fail("save counter: " + e.message); }

// ── Shift+O opens: cursor shown with the saved position, camera rotation saved ──
// EC-6's bridge, recorded; the real one is loaded later in modDesc order and is not under test here.
try { run(`RWEMarketBridge = { watch = function(rwe) if rwe == g_RandomWorldEvents then REC.watch = REC.watch + 1 end end }`, "bridge"); } catch (e) { fail("bridge: " + e.message); }
try { run(`REC.cursor = {}; g_RandomWorldEvents:onToggleSettingsInput()`, "open"); } catch (e) { fail("open: " + e.message); }
check("B1 Shift+O opens the panel", `g_RandomWorldEvents.settingsPanel.isOpen == true`);
check("B2 open shows the cursor once, keeping its position", `#REC.cursor == 1 and REC.cursor[1].show == true and REC.cursor[1].save == true`);
check("B3 open saves the camera rotation", `g_RandomWorldEvents.settingsPanel.savedCamRotX == 0.1 and g_RandomWorldEvents.settingsPanel.savedCamRotZ == 0.3`);
check("B4 open re-reads the market status on the server (EC-6, kept from the old toggle)", `REC.watch == 1`);

// ── every frame while open: the cursor is re-asserted and the camera held ──────
try {
  run(`REC.cursor = {}; REC.rotWrites = {}
       REC.camRot = { 0.9, 0.9, 0.9 }   -- the mouse would turn the camera
       for i = 1, 3 do FSBaseMission.update(MISSION, 16) end`, "frames");
} catch (e) { fail("frames: " + e.message); }
check("C1 three frames re-assert the cursor three times (the game hides it otherwise)", `#REC.cursor == 3 and REC.cursor[1].show == true and REC.cursor[3].show == true`);
check("C2 three frames hold the camera at the SAVED rotation, not the moved one", `#REC.rotWrites == 3 and REC.rotWrites[3].cam == 42 and REC.rotWrites[3].x == 0.1 and REC.rotWrites[3].y == 0.2 and REC.rotWrites[3].z == 0.3`);
check("C3 the panel stays open across frames", `g_RandomWorldEvents.settingsPanel.isOpen == true`);

// ── Shift+O again closes: cursor hidden, settings saved, frames stop touching both ──
try {
  run(`REC.cursor = {}; REC.rotWrites = {}; WATCH_BEFORE_CLOSE = REC.watch
       g_RandomWorldEvents:onToggleSettingsInput()
       CLOSE_CURSOR = #REC.cursor; WATCH_AFTER_CLOSE = REC.watch
       for i = 1, 3 do FSBaseMission.update(MISSION, 16) end`, "close");
} catch (e) { fail("close: " + e.message); }
check("D1 the second Shift+O closes the panel", `g_RandomWorldEvents.settingsPanel.isOpen == false`);
check("D2 close hides the cursor once", `CLOSE_CURSOR == 1 and REC.cursor[1].show == false`);
check("D3 settings persist on close, as before", `REC.saves == 1`);
check("D4 closed: frames neither touch the cursor nor the camera", `#REC.cursor == 1 and #REC.rotWrites == 0`);
check("D5 the close itself does not re-read the market status (the manager's own per-frame server watch is separate)", `WATCH_AFTER_CLOSE == WATCH_BEFORE_CLOSE`);

// ── a menu or dialog opening on top closes the panel and releases the cursor ──
try {
  run(`g_RandomWorldEvents:onToggleSettingsInput(); REC.cursor = {}; REC.rotWrites = {}
       GUI_VISIBLE = true
       FSBaseMission.update(MISSION, 16)
       GUI_VISIBLE = false`, "gui on top");
} catch (e) { fail("gui on top: " + e.message); }
check("E1 a GUI on top auto-closes the panel", `g_RandomWorldEvents.settingsPanel.isOpen == false`);
check("E2 and the last cursor call hides it", `#REC.cursor >= 1 and REC.cursor[#REC.cursor].show == false`);
check("E3 settings persisted by that close", `REC.saves == 2`);

// ── a pure client opening the panel does not ask the server-side bridge ────────
try {
  run(`local srv = g_server; g_server = nil; REC.watch = 0
       g_RandomWorldEvents.settingsPanel:open(); g_RandomWorldEvents.settingsPanel:close()
       g_server = srv`, "client open");
} catch (e) { fail("client open: " + e.message); }
check("E4 a pure client does not re-read the market status", `REC.watch == 0`);

// ── source witness: the engine-absent camera lock is gone ─────────────────────
const panelSrc = readFileSync(join(ROOT, "gui/RWESettingsPanel.lua"), "utf8");
const code = panelSrc.split(/\r?\n/).filter((l) => !/^\s*--/.test(l)).join("\n");
(code.includes("setForcedNoCameraRotation") ? fail : ok)("F1 no code line calls setForcedNoCameraRotation (absent from the FS25 engine)");

console.log(`\n[bench] passed: ${pass}, failed: ${failCount}`);
if (failCount > 0) {
  console.error("[bench] FAILED");
  process.exit(1);
}
console.log("[bench] PASSED");
