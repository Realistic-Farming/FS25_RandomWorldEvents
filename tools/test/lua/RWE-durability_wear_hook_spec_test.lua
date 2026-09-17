--!load: tools/test/lua/wear_harness.lua, utils/EffectHooks.lua
-- RWE equipment durability hook on the engine's real dispatch path. Usage damage
-- accrues through each vehicle's own updateDamageAmount (Wearable.lua:161-166); the
-- hook replaces that instance function from an appended Wearable.onLoad. Rows:
-- I the wrapper INSTALLS on a loaded vehicle, A damage APPLIES scaled after a tick,
-- S every vehicle in use is scaled (Design d3c0626: any player, a hired worker, an
-- implement, decided on the server), N what the engine does not charge stays 0,
-- P the remaining pass-throughs.

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

    local _, v = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self" })
    local values = {}
    Wearable.updateDebugValues(v, values)
    T.near("A5 named consequence: the debug damage readout (Wearable.lua:366) shows the scaled rate", values[1].value, 3600000 * WEAR.WEAR_DURATION * 0.35 * 1.2, 1e-9)
end

-- P: pass-throughs
do
    local d = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self", arcade = false })
    T.near("P1 arcade physics OFF: damage untouched", d, BASE, 1e-12)
    d = damageAfterTick({ state = {}, playerVehicle = "self" })
    T.near("P3 no durability event: damage untouched", d, BASE, 1e-12)
    local v = WEAR.loadVehicle(WEAR.EARLY_TYPE)
    g_RandomWorldEvents = nil
    g_localPlayer = { getCurrentVehicle = function() return v end }
    WEAR.tick(v, 1000)
    T.near("P4 no RWE singleton: damage untouched", v.spec_wearable.damage, BASE, 1e-12)
    d = damageAfterTick({ state = { durabilityMalus = 0.2 }, playerVehicle = "self" }, { isServer = false })
    T.eq("P5 [engine: a client accrues no usage damage]", d, 0)
end

-- S: every vehicle in use is scaled, whoever runs it
do
    -- a joined player's vehicle on a listen host: the server set isControlled for it
    -- (VehicleEnterResponseEvent.lua:45, Enterable.lua:712); the host player drives another
    local hostVehicle = WEAR.loadVehicle(WEAR.EARLY_TYPE)
    local clientVehicle = WEAR.loadVehicle(WEAR.EARLY_TYPE)
    WEAR.world({ state = {}, playerVehicle = hostVehicle })
    WEAR.tick(clientVehicle, 1000)
    T.near("S1a [reached: with no event the joined player's vehicle takes base damage]", clientVehicle.spec_wearable.damage, BASE, 1e-12)
    clientVehicle.spec_wearable.damage = 0
    WEAR.world({ state = { durabilityMalus = 0.2 }, playerVehicle = hostVehicle })
    WEAR.tick(clientVehicle, 1000)
    T.near("S1b NAMED: a vehicle a joined (non-local) player drives is scaled", clientVehicle.spec_wearable.damage, BASE * 1.2, 1e-12)

    -- a hired worker on a dedicated server: no local player at all, no one entered
    local worker = WEAR.loadVehicle(WEAR.MOTORIZED_TYPE, { active = false })
    worker.aiJobActive = true
    WEAR.world({ state = {}, noPlayer = true })
    WEAR.tick(worker, 1000)
    T.near("S2a [reached: with no event the hired worker's vehicle takes base damage]", worker.spec_wearable.damage, BASE, 1e-12)
    worker.spec_wearable.damage = 0
    WEAR.world({ state = { durabilityMalus = 0.2 }, noPlayer = true })
    WEAR.tick(worker, 1000)
    T.near("S2b NAMED: a hired worker's vehicle on a dedicated server (no local player) is scaled", worker.spec_wearable.damage, BASE * 1.2, 1e-12)

    -- an implement attached to a vehicle in use
    local tractor = WEAR.loadVehicle(WEAR.MOTORIZED_TYPE)
    local implement = WEAR.loadVehicle(WEAR.EARLY_TYPE, { active = false })
    implement.spec_attachable = { attacherVehicle = tractor }
    WEAR.world({ state = { durabilityBoost = 0.2 }, noPlayer = true })
    WEAR.tick(implement, 1000)
    T.near("S3a NAMED: an implement attached to a vehicle in use is scaled", implement.spec_wearable.damage, BASE * 0.8, 1e-12)
    implement.spec_wearable.damage = 0
    implement.spec_attachable.attacherVehicle = nil
    WEAR.tick(implement, 1000)
    T.eq("S3b [reached: the same implement detached takes no usage damage]", implement.spec_wearable.damage, 0)
end

-- N: what the engine does not charge stays untouched
do
    local parked = WEAR.loadVehicle(WEAR.EARLY_TYPE, { active = false })
    WEAR.world({ state = { durabilityMalus = 0.2 }, noPlayer = true })
    for _ = 1, 5 do WEAR.tick(parked, 1000) end
    T.eq("N1a NAMED: a parked vehicle takes 0 during a High Wear event and stays 0", parked.spec_wearable.damage, 0)
    parked.spec_enterable.isControlled = true
    WEAR.tick(parked, 1000)
    T.near("N1b [reached: the same vehicle, once driven, is scaled]", parked.spec_wearable.damage, BASE * 1.2, 1e-12)

    local idle = WEAR.loadVehicle(WEAR.MOTORIZED_TYPE, { motorState = "OFF" })
    WEAR.world({ state = { durabilityMalus = 0.2 }, noPlayer = true })
    WEAR.tick(idle, 1000)
    T.eq("N2a NAMED: a motorized vehicle with its motor off takes 0", idle.spec_wearable.damage, 0)
    idle.spec_motorized.motorState = "ON"
    WEAR.tick(idle, 1000)
    T.near("N2b [reached: the same vehicle with the motor on is scaled]", idle.spec_wearable.damage, BASE * 1.2, 1e-12)
end
