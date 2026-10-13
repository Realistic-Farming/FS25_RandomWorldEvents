-- prelude.lua - minimal FS25 engine mock + tiny test framework.
-- Loaded first by run-tests.mjs, before any src module and the test file itself.
-- Same shape as the FS25_SoilFertilizer / FS25_TaxMod preludes; only stubs what
-- module load and the functions under test touch. Extend as new tests need more.

-- Lua 5.1 <-> fengari (5.3) shims
unpack = unpack or table.unpack
if getfenv == nil then
  function getfenv(_level) return _G end
end
if setfenv == nil then
  function setfenv(_f, _env) return _f end
end

-- FS25 OO helper
function Class(base)
  local mt = {}
  mt.__index = base or mt
  return mt
end

-- Mod environment
g_currentModDirectory = "./"
g_currentModName = "FS25_RandomWorldEvents"
g_modsDirectory = "./"
function source(_path) end          -- tests declare real files through --!load:
function addModEventListener(_l) end
function addConsoleCommand(_n, _d, _f, _t) end
function removeConsoleCommand(_n) end
function createFolder(_p) end
function getUserProfileAppPath() return "./" end  -- a string: loaders concatenate it; fileExists stays false
function fileExists(_p) return false end

-- Mission lifecycle hook targets. Utils chains hooks the way the engine does
-- (appended: old then new; prepended: new then old) so a file that hooks the
-- same method twice keeps both.
Mission00 = Mission00 or {}
FSBaseMission = FSBaseMission or {}
FSCareerMissionInfo = FSCareerMissionInfo or {}
Utils = Utils or {}
function Utils.appendedFunction(old, new)
  if old == nil then return new end
  return function(...) old(...); return new(...) end
end
function Utils.prependedFunction(old, new)
  if old == nil then return new end
  return function(...) new(...); return old(...) end
end
function Utils.overwrittenFunction(old, new)
  return function(self, ...) return new(self, old, ...) end
end
function Utils.getNoNil(v, d) if v == nil then return d else return v end end

g_currentMission = nil  -- each test sets its own mission stub
g_localPlayer = nil
MoneyType = { OTHER = 3, AI = 1, WORKER_WAGES = 2 }
FarmManager = { SPECTATOR_FARM_ID = 0, INVALID_FARM_ID = 15 }
Logging = {
  info = function() end, warning = function() end, error = function() end,
  devInfo = function() end, devWarning = function() end,
}
function printCallstack() end
g_i18n = {
  getText = function(_self, key) return key end,
  hasText = function(_self, _key) return false end,
  formatMoney = function(_self, amount) return "$" .. tostring(amount) end,
}
g_messageCenter = { subscribe = function() end, unsubscribe = function() end, publish = function() end }

-- XML stubs (no persistence in tests)
function createXMLFile() return 0 end
function loadXMLFile() return 0 end
function saveXMLFile() end
function delete() end
function setXMLInt() end
function setXMLFloat() end
function setXMLString() end
function setXMLBool() end
function getXMLInt() return nil end
function getXMLFloat() return nil end
function getXMLString() return nil end
function getXMLBool() return nil end
function hasXMLProperty() return false end

-- Tiny test framework: prints ##TEST_PASS / ##TEST_FAIL markers the runner parses.
T = { _pass = 0, _fail = 0 }
local function _pass(name) T._pass = T._pass + 1; print("##TEST_PASS " .. name) end
local function _fail(name, msg) T._fail = T._fail + 1; print("##TEST_FAIL " .. name .. " :: " .. tostring(msg)) end
function T.ok(name, cond, msg) if cond then _pass(name) else _fail(name, msg or ("expected truthy, got " .. tostring(cond))) end end
function T.eq(name, got, want) if got == want then _pass(name) else _fail(name, "got " .. tostring(got) .. " want " .. tostring(want)) end end
function T.near(name, got, want, tol)
  tol = tol or 1e-6
  if type(got) == "number" and math.abs(got - want) <= tol then _pass(name)
  else _fail(name, "got " .. tostring(got) .. " want ~" .. tostring(want) .. " (tol " .. tol .. ")") end
end
function T.summary() print("##TEST_SUMMARY " .. T._pass .. " " .. T._fail) end
