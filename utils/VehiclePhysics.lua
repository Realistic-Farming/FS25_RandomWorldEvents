-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- VehiclePhysics: real basegame vehicle-physics controller.
--
-- This is a vehicle specialization injected into every drivable,
-- motorized, wheeled vehicle type. It exposes a small API that the
-- vehicle EVENTS use to apply real, restorable physics effects, and
-- it runs an always-on terrain "traction governor".
--
-- Only fields the GIANTS engine actually reads are touched here:
--   * vehicle.speedLimit ............ km/h cap (Vehicle:getRawSpeedLimit)
--   * motor.maxForwardSpeed ......... true top speed (restore origin)
--   * motor:setAccelerationLimit() .. engine sluggishness
--   * spec_drivable.lastInputValues.axisSteer .. steering pull
--   * wheel.physics:getSurfaceSoundAttributes() .. real surface (read)
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
--
-- CREDIT: The steering-input technique used here - feeding a value back into
-- Drivable's spec_drivable.lastInputValues.axisSteer so the game steers as if
-- the player were holding the wheel - is adapted from the mod
-- "RealPhysics Steering" by Tubez47. Thank you, Tubez47.
-- (The spec is injected into existing vehicle types via the standard
-- TypeManager.validateTypes pattern, the same as Variable Tire Pressure.)
-- =========================================================

RWEVehiclePhysics = RWEVehiclePhysics or {}

RWEVehiclePhysics.SPEC_NAME = "rweVehiclePhysics"
-- Captured at source time, while g_currentModName is still this mod.
RWEVehiclePhysics.MOD_NAME = RWEVehiclePhysics.MOD_NAME or (g_currentModName or "FS25_RandomWorldEvents")
RWEVehiclePhysics.MOD_DIR  = RWEVehiclePhysics.MOD_DIR or g_currentModDirectory
RWEVehiclePhysics._validateHookInstalled = false
RWEVehiclePhysics._didRegisterGlobally   = false

-- Surface name -> grip factor (1.0 = full grip). Used by the terrain
-- governor to decide how much to ease off on loose ground.
-- Only genuinely slick surfaces ease the vehicle off; normal ground (asphalt,
-- dirt, field, grass...) is full grip so day-to-day driving is never slowed.
RWEVehiclePhysics.SURFACE_GRIP = {
    mud  = 0.80,
    snow = 0.72,
    ice  = 0.60,
}
RWEVehiclePhysics.DEFAULT_GRIP = 1.00

-- =====================
-- SMALL HELPERS
-- =====================
local function clamp(v, lo, hi)
    v = tonumber(v) or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function hasSpecByName(typeDef, name)
    return typeDef ~= nil and typeDef.specializationsByName ~= nil
        and typeDef.specializationsByName[name] ~= nil
end

local function getMotorSafe(vehicle)
    if vehicle == nil or vehicle.getMotor == nil then return nil end
    local ok, motor = pcall(function() return vehicle:getMotor() end)
    if ok then return motor end
    return nil
end

-- Is this the vehicle the local player is currently driving? FS25 exposes
-- that via g_localPlayer:getCurrentVehicle() (returns nil when on foot), with
-- g_currentMission.controlledVehicle as a legacy fallback.
local function isPlayerVehicle(vehicle)
    local p = g_localPlayer
    if p ~= nil and p.getCurrentVehicle ~= nil then
        return p:getCurrentVehicle() == vehicle
    end
    return g_currentMission ~= nil and g_currentMission.controlledVehicle == vehicle
end

-- =====================
-- SPECIALIZATION REGISTRATION HOOKS
-- =====================
function RWEVehiclePhysics.prerequisitesPresent(specializations)
    if SpecializationUtil ~= nil and Motorized ~= nil then
        return SpecializationUtil.hasSpecialization(Motorized, specializations)
    end
    return true
end

function RWEVehiclePhysics.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad",         RWEVehiclePhysics)
    SpecializationUtil.registerEventListener(vehicleType, "onPreUpdate",    RWEVehiclePhysics)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate",       RWEVehiclePhysics)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", RWEVehiclePhysics)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete",       RWEVehiclePhysics)
