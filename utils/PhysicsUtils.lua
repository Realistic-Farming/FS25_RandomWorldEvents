-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- PhysicsUtils: debug telemetry only.
--
-- The real vehicle physics (terrain governor + event effects) live in
-- the RWEVehiclePhysics specialization (utils/VehiclePhysics.lua). This
-- module used to scale fake fields (wheel.physics.frictionScale,
-- wheel.suspension.springForce) that the engine never reads - that code
-- has been removed. What remains is an honest, correct readout shown
-- when "Show Physics Info" is enabled in the debug settings.
-- =========================================================
-- Author: TisonK
-- =========================================================

local PhysicsUtils = {}
local PhysicsUtils_mt = Class(PhysicsUtils)

function PhysicsUtils:new()
    return setmetatable({}, PhysicsUtils_mt)
end

-- Read the real surface name under the first contacting wheel, or nil.
function PhysicsUtils:getSurfaceName(vehicle)
    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if type(wheels) ~= "table" then return nil end
    for i = 1, #wheels do
        local wheel = wheels[i]
        if wheel ~= nil and wheel.physics ~= nil and wheel.physics.hasGroundContact
            and wheel.physics.getSurfaceSoundAttributes ~= nil then
            local ok, name = pcall(function() return wheel.physics:getSurfaceSoundAttributes() end)
            if ok and name ~= nil then
                return name
            end
        end
    end
    return nil
end

-- Honest per-vehicle readout. Speed is taken from getLastSpeed() (already
-- km/h) rather than the old lastSpeedReal * 3.6 that was 1000x too small.
function PhysicsUtils:showPhysicsInfo(vehicle)
    if vehicle == nil then return end

    local vehicleName = vehicle.getName and vehicle:getName() or "Vehicle"

    local speedKmh = 0
    if vehicle.getLastSpeed ~= nil then
        local ok, s = pcall(function() return vehicle:getLastSpeed() end)
        if ok and type(s) == "number" then speedKmh = s end
    end

    local surface = self:getSurfaceName(vehicle) or "unknown"

    -- Active RWE modifiers, if any.
    local state = vehicle._rwePhysics
    local speedScale = state and state.eventSpeedScale or 1
    local accelScale = state and state.eventAccelScale or 1
    local topScale   = state and state.eventTopScale   or 1
    local steerPull  = state and state.eventSteerPull  or 0

    Logging.info(string.format(
        "[PhysicsUtils] %s | %.1f km/h | surface: %s | speedx%.2f accelx%.2f topx%.2f steer%+.2f",
        vehicleName, speedKmh, surface, speedScale, accelScale, topScale, steerPull))
end

-- =====================
-- SINGLETON INIT
-- A sentinel prevents double-instantiation whether the core is already
-- live (immediate path) or not yet ready (deferred path).
-- =====================
local function _initPhysicsUtils()
    if _G.RWE_PhysicsUtils_initialized then
        return
    end
    _G.RWE_PhysicsUtils_initialized = true
    PhysicsUtils = PhysicsUtils:new()
    Logging.info("[PhysicsUtils] Initialized (debug telemetry)")
end

if g_RandomWorldEvents then
    _initPhysicsUtils()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then
        RandomWorldEvents.pendingRegistrations = {}
    end
    table.insert(RandomWorldEvents.pendingRegistrations, _initPhysicsUtils)
end

Logging.info("[PhysicsUtils] Module loaded")
