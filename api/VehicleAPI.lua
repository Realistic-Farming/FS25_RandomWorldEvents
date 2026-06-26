-- =========================================================
-- RWEVehicleAPI v2.0.0
-- Public subsystem API for the Vehicle event category.
-- Third-party mods consume this table to register custom
-- vehicle events and apply vehicle modifiers at runtime.
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
-- =========================================================
--
-- USAGE (third-party mod):
--   if RWEVehicleAPI and RWEVehicleAPI.registerEvent then
--     RWEVehicleAPI:registerEvent({
--       name        = "myMod_turbo_boost",
--       minIntensity = 1,
--       ambientMsgs = {
--         "Your tractor engine is singing at full throttle!",
--         "Fields are flying by — everything feels faster today.",
--       },
--       func = function(intensity)
--         local v = g_currentMission and g_currentMission.controlledVehicle
--         if v then
--           RWEVehicleAPI:applyVehicleModifier(v, { speedMultiplier = 1.0 + 0.1 * intensity })
--         end
--         return string.format("Turbo engaged! +%.0f%% speed", intensity * 10)
--       end,
--       onMid = function(intensity)
--         return "The boost is at its peak — make the most of it!"
--       end,
--     })
--   end
-- =========================================================

---@class RWEVehicleAPI
RWEVehicleAPI = {
    _VERSION          = "2.0.0",
    _CATEGORY         = "vehicle",
    _defaultDuration  = { min = 10, max = 30 },

    _startCallbacks   = {},
    _endCallbacks     = {},
    _pendingTicks     = {},
    _tickCounter      = 0,

    -- Tracks vehicles modified via applyVehicleModifier for cleanup on event end
    _modifiedVehicles = {},
}

-- Inject shared API surface.
RWEBaseAPI.mixin(RWEVehicleAPI)

-- Category-specific cleanup: restore all modified vehicles on event end.
function RWEVehicleAPI._onEndCleanup(api)
    api:_restoreModifiedVehicles()
end

-- =====================
-- CATEGORY-SPECIFIC: VEHICLE MODIFIERS
-- =====================

--- Apply a set of runtime modifiers to a vehicle and track it for auto-restore.
--- Routes through RWEVehiclePhysics so only real, engine-read fields are
--- touched (vehicle.speedLimit, motor.maxForwardSpeed, accelerationLimit,
--- steering input). Supported modifier keys:
---   speedMultiplier  (number) — scales the km/h cap and physical top speed
---   accelMultiplier  (number) — scales acceleration (engine feel)
---   steerPull        (number) — -1..1 continuous steering bias
---@param vehicle table   FS25 vehicle object
---@param modifiers table  Key-value modifier table
function RWEVehicleAPI:applyVehicleModifier(vehicle, modifiers)
    if not vehicle or type(modifiers) ~= "table" then return end
    if not RWEVehiclePhysics then
        Logging.warning("[RWEVehicleAPI] RWEVehiclePhysics controller unavailable; modifier ignored")
        return
    end

    local mods = {}
    if modifiers.speedMultiplier then mods.speedScale = modifiers.speedMultiplier end
    if modifiers.accelMultiplier then mods.accelScale = modifiers.accelMultiplier end
    if modifiers.steerPull       then mods.steerPull  = modifiers.steerPull       end

    RWEVehiclePhysics.applyEventMods(vehicle, mods)
    table.insert(self._modifiedVehicles, { vehicle = vehicle })

    Logging.info(string.format("[RWEVehicleAPI] Modifier applied to vehicle (speedMult=%s)",
        tostring(modifiers.speedMultiplier)))
end

--- Restore all vehicles modified during this event.
--- Called automatically on event end via _onEndCleanup.
function RWEVehicleAPI:_restoreModifiedVehicles()
    if RWEVehiclePhysics then
        for _, record in ipairs(self._modifiedVehicles) do
            if record.vehicle then
                RWEVehiclePhysics.clearEventMods(record.vehicle)
            end
        end
    end
    self._modifiedVehicles = {}
    Logging.info("[RWEVehicleAPI] All vehicle modifiers restored")
end

-- =====================
-- SELF-REGISTRATION WITH CORE
-- =====================

local function initVehicleAPI()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerSubsystem then return false end
    g_RandomWorldEvents:registerSubsystem("vehicle", RWEVehicleAPI)
    RWEVehicleAPI:_flushPendingTicks()
    Logging.info("[RWEVehicleAPI] v" .. RWEVehicleAPI._VERSION .. " registered with RWE core")
    return true
end

if not initVehicleAPI() then
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, initVehicleAPI)
    Logging.info("[RWEVehicleAPI] Queued for deferred registration")
end

Logging.info("[RWEVehicleAPI] Module loaded (v" .. RWEVehicleAPI._VERSION .. ")")