end

function RWEVehiclePhysics.registerOverwrittenFunctions(vehicleType)
    -- The drivetrain clamps top speed to getSpeedLimit() (WheelsUtil), which
    -- caps a Fendt at ~62 no matter how high we set maxForwardSpeed/maxRpm.
    -- Scaling the speed limit here lets a boost actually exceed stock top end
    -- (and a slowdown lower it) through the game's own pipeline.
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", RWEVehiclePhysics.getSpeedLimit)
end

function RWEVehiclePhysics:getSpeedLimit(superFunc, onlyIfWorking)
    local limit, doCheck = superFunc(self, onlyIfWorking)
    local s = self._rwePhysics
    if s ~= nil and s.eventSpeedScale ~= nil and s.eventSpeedScale ~= 1
        and type(limit) == "number" and limit > 0 and limit < math.huge then
        limit = limit * s.eventSpeedScale
    end
    return limit, doCheck
end

-- =====================
-- PER-VEHICLE STATE
-- State lives on the vehicle (vehicle._rwePhysics) so the event API can
-- reach it even on the rare vehicle that did not receive the spec.
-- =====================
function RWEVehiclePhysics.getState(vehicle)
    if vehicle == nil then return nil end
    local s = vehicle._rwePhysics
    if s == nil then
        s = {
            baseSpeedLimit  = nil,   -- captured lazily (working speed limit, km/h)
            baseAccelLimit  = nil,   -- captured lazily (m/s^2, default 2.0)
            baseMaxRpm      = nil,   -- captured lazily (engine max rpm; raised for turbo)
            eventSpeedScale = 1,     -- scales top speed AND the working cap
            eventAccelScale = 1,     -- acceleration multiplier (engine feel)
            eventSteerPull  = 0,     -- -1..1 steering bias from events
            lastTouched     = false, -- did we write physics last frame?
        }
        vehicle._rwePhysics = s
    end
    return s
end

-- Capture the untouched baseline values once, before we ever scale them.
function RWEVehiclePhysics.captureBase(vehicle, state)
    if state.baseSpeedLimit == nil and type(vehicle.speedLimit) == "number" then
        state.baseSpeedLimit = vehicle.speedLimit
    end
    local motor = getMotorSafe(vehicle)
    if motor ~= nil then
        if state.baseAccelLimit == nil then
            state.baseAccelLimit = motor.accelerationLimit or 2.0
        end
        if state.baseMaxRpm == nil and type(motor.maxRpm) == "number" then
            state.baseMaxRpm = motor.maxRpm
        end
    end
end

function RWEVehiclePhysics:onLoad(savegame)
    -- Establish the state table early; baselines are captured lazily on
    -- first update once the base specs have finished loading their values.
    RWEVehiclePhysics.getState(self)
end

-- =====================
-- PUBLIC EVENT API
-- Called by vehicleEvents.lua / RWEVehicleAPI.
-- =====================

-- Apply a set of event modifiers. Unspecified keys are left unchanged.
--   speedScale : multiplier on top speed + working cap (0.5 slow, 1.3 fast)
--   accelScale : multiplier on acceleration (engine feel; < 1.0 sluggish)
--   steerPull  : -1..1 continuous steering bias (per frame)
function RWEVehiclePhysics.applyEventMods(vehicle, mods)
    if vehicle == nil or type(mods) ~= "table" then return end
    local s = RWEVehiclePhysics.getState(vehicle)
    RWEVehiclePhysics.captureBase(vehicle, s)

    if mods.speedScale ~= nil then s.eventSpeedScale = clamp(mods.speedScale, 0.05, 5.0) end
    if mods.accelScale ~= nil then s.eventAccelScale = clamp(mods.accelScale, 0.05, 5.0) end
    if mods.steerPull  ~= nil then s.eventSteerPull  = clamp(mods.steerPull, -1.0, 1.0) end

    -- Apply immediately so the effect is felt without waiting a frame
    -- (also covers vehicles that, for any reason, lack the spec update).
    RWEVehiclePhysics.enforce(vehicle, s)
end

