-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- Physics utilities for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================

local PhysicsUtils = {}

PhysicsUtils.TERRAIN_CURVES = {
    asphalt = { grip = 1.1 },
    dirt    = { grip = 0.95 },
    field   = { grip = 0.85 },
    grass   = { grip = 0.9 },
    snow    = { grip = 0.7 },
    default = { grip = 1.0 }
}

PhysicsUtils.DAMPING_MULTIPLIER = 0.1
PhysicsUtils.COM_ADJUSTMENT = 0.15
PhysicsUtils.DEFAULT_GRIP = 1.0

local PhysicsUtils_mt = Class(PhysicsUtils)

function PhysicsUtils:new()
    return setmetatable({}, PhysicsUtils_mt)
end

function PhysicsUtils:log(msg, level)
    if not g_RandomWorldEvents or not g_RandomWorldEvents.physics then
        return
    end
    
    level = level or 1
    local debugLevel = g_RandomWorldEvents.physics.debugMode and 2 or 0
    
    if debugLevel >= level then
        Logging.info("[PhysicsUtils] " .. tostring(msg))
    end
end

function PhysicsUtils:clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function PhysicsUtils:getTerrainGrip(terrainType)
    local curve = self.TERRAIN_CURVES[terrainType] or self.TERRAIN_CURVES.default
    return curve.grip
end

function PhysicsUtils:applyTerrainResponse(vehicle)
    if not vehicle or not vehicle.wheels then 
        return 
    end
    
    local physics = g_RandomWorldEvents and g_RandomWorldEvents.physics
    if not physics or not physics.enabled then 
        return 
    end
    
    for wheelIndex, wheel in pairs(vehicle.wheels) do
        if wheel ~= nil and wheel.contact ~= nil and wheel.physics ~= nil then
            local terrain = wheel.contact.groundTypeName or "default"
            local terrainGrip = self:getTerrainGrip(terrain)
            local baseGrip = physics.wheelGripMultiplier or self.DEFAULT_GRIP
            
            wheel.physics.frictionScale = baseGrip * terrainGrip
            
            if physics.debugMode then
                self:log(string.format("Wheel %d: Terrain=%s, Grip=%.2f", 
                    wheelIndex, terrain, wheel.physics.frictionScale))
            end
        end
    end
end

function PhysicsUtils:applyAdvancedPhysics(vehicle)
    if not vehicle or vehicle.getIsActiveForInput == nil or not vehicle:getIsActiveForInput() then
        return
    end
    
    local physics = g_RandomWorldEvents and g_RandomWorldEvents.physics
    if not physics or not physics.enabled then
        return
    end
    
    -- Apply terrain-based grip
    self:applyTerrainResponse(vehicle)
    
    -- Apply suspension stiffness
    if physics.suspensionStiffness and vehicle.wheels then
        for _, wheel in pairs(vehicle.wheels) do
            if wheel ~= nil and wheel.suspension ~= nil then
                local originalForce = wheel.suspension.originalSpringForce or wheel.suspension.springForce
                wheel.suspension.originalSpringForce = originalForce
                wheel.suspension.springForce = originalForce * physics.suspensionStiffness
            end
        end
    end
    
    -- Show physics info if enabled
    if physics.showPhysicsInfo then
        self:showPhysicsInfo(vehicle)
    end
end

function PhysicsUtils:showPhysicsInfo(vehicle)
    if not vehicle then return end

    local physics = g_RandomWorldEvents and g_RandomWorldEvents.physics
    if not physics then return end

    local vehicleName = vehicle.getName and vehicle:getName() or "Vehicle"
    local speed = vehicle.lastSpeedReal or 0
    local speedKmh = speed * 3.6

    -- This function is only called when physics.showPhysicsInfo is true (see
    -- applyAdvancedPhysics); no additional debugMode guard needed here.
    Logging.info(string.format(
        "[PhysicsUtils] %s (%.1f km/h) — grip: %.2f  suspension: %.2f  COM: %.2f  damping: %.2f",
        vehicleName,
        speedKmh,
        physics.wheelGripMultiplier or 1.0,
        physics.suspensionStiffness or 1.0,
        physics.comStrength or 1.0,
        physics.articulationDamping or 0.5
    ))
end

-- =====================
-- SINGLETON INIT (Bug #7 fix)
-- A sentinel prevents double-instantiation whether the core is already live
-- (immediate path) or not yet ready (deferred path via pendingRegistrations).
-- Both paths set _G.RWE_PhysicsUtils_initialized so the other can never run.
-- =====================
local function _initPhysicsUtils()
    if _G.RWE_PhysicsUtils_initialized then
        Logging.info("[PhysicsUtils] Already initialized — skipping duplicate init")
        return
    end
    _G.RWE_PhysicsUtils_initialized = true
    PhysicsUtils = PhysicsUtils:new()
    Logging.info("[PhysicsUtils] Initialized")
end

if g_RandomWorldEvents then
    _initPhysicsUtils()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then
        RandomWorldEvents.pendingRegistrations = {}
    end
    table.insert(RandomWorldEvents.pendingRegistrations, _initPhysicsUtils)
    Logging.info("[PhysicsUtils] Queued for deferred initialization")
end

Logging.info("[PhysicsUtils] Module loaded successfully")