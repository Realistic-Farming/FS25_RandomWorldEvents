--!load: integrations/RWESettingsHubBridge.lua
-- MAINT-254-hub_save_server_guard_spec_test.lua - MAINTENANCE row 254: RWE's SettingsHub bridge saves on
-- the server only.
--
-- THE DEFECT THIS PINS (development 96f7ac3): the bridge's applyChange
-- (integrations/RWESettingsHubBridge.lua:81-103) ended in mgr:saveSettings() (:102) on every peer.
-- RWE's writer (RandomWorldEvents.lua:313-396) also writes the event-state snapshot and the settlement
-- lines, and a joined client's savegameDirectory is set (<profile>/savegame0: JoinGameScreen.lua:630,
-- FSCareerMissionInfo.lua:13, :451-452), so a client reached through its own SettingsHub would write
-- its own unsynced copy of them. The bridge registers on every peer (RandomWorldEvents.lua:1756).
-- Since SettingsHub #24 the admin keys reach a selfPersisted module's onChange on the server only, but
-- the player-local keys (admin = false) still reach it on a client, through the hub's _applyLocal
-- (SettingsHub.lua:223-228), so the client save was live for them.
--
-- THE FIX: applyChange applies the value on every peer and saves behind g_server ~= nil, RWE's own
-- server predicate (utils/RWESettlement.lua:44).
--
-- THE ENTRY-POINT BAR IS GROUP E. The real bridge registers itself the way RandomWorldEvents.lua:1756
-- calls it, with SettingsHub reachable only as the mission's handle (its registerModule records the
-- spec); the change enters where production enters it, the hub calling the registered onChange. The
-- RWE manager is the world: its settings sections and a saveSettings that counts writes.
--
--   E1  a client (g_server nil) registered with its own hub applies a player-local change (showHUD,
--       the key kind the hub still routes to a client's onChange) and writes nothing
--   E2  the server applies it and writes once
--   E3  the registration is selfPersisted (the hub mirrors, the mod owns persistence)

local function group(name, fn)
  local ok, err = pcall(fn)
  if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

--- One peer: its RWE manager (the world), its mission with SettingsHub on it, the bridge registered.
local function peer(isServer)
  local mgr = {
    events  = { enabled = true, frequency = 5, intensity = 2, cooldown = 60, arcadePhysics = false,
                showNotifications = true, showWarnings = true, showHUD = true, economicEvents = true,
                vehicleEvents = true, fieldEvents = true, wildlifeEvents = true, specialEvents = true },
    physics = { enabled = true, wheelGripMultiplier = 1.0, suspensionStiffness = 1.0, showPhysicsInfo = false },
    debug   = { enabled = false, showDebugInfo = false },
    hudScale = 1.0, experimentalSystems = false,
    saves = 0,
  }
  function mgr:saveSettings() self.saves = self.saves + 1 end
  local spec = {}
  g_currentMission = {
    missionInfo = { savegameDirectory = isServer and "savegame1" or "profile/savegame0" },
    getIsServer = function() return isServer end,
    settingsHub = { registerModule = function(_self, name, s) spec[name] = s; return true end },
  }
  g_server = isServer and {} or nil
  g_RandomWorldEvents = mgr
  RWESettingsHubBridge.register(mgr)
  return mgr, spec.RandomWorldEvents
end

group("E1", function()
  local mgr, mod = peer(false)
  T.ok("E1 [reached] the client's bridge registered with its own SettingsHub", mod ~= nil and type(mod.onChange) == "function")
  mod.onChange("showHUD", false, 3)
  T.eq("E1 the client applies the player-local value through the registered callback", mgr.events.showHUD, false)
  T.eq("E1 and writes nothing", mgr.saves, 0)
end)

group("E2", function()
  local mgr, mod = peer(true)
  mod.onChange("frequency", 8, 3)
  T.eq("E2 the server applies the value", mgr.events.frequency, 8)
  T.eq("E2 and writes once", mgr.saves, 1)
end)

group("E3", function()
  local _, mod = peer(true)
  T.eq("E3 the registration is selfPersisted", mod and mod.selfPersisted, true)
end)

g_server, g_RandomWorldEvents = nil, nil