-- Clear all event modifiers and restore the captured baselines.
function RWEVehiclePhysics.clearEventMods(vehicle)
    local s = vehicle and vehicle._rwePhysics
    if s == nil then return end
    s.eventSpeedScale = 1
    s.eventAccelScale = 1
    s.eventSteerPull  = 0
    RWEVehiclePhysics.restore(vehicle, s)
end

-- Restore a vehicle to its captured baseline (speed/top/accel).
function RWEVehiclePhysics.restore(vehicle, state)
    state = state or (vehicle and vehicle._rwePhysics)
    if vehicle == nil or state == nil then return end
    if state.baseSpeedLimit ~= nil then
        vehicle.speedLimit = state.baseSpeedLimit
    end
    local motor = getMotorSafe(vehicle)
    if motor ~= nil then
        if state.baseAccelLimit ~= nil and motor.setAccelerationLimit ~= nil then
            motor:setAccelerationLimit(state.baseAccelLimit)
        end
        if motor.maxForwardSpeedOrigin ~= nil then
            motor.maxForwardSpeed = motor.maxForwardSpeedOrigin
        end
        if motor.maxBackwardSpeedOrigin ~= nil then
            motor.maxBackwardSpeed = motor.maxBackwardSpeedOrigin
        end
        if state.baseMaxRpm ~= nil then
            motor.maxRpm = state.baseMaxRpm
        end
    end
    state.lastTouched = false
end

-- =====================
-- TERRAIN TRACTION GOVERNOR (always-on, replaces the old fake grip)
-- Returns speedScale, accelScale based on the surface under the wheels.
-- =====================
function RWEVehiclePhysics.getTerrainScales(vehicle)
    local rwe = g_RandomWorldEvents
    local physics = rwe ~= nil and rwe.physics or nil
    if physics == nil or not physics.enabled then
        return 1, 1
    end

    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if type(wheels) ~= "table" or #wheels == 0 then
        return 1, 1
    end

    -- Find the grip of the loosest surface currently under a driven wheel.
    local minGrip = nil
    for i = 1, #wheels do
        local wheel = wheels[i]
        if wheel ~= nil and wheel.physics ~= nil and wheel.physics.hasGroundContact then
            local surfaceName
            if wheel.physics.getSurfaceSoundAttributes ~= nil then
                local ok, name = pcall(function() return wheel.physics:getSurfaceSoundAttributes() end)
                if ok then surfaceName = name end
            end
            local grip = RWEVehiclePhysics.SURFACE_GRIP[surfaceName or ""] or RWEVehiclePhysics.DEFAULT_GRIP
            if minGrip == nil or grip < minGrip then
                minGrip = grip
            end
        end
    end

    if minGrip == nil then
        return 1, 1
    end

    -- The user setting scales how much grip the tyres find. Higher = more
    -- grip = less of a slowdown on loose ground. 1.0 = neutral.
    local userGrip = clamp(physics.wheelGripMultiplier or 1.0, 0.5, 2.0)
    local effGrip = clamp(minGrip * userGrip, 0.3, 1.0)

    -- Translate grip into gentle speed/acceleration easing. At full grip
    -- (1.0) nothing changes; at low grip the vehicle is calmer to control.
    local speedScale = clamp(0.6 + 0.4 * effGrip, 0.5, 1.0)
    local accelScale = clamp(0.4 + 0.6 * effGrip, 0.35, 1.0)
    return speedScale, accelScale
end

-- =====================
-- ENFORCEMENT (per frame)
-- =====================
-- Compose event mods with the terrain governor and write the result to
-- the real fields. Only writes when something actually deviates, so
-- untouched vehicles on good ground are never modified.
function RWEVehiclePhysics.enforce(vehicle, state)
    state = state or (vehicle and vehicle._rwePhysics)
    if vehicle == nil or state == nil then return end
    RWEVehiclePhysics.captureBase(vehicle, state)

    local speedScale = state.eventSpeedScale or 1
    local accelScale = state.eventAccelScale or 1

    -- Terrain governor only affects the vehicle the player is driving.
    local controlled = isPlayerVehicle(vehicle)
    if controlled then
        local tSpeed, tAccel = RWEVehiclePhysics.getTerrainScales(vehicle)
        speedScale = speedScale * tSpeed
        accelScale = accelScale * tAccel
    end

    local deviates = (math.abs(speedScale - 1) > 0.001)
        or (math.abs(accelScale - 1) > 0.001)

    if deviates then
        -- Working speed limit (only bites when a tool forces a limit).
        if state.baseSpeedLimit ~= nil then
            vehicle.speedLimit = state.baseSpeedLimit * speedScale
        end
        local motor = getMotorSafe(vehicle)
        if motor ~= nil then
            if state.baseAccelLimit ~= nil and motor.setAccelerationLimit ~= nil then
                motor:setAccelerationLimit(state.baseAccelLimit * accelScale)
            end
            -- Free-driving top speed (m/s) - the lever you feel on the road.
            -- Lowering this slows the machine; the engine's rpm ceiling still
            -- caps the top end, so to go FASTER than stock we must also let the
            -- engine rev higher (raise maxRpm). Lowering needs no rpm change.
            if motor.maxForwardSpeedOrigin ~= nil then
                motor.maxForwardSpeed = motor.maxForwardSpeedOrigin * speedScale
            end
            if motor.maxBackwardSpeedOrigin ~= nil then
                motor.maxBackwardSpeed = motor.maxBackwardSpeedOrigin * speedScale
            end
            if state.baseMaxRpm ~= nil then
                motor.maxRpm = state.baseMaxRpm * math.max(1, speedScale)
            end
        end
        state.lastTouched = true
    elseif state.lastTouched then
        -- Returned to neutral this frame: restore once.
        RWEVehiclePhysics.restore(vehicle, state)
    end
end

-- =====================
-- PER-FRAME LISTENERS
-- =====================

-- Steering pull is written before the steering physics consume the input
-- (proven approach from RealPhysics Steering by Tubez47).
--
-- It is applied in short, eased bursts rather than a constant lean, so it
-- nudges the wheel now and then (a loose axle catching) instead of fighting
-- the player non-stop - much friendlier on keyboard.
RWEVehiclePhysics.STEER_CYCLE_MS = 5000   -- one tug every 5 s
RWEVehiclePhysics.STEER_ON_MS    = 1200   -- each tug lasts ~1.2 s

function RWEVehiclePhysics:onPreUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local s = self._rwePhysics
    if s == nil or not s.eventSteerPull or s.eventSteerPull == 0 then return end
    if not self.isServer then return end

    local sd = self.spec_drivable
    if sd == nil or sd.lastInputValues == nil then return end

    local t = (g_currentMission and g_currentMission.time) or 0
    local phase = t % RWEVehiclePhysics.STEER_CYCLE_MS
    if phase >= RWEVehiclePhysics.STEER_ON_MS then return end  -- resting between tugs

    -- Smooth 0 -> peak -> 0 envelope across the tug window.
    local envelope = math.sin((phase / RWEVehiclePhysics.STEER_ON_MS) * math.pi)
    local pull = s.eventSteerPull * envelope

    local current = tonumber(sd.lastInputValues.axisSteer) or 0
    sd.lastInputValues.axisSteer = clamp(current + pull, -1, 1)
    sd.lastInputValues.axisSteerIsAnalog = true
end

function RWEVehiclePhysics:onUpdate(dt)
    if not self.isServer then return end
    local s = self._rwePhysics
    if s == nil then return end

    -- Cheap early-out: the governor only matters for the controlled vehicle,
    -- so skip idle parked / AI machines entirely unless an event touched them.
    local hasEventMod = (s.eventSpeedScale ~= 1) or (s.eventAccelScale ~= 1)
        or (s.eventSteerPull ~= 0)
    local physics = g_RandomWorldEvents ~= nil and g_RandomWorldEvents.physics or nil
    local governorRelevant = physics ~= nil and physics.enabled == true
        and isPlayerVehicle(self)

    if not hasEventMod and not governorRelevant and not s.lastTouched then
        return
    end

    RWEVehiclePhysics.enforce(self, s)
end

