--!load: tools/test/lua/wear_harness.lua, utils/EffectHooks.lua
-- RWE equipment durability hook on the engine's real dispatch path. Usage damage
-- accrues through each vehicle's own updateDamageAmount (Wearable.lua:161-166); the
-- hook replaces that instance function from an appended Wearable.onLoad. Rows:
-- I the wrapper INSTALLS on a loaded vehicle, A damage APPLIES scaled after a tick,
-- P every pass-through the arcade-physics gate and player-vehicle rule keep.

local BASE = 1000 * WEAR.WEAR_DURATION * 0.35   -- one 1000 ms tick of usage damage

local function damageAfterTick(worldOpts, vehicleOpts)
    local v = WEAR.loadVehicle(WEAR.EARLY_TYPE, vehicleOpts)
    if worldOpts.playerVehicle == "self" then worldOpts.playerVehicle = v end
    if worldOpts.controlledVehicle == "self" then worldOpts.controlledVehicle = v end
    WEAR.world(worldOpts)
    WEAR.tick(v, 1000)
    return v.spec_wearable.damage, v
end

-- I: installs
do
    WEAR.world({})
    local v = WEAR.loadVehicle(WEAR.EARLY_TYPE)
    T.ok("I1a [reached: the vehicle got the type's own function first]", WEAR.EARLY_TYPE.functions.updateDamageAmount == Wearable.updateDamageAmount)
    T.ok("I1b NAMED: INSTALLED, the loaded vehicle's own updateDamageAmount is the RWE wrapper", v.updateDamageAmount ~= WEAR.EARLY_TYPE.functions.updateDamageAmount)
    T.eq("I1c and is marked wrapped", v.rweUsageDamageWrapped, true)
    SpecializationUtil.raiseEvent(v, "onLoad", nil)
    WEAR.world({ state = { durabilityMalus = 0.2 }, playerVehicle = v })
    v.spec_wearable.damage = 0
    WEAR.tick(v, 1000)
    T.near("I2 a second onLoad never wraps twice (scaled once)", v.spec_wearable.damage, BASE * 1.2, 1e-12)
end

-- A: applies
do
    local d = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self" })
    T.near("A1 NAMED: APPLIES, High Wear (malus 0.2) makes one tick's damage 1.2x", d, BASE * 1.2, 1e-12)
    d = damageAfterTick({ state = { durabilityBoost = 0.2 }, playerVehicle = "self" })
    T.near("A2 NAMED: APPLIES, Low Wear (boost 0.2) makes one tick's damage 0.8x", d, BASE * 0.8, 1e-12)
    d = damageAfterTick({ state = { durabilityBoost = 1.5 }, playerVehicle = "self" })
    T.eq("A3 a boost past 1 floors at no damage, never negative", d, 0)
    d = damageAfterTick({ state = { durabilityMalus = 0.2 }, noPlayer = true, controlledVehicle = "self" })
    T.near("A4 with no local player the mission's controlled vehicle is the player's", d, BASE * 1.2, 1e-12)

    local _, v = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self" })
    local values = {}
    Wearable.updateDebugValues(v, values)
    T.near("A5 named consequence: the debug damage readout (Wearable.lua:366) shows the scaled rate", values[1].value, 3600000 * WEAR.WEAR_DURATION * 0.35 * 1.2, 1e-9)
end

-- P: pass-throughs
do
    local d = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self", arcade = false })
    T.near("P1 arcade physics OFF: damage untouched", d, BASE, 1e-12)
    local other = {}
    d = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = other })
    T.near("P2 an NPC or other vehicle: damage untouched", d, BASE, 1e-12)
    d = damageAfterTick({ state = {}, playerVehicle = "self" })
    T.near("P3 no durability event: damage untouched", d, BASE, 1e-12)
    local v = WEAR.loadVehicle(WEAR.EARLY_TYPE)
    g_RandomWorldEvents = nil
    g_localPlayer = { getCurrentVehicle = function() return v end }
    WEAR.tick(v, 1000)
    T.near("P4 no RWE singleton: damage untouched", v.spec_wearable.damage, BASE, 1e-12)
    d = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self" }, { isServer = false })
    T.eq("P5 [engine: a client accrues no usage damage]", d, 0)
    v = WEAR.loadVehicle(WEAR.EARLY_TYPE)
    v.usageCausesDamage = false
    WEAR.world({ state = { durabilityMalus = 0.2 }, playerVehicle = v })
    WEAR.tick(v, 1000)
    T.eq("P6 no usage damage stays no damage", v.spec_wearable.damage, 0)
end
