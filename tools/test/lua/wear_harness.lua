-- wear_harness.lua: the FS25 engine pieces the RWE durability hook sits on, copied
-- from the decompiled scripts (D:\FS25_Decoded\dataS\scripts_decompiled). Loaded
-- through --!load BEFORE utils/EffectHooks.lua, the way the base game has sourced
-- its specializations before any mod script runs.
--
--   SpecializationUtil.raiseEvent          specialization/SpecializationUtil.lua:17-26
--   SpecializationUtil.copyTypeFunctionsInto specialization/SpecializationUtil.lua:141-145
--   Vehicle:load order (functions copied at :486, onLoad raised at :866)
--   Wearable:onUpdateTick                  vehicles/specializations/Wearable.lua:161-175
--   Wearable:setDamageAmount               Wearable.lua:177-185 (network flags left out)
--   Wearable:updateDamageAmount            Wearable.lua:190-200 (lifetime factor 1)
--   Wearable:updateDebugValues             Wearable.lua:364-370
--   Wearable:getUsageCausesDamage          Wearable.lua:204-209 (sleep test as a flag)
--   Motorized:getUsageCausesDamage         Motorized.lua:1997-2003 (overwritten function)
--   Vehicle:update isActive refresh        Vehicle.lua:1527, getIsActive chain:
--     Enterable:getIsActive  (isEntered or isControlled)   Enterable.lua:992-995
--     AIJobVehicle:getIsActive (a hired worker's job)       AIJobVehicle.lua:251-253
--     Attachable:getIsActive (the attacher is active)       Attachable.lua:1456-1466

WEAR = WEAR or {}

SpecializationUtil = SpecializationUtil or {}
function SpecializationUtil.raiseEvent(object, eventName, ...)
    for _, spec in ipairs(object.eventListeners[eventName]) do
        spec[eventName](object, ...)
    end
end
function SpecializationUtil.copyTypeFunctionsInto(typeDef, target)
    for funcName, func in pairs(typeDef.functions) do
        target[funcName] = func
    end
end

Wearable = {}
function Wearable:onLoad(_)
    local spec = self.spec_wearable
    spec.damage = 0
    spec.damageSent = 0
    spec.wearDuration = WEAR.WEAR_DURATION
end
function Wearable:getUsageCausesDamage()
    if self.spec_motorized == nil and self.sleeping then
        return false
    end
    return self.isActive and self.propertyState ~= "MISSION"
end

--- Motorized's overwritten getUsageCausesDamage: only while the motor is starting or on.
function WEAR.motorizedUsageCausesDamage(self)
    local motorState = self.spec_motorized.motorState
    if motorState == "STARTING" or motorState == "ON" then
        return Wearable.getUsageCausesDamage(self)
    end
    return false
end

--- The getIsActive chain for the specializations a vehicle has.
function WEAR.getIsActive(v)
    if v.spec_enterable ~= nil and (v.spec_enterable.isEntered or v.spec_enterable.isControlled) then
        return true
    end
    if v.aiJobActive then
        return true
    end
    if v.spec_attachable ~= nil and v.spec_attachable.attacherVehicle ~= nil then
        return WEAR.getIsActive(v.spec_attachable.attacherVehicle)
    end
    return false
end
function Wearable:updateDamageAmount(dt)
    if not self:getUsageCausesDamage() then
        return 0
    end
    local factor = 1
    return dt * self.spec_wearable.wearDuration * 0.35 * factor
end
function Wearable:setDamageAmount(amount, force)
    local spec = self.spec_wearable
    spec.damage = math.min(math.max(amount, 0), 1)
end
function Wearable:getDamageAmount()
    return self.spec_wearable.damage
end
function Wearable:onUpdateTick(dt, _, _, _)
    local spec = self.spec_wearable
    if self.isServer then
        local changeAmount = self:updateDamageAmount(dt)
        if changeAmount ~= 0 then
            self:setDamageAmount(spec.damage + changeAmount)
        end
    end
end
function Wearable:updateDebugValues(values)
    local changedAmount = self:updateDamageAmount(3600000)
    table.insert(values, { name = "Damage", value = changedAmount })
end

WEAR.WEAR_DURATION = 0.0001    -- a round number: one 1000 ms tick of base usage damage is 0.035

--- A vehicle type's function table, captured the way Wearable.registerFunctions
--- does (Wearable.lua:27-50). Captured here, at harness load, so it predates the
--- mod script: the hook must not depend on when the capture happened.
function WEAR.captureType(motorized)
    return {
        functions = {
            updateDamageAmount = Wearable.updateDamageAmount,
            setDamageAmount    = Wearable.setDamageAmount,
            getDamageAmount    = Wearable.getDamageAmount,
            getUsageCausesDamage = motorized and WEAR.motorizedUsageCausesDamage or Wearable.getUsageCausesDamage,
        },
    }
end
WEAR.EARLY_TYPE = WEAR.captureType(false)
WEAR.MOTORIZED_TYPE = WEAR.captureType(true)

--- Load one vehicle in the engine's order: copy the type's functions onto the
--- instance, then raise onLoad through the listener table.
function WEAR.loadVehicle(typeDef, opts)
    opts = opts or {}
    local v = { spec_wearable = {}, isServer = opts.isServer ~= false }
    -- Driven by a player unless told otherwise (opts.active = false parks it).
    v.spec_enterable = { isEntered = false, isControlled = opts.active ~= false }
    if typeDef == WEAR.MOTORIZED_TYPE then
        v.spec_motorized = { motorState = opts.motorState or "ON" }
    end
    v.eventListeners = { onLoad = { Wearable }, onUpdateTick = { Wearable } }
    SpecializationUtil.copyTypeFunctionsInto(typeDef, v)
    SpecializationUtil.raiseEvent(v, "onLoad", nil)
    return v
end

function WEAR.tick(v, dt)
    v.isActive = WEAR.getIsActive(v)    -- Vehicle.lua:1527, before the update tick
    SpecializationUtil.raiseEvent(v, "onUpdateTick", dt, false, false, false)
end

--- The RWE singleton, the local player and the mission, as the hook reads them.
function WEAR.world(opts)
    opts = opts or {}
    g_RandomWorldEvents = {
        EVENT_STATE = opts.state or {},
        arcade = opts.arcade ~= false,
    }
    function g_RandomWorldEvents:allowsArcadePhysics() return self.arcade end
    local current = opts.playerVehicle
    if opts.noPlayer then
        g_localPlayer = nil
    else
        g_localPlayer = { getCurrentVehicle = function() return current end }
    end
    g_currentMission = { controlledVehicle = opts.controlledVehicle }
end