function RWEVehiclePhysics:onLeaveVehicle()
    -- Leave event mods in place (the event still owns them), but the
    -- terrain governor is tied to being driven, so re-baseline cleanly.
    local s = self._rwePhysics
    if s == nil then return end
    if (s.eventSpeedScale == 1) and (s.eventAccelScale == 1) and s.lastTouched then
        RWEVehiclePhysics.restore(self, s)
    end
end

function RWEVehiclePhysics:onDelete()
    RWEVehiclePhysics.restore(self, self._rwePhysics)
end

-- =====================
-- GUARANTEED-WIN MOTOR ENFORCEMENT (WheelsUtil hook)
-- ColdStart (and any similar mod) also writes motor.maxForwardSpeed every
-- frame in its onUpdate, so spec order decides who wins. To never lose that
-- race, we set the motor levers at the very start of WheelsUtil.updateWheelsPhysics
-- - the exact function that reads them right before controlVehicle. Whatever
-- another spec wrote in onUpdate, ours is the last word before the physics read.
-- =====================
function RWEVehiclePhysics.applyMotorEnforcement(vehicle)
    local s = vehicle and vehicle._rwePhysics
    if s == nil then return end
    local mspec = vehicle.spec_motorized
    local motor = mspec and mspec.motor
    if motor == nil then return end

    local speedScale = s.eventSpeedScale or 1
    local accelScale = s.eventAccelScale or 1

    -- Always-on terrain governor, controlled vehicle only.
    if isPlayerVehicle(vehicle) then
        local tS, tA = RWEVehiclePhysics.getTerrainScales(vehicle)
        speedScale = speedScale * tS
        accelScale = accelScale * tA
    end

    local active = (math.abs(speedScale - 1) > 0.001) or (math.abs(accelScale - 1) > 0.001)
    if not active then
        if s.hookTouched then
            RWEVehiclePhysics.restoreMotor(motor, s)
            s.hookTouched = false
        end
        return
    end

    -- True stock baselines. maxForwardSpeedOrigin / maxBackwardSpeedOrigin are
    -- native fields set once at motor creation and never changed by other mods.
    if s.baseAccelLimit == nil then s.baseAccelLimit = motor.accelerationLimit or 2.0 end
    if s.baseMaxRpm == nil and type(motor.maxRpm) == "number" then s.baseMaxRpm = motor.maxRpm end

    local fwdBase = motor.maxForwardSpeedOrigin or motor.maxForwardSpeed
    local bwdBase = motor.maxBackwardSpeedOrigin or motor.maxBackwardSpeed

    if fwdBase ~= nil then motor.maxForwardSpeed = fwdBase * speedScale end
    if bwdBase ~= nil then motor.maxBackwardSpeed = bwdBase * speedScale end
    if s.baseAccelLimit ~= nil and motor.setAccelerationLimit ~= nil then
        motor:setAccelerationLimit(s.baseAccelLimit * accelScale)
    end

    if speedScale > 1 then
        -- Boost above stock top speed. Raising maxForwardSpeed/rpm alone does
        -- nothing on a CVT because the gearbox tops out at its tallest ratio
        -- (minForwardGearRatio). Give it a taller top gear by lowering that
        -- ratio; a geared box instead needs more rpm headroom in top gear.
        motor.speedLimit = math.huge
        if motor.minForwardGearRatioOrigin ~= nil then
            motor.minForwardGearRatio = motor.minForwardGearRatioOrigin / speedScale
            motor.minGearRatio = motor.minForwardGearRatio  -- override this frame's value
            if s.baseMaxRpm ~= nil then motor.maxRpm = s.baseMaxRpm end
        elseif s.baseMaxRpm ~= nil then
            motor.maxRpm = s.baseMaxRpm * speedScale
        end
    else
        -- Slowdown / governor: stock gearing & rpm; lower maxForwardSpeed does it.
        if s.baseMaxRpm ~= nil then motor.maxRpm = s.baseMaxRpm end
        if motor.minForwardGearRatioOrigin ~= nil then
            motor.minForwardGearRatio = motor.minForwardGearRatioOrigin
        end
    end

    s.hookTouched = true
end

function RWEVehiclePhysics.restoreMotor(motor, s)
    if motor == nil then return end
    if motor.maxForwardSpeedOrigin ~= nil then motor.maxForwardSpeed = motor.maxForwardSpeedOrigin end
    if motor.maxBackwardSpeedOrigin ~= nil then motor.maxBackwardSpeed = motor.maxBackwardSpeedOrigin end
    if motor.minForwardGearRatioOrigin ~= nil then motor.minForwardGearRatio = motor.minForwardGearRatioOrigin end
    if s ~= nil and s.baseMaxRpm ~= nil then motor.maxRpm = s.baseMaxRpm end
    if s ~= nil and s.baseAccelLimit ~= nil and motor.setAccelerationLimit ~= nil then
        motor:setAccelerationLimit(s.baseAccelLimit)
    end
end

function RWEVehiclePhysics.installWheelsHook()
    if RWEVehiclePhysics._wheelsHookInstalled then return end
    if WheelsUtil ~= nil and type(WheelsUtil.updateWheelsPhysics) == "function" and Utils ~= nil then
        WheelsUtil.updateWheelsPhysics = Utils.prependedFunction(WheelsUtil.updateWheelsPhysics, function(self)
            RWEVehiclePhysics.applyMotorEnforcement(self)
        end)
        RWEVehiclePhysics._wheelsHookInstalled = true
        Logging.info("[RWEVehiclePhysics] WheelsUtil hook installed")
    end
end

-- =====================
-- TYPE INJECTION
-- Mirrors the proven Variable-Tire-Pressure / See & Spray pattern: hook
-- TypeManager.validateTypes and add this spec to every drivable + motorized +
-- wheeled vehicle type through the official addSpecialization API (which wires
-- the event listeners properly), not by poking the spec tables by hand.
-- =====================
function RWEVehiclePhysics.registerGlobally()
    if RWEVehiclePhysics._didRegisterGlobally then return end

    -- Wait until the vehicle type manager and its types are actually populated.
    if not (g_vehicleTypeManager and g_vehicleTypeManager.types) then return end

    local shortName = RWEVehiclePhysics.SPEC_NAME
    local fullName  = RWEVehiclePhysics.MOD_NAME .. "." .. shortName

    -- No modDesc <specialization> entry, so register the spec class here.
    -- Never double-register (that errors).
    if g_specializationManager
        and g_specializationManager:getSpecializationByName(fullName) == nil then
        local filename = Utils.getFilename("utils/VehiclePhysics.lua", RWEVehiclePhysics.MOD_DIR)
        g_specializationManager:addSpecialization(fullName, "RWEVehiclePhysics", filename, nil)
    end

    local added = 0
    for typeName, vehicleType in pairs(g_vehicleTypeManager.types) do
        if vehicleType and vehicleType.specializationsByName then
            local byName = vehicleType.specializationsByName
            local isDrivable  = byName["drivable"]  ~= nil
            local isMotorized = byName["motorized"] ~= nil
            local hasWheels   = byName["wheels"]    ~= nil
            -- Internals may key by either the full or short name - check both.
            local hasAlready  = (byName[fullName] ~= nil) or (byName[shortName] ~= nil)
            if isDrivable and isMotorized and hasWheels and not hasAlready then
                g_vehicleTypeManager:addSpecialization(typeName, fullName)
                added = added + 1
            end
        end
    end

    RWEVehiclePhysics._didRegisterGlobally = true
    Logging.info(string.format("[RWEVehiclePhysics] Injected into %d vehicle type(s)", added))
end

function RWEVehiclePhysics.installValidateHook()
    if RWEVehiclePhysics._validateHookInstalled then return end
    if TypeManager ~= nil and type(TypeManager.validateTypes) == "function" and Utils ~= nil then
        TypeManager.validateTypes = Utils.prependedFunction(
            TypeManager.validateTypes, RWEVehiclePhysics.registerGlobally)
        RWEVehiclePhysics._validateHookInstalled = true
        Logging.info("[RWEVehiclePhysics] validateTypes hook installed")
    end
end

-- Install the hooks the moment this file is sourced, before vehicle types
-- are validated at map load.
RWEVehiclePhysics.installValidateHook()
RWEVehiclePhysics.installWheelsHook()

Logging.info("[RWEVehiclePhysics] Module loaded")
