-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- Vehicle events for FS25
--
-- All physics-affecting events route through RWEVehiclePhysics
-- (utils/VehiclePhysics.lua), which touches only real, engine-read
-- fields and restores them cleanly. The old no-op fields
-- (motor.maxPower, vehicle.maxSpeed, vehicle:setSpeedLimit) are gone.
-- =========================================================
-- Author: TisonK
-- =========================================================

local vehicleEvents = {}

-- Server-authoritative money. addMoney must run only on the server in multiplayer,
-- or every client applies the change (desync); the engine syncs the balance back.
local function rweAddMoney(...)
    if g_currentMission and g_currentMission:getIsServer() then
        g_currentMission:addMoney(...)
    end
end

vehicleEvents.getFarmId = function()
    -- FS25: the player's farm comes from g_localPlayer, not the old
    -- g_currentMission.player (nil here) - which returned 0 and sent every
    -- repair charge to "no farm" while making getAllVehicles match nothing.
    if g_localPlayer ~= nil and type(g_localPlayer.farmId) == "number" and g_localPlayer.farmId > 0 then
        return g_localPlayer.farmId
    end
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local ok, fid = pcall(function() return g_currentMission:getFarmId() end)
        if ok and type(fid) == "number" and fid > 0 then return fid end
    end
    if g_currentMission ~= nil and g_currentMission.player ~= nil and g_currentMission.player.farmId then
        return g_currentMission.player.farmId
    end
    return 0
end

vehicleEvents.getVehicle = function()
    -- FS25: the player's vehicle comes from g_localPlayer:getCurrentVehicle()
    -- (returns nil on foot). g_currentMission.controlledVehicle is a fallback.
    local player = g_localPlayer
    local cur = (player ~= nil and player.getCurrentVehicle ~= nil) and player:getCurrentVehicle() or nil
    local ctrl = (g_currentMission ~= nil) and g_currentMission.controlledVehicle or nil
    return cur or ctrl
end

vehicleEvents.getAllVehicles = function()
    local vehicles = {}
    if g_currentMission and g_currentMission.vehicles then
        for _, vehicle in pairs(g_currentMission.vehicles) do
            if vehicle and vehicle.getOwnerFarmId and vehicle:getOwnerFarmId() == vehicleEvents.getFarmId() then
                table.insert(vehicles, vehicle)
            end
        end
    end
    return vehicles
end

-- Convenience: remember which vehicle an active physics event touched so
-- onEnd can restore it even after the player swaps machines.
vehicleEvents.trackPhysics = function(vehicle)
    if g_RandomWorldEvents then
        g_RandomWorldEvents.EVENT_STATE.vehiclePhysics = { vehicle = vehicle }
    end
end

vehicleEvents.restoreTrackedPhysics = function()
    if not g_RandomWorldEvents then return end
    local d = g_RandomWorldEvents.EVENT_STATE.vehiclePhysics
    if d and d.vehicle and RWEVehiclePhysics then
        RWEVehiclePhysics.clearEventMods(d.vehicle)
    end
    if g_RandomWorldEvents.EVENT_STATE then
        g_RandomWorldEvents.EVENT_STATE.vehiclePhysics = nil
    end
end

-- =====================
-- VEHICLE FUEL SYSTEM (real FS25 FillUnit API)
-- The old code used getFillUnitInformation()/setFillUnitFillLevel() which do
-- not exist in FS25 - the events did nothing. The correct path (per the game's
-- own VehicleSystem) is getConsumerFillUnitIndex() to find the fuel tank, then
-- addFillUnitFillLevel(farmId, index, delta, fillType, toolType, ...).
-- =====================

-- Collect the vehicle's fuel/consumable fill-unit indices (diesel / electric /
-- methane / DEF). Returns a list of fill-unit indices.
vehicleEvents.getFuelFillUnits = function(vehicle)
    local units = {}
    if not vehicle or vehicle.getConsumerFillUnitIndex == nil then return units end
    local fuelTypes = { FillType.DIESEL, FillType.ELECTRICCHARGE, FillType.METHANE, FillType.DEF }
    for _, ft in ipairs(fuelTypes) do
        if ft ~= nil then
            local idx = vehicle:getConsumerFillUnitIndex(ft)
            if idx ~= nil then
                table.insert(units, idx)
            end
        end
    end
    return units
end

vehicleEvents.fillVehicleFuel = function(vehicle)
    if not vehicle then return 0 end
    local farmId = vehicleEvents.getFarmId()
    if farmId <= 0 then return 0 end
    local filled = 0
    for _, idx in ipairs(vehicleEvents.getFuelFillUnits(vehicle)) do
        local capacity = vehicle:getFillUnitCapacity(idx)
        local level    = vehicle:getFillUnitFillLevel(idx)
        local fillType = vehicle:getFillUnitFirstSupportedFillType(idx)
        if capacity and level and fillType and fillType ~= FillType.UNKNOWN then
            local toFill = capacity - level
            if toFill > 0 then
                vehicle:addFillUnitFillLevel(farmId, idx, toFill, fillType, ToolType.UNDEFINED, nil)
                filled = filled + toFill
            end
        end
    end
    return filled
end

vehicleEvents.drainVehicleFuel = function(vehicle, percentage)
    if not vehicle then return 0 end
    local farmId = vehicleEvents.getFarmId()
    if farmId <= 0 then return 0 end
    local drained = 0
    for _, idx in ipairs(vehicleEvents.getFuelFillUnits(vehicle)) do
        local level    = vehicle:getFillUnitFillLevel(idx)
        local fillType = vehicle:getFillUnitFirstSupportedFillType(idx)
        if level and fillType and fillType ~= FillType.UNKNOWN then
            local toDrain = level * (percentage / 100)
            if toDrain > 0 then
                vehicle:addFillUnitFillLevel(farmId, idx, -toDrain, fillType, ToolType.UNDEFINED, nil)
                drained = drained + toDrain
            end
        end
    end
    return drained
end

-- =====================
-- VEHICLE DAMAGE SYSTEM (real: Wearable API)
-- Note: vehicle damage also reduces engine torque and top speed natively
-- (getTorqueCurveValue / getSpeedLimit apply a damage factor), so an
-- accident genuinely weakens the machine - no faked power loss needed.
-- =====================
vehicleEvents.applyVehicleDamage = function(vehicle, damagePercentage)
    if not vehicle then return end
    local damageAmount = damagePercentage / 100
    if vehicle.addDamageAmount then
        vehicle:addDamageAmount(damageAmount)
    elseif vehicle.spec_wearable then
        local spec = vehicle.spec_wearable
        local newDamage = math.min((spec.damage or 0) + damageAmount, 1)
        spec.damage = newDamage
        spec.damageByCurve = math.max(newDamage - 0.3, 0) / 0.7
    end
end

vehicleEvents.repairVehicleDamage = function(vehicle)
    if not vehicle or not vehicle.repair then return 0 end
    vehicle:repair()
    local repairCost = math.random(500, 2000)
    local farmId = vehicleEvents.getFarmId()
    if farmId > 0 and g_currentMission and g_currentMission.addMoney then
        rweAddMoney(-repairCost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
    end
    return repairCost
end

-- =====================
-- VEHICLE EVENTS
-- =====================
vehicleEvents.eventList = {
    {
        name = "vehicle_speed_boost",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle and RWEVehiclePhysics then
                local multiplier = 1.25 + (intensity * 0.12)  -- ~1.37x .. 1.85x top speed
                -- speedScale raises the real top speed (taller top gear);
                -- accelScale adds extra pull off the line.
                local accelBoost = 1.20 + (intensity * 0.06)  -- ~1.26x .. 1.50x acceleration
                RWEVehiclePhysics.applyEventMods(vehicle, { speedScale = multiplier, accelScale = accelBoost })
                vehicleEvents.trackPhysics(vehicle)
                return string.format("Turbo day! Your machine is running %.0f%% faster.", (multiplier - 1) * 100)
            end
            return "Speed boost available - climb into a vehicle to feel it!"
        end,
        onMid = function(intensity)
            local mult = 1.2 + intensity * 0.1
            return string.format("Still running hot! +%.0f%% speed boost continues.", (mult - 1) * 100)
        end,
        ambientMsgs = {
            "The engine note is higher than usual - everything feels responsive today.",
            "You're covering ground fast. The fields won't know what hit them.",
            "Neighbours are asking what you put in the tank. It's a good day to work.",
        },
    },

    {
        name = "vehicle_fuel_bonus",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle then
                local filledAmount = vehicleEvents.fillVehicleFuel(vehicle)
                if filledAmount > 0 then
                    return string.format("Mystery fuel delivery! Tanks topped up (+%.1fL).", filledAmount)
                end
                return "Free fuel - tanks were already full."
            end
            return "Free fuel waiting - get in a vehicle!"
        end,
    },

    {
        name = "vehicle_fuel_penalty",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle then
                local drainPercent = 20 + (intensity * 10)
                local drainedAmount = vehicleEvents.drainVehicleFuel(vehicle, drainPercent)
                if drainedAmount > 0 then
                    return string.format("Fuel leak! %.0fL drained - check your tank connections.", drainedAmount)
                end
                return "Fuel leak warning - but the tank was already low."
            end
            return "Fuel leak detected, but no vehicle is running."
        end,
        ambientMsgs = {
            "You can smell diesel. Something's dripping under the machine.",
            "The fuel gauge is dropping faster than it should.",
        },
    },

    {
        name = "vehicle_accident",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle then
                local damagePercent = 10 + (intensity * 5)
                vehicleEvents.applyVehicleDamage(vehicle, damagePercent)
                local repairCost = math.random(500, 1500) * intensity
                local farmId = vehicleEvents.getFarmId()
                if farmId > 0 and g_currentMission and g_currentMission.addMoney then
                    rweAddMoney(-repairCost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
                end
                if g_RandomWorldEvents then
                    g_RandomWorldEvents.EVENT_STATE.vehicleAccident = { vehicle = vehicle, damagePercent = damagePercent }
                end
                return string.format("Fender bender! %.0f%% damage - EUR %d repair bill already submitted.", damagePercent, repairCost)
            end
            return "Something scraped past, but nobody was in a vehicle."
        end,
        ambientMsgs = {
            "The dent is nagging at you. Should've watched that gatepost.",
            "The machine feels a touch down on power since the knock. Workshop soon.",
        },
    },

    {
        name = "vehicle_repair_bill",
        minI = 1,
        func = function(intensity)
            local vehicles = vehicleEvents.getAllVehicles()
            local totalCost = 0
            local repairedCount = 0
            for _, vehicle in ipairs(vehicles) do
                if vehicle and vehicle.getDamageAmount then
                    local damage = vehicle:getDamageAmount() or 0
                    if damage > 0.1 then
                        local cost = vehicleEvents.repairVehicleDamage(vehicle)
                        totalCost = totalCost + cost
                        repairedCount = repairedCount + 1
                    end
                end
            end
            if repairedCount > 0 then
                return string.format("%d machine%s serviced. Total bill: EUR %d.", repairedCount, repairedCount > 1 and "s" or "", totalCost)
            end
            return "Service van arrived - all machines already in top shape."
        end,
    },

    {
        name = "vehicle_free_upgrade",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle and vehicle.getColor and vehicle.setColor then
                if not vehicle.originalColor then
                    vehicle.originalColor = { vehicle:getColor() }
                end
                local r, g, b = unpack(vehicle.originalColor)
                vehicle:setColor(r * 1.2, g * 1.1, b * 0.9)
                if g_RandomWorldEvents then
                    g_RandomWorldEvents.EVENT_STATE.vehicleUpgrade = { vehicle = vehicle }
                end
                return "Showroom shine! Your machine got a fresh golden coat."
            end
            return "Free upgrade kit arrived - get in a vehicle!"
        end,
        ambientMsgs = {
            "Heads are turning as you drive past. The paint job looks immaculate.",
            "Someone asked if it was a new model. Close enough.",
        },
    },

    {
        name = "vehicle_cleaning_bonus",
        minI = 1,
        func = function(intensity)
            local vehicles = vehicleEvents.getAllVehicles()
            local cleanedCount = 0
            for _, vehicle in ipairs(vehicles) do
                if vehicle and vehicle.getDirtAmount then
                    if (vehicle:getDirtAmount() or 0) > 0 then
                        vehicle:setDirtAmount(0)
                        cleanedCount = cleanedCount + 1
                    end
                end
            end
            if cleanedCount > 0 then
                return string.format("Pressure wash crew showed up! %d machine%s spotless.", cleanedCount, cleanedCount > 1 and "s" or "")
            end
            return "Cleaning crew arrived - machines were already gleaming."
        end,
    },

    {
        name = "vehicle_engine_trouble",
        minI = 2,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle and RWEVehiclePhysics then
                -- Real "limp home": cut acceleration hard (sluggish engine)
                -- and shave the top speed. Both are engine-respected levers.
                local accelScale = math.max(0.35, 1 - (0.12 * intensity))
                local speedScale = math.max(0.5,  1 - (0.06 * intensity))
                RWEVehiclePhysics.applyEventMods(vehicle, { accelScale = accelScale, speedScale = speedScale })
                vehicleEvents.trackPhysics(vehicle)
                return string.format("Engine misfiring! Down on power - limp it home.")
            end
            return "Engine warning light came on, but no vehicle is running."
        end,
        onMid = function(intensity)
            return "Engine still struggling - sluggish and slow. Get to the workshop soon."
        end,
        ambientMsgs = {
            "The revs are hunting. Something isn't right under the hood.",
            "Black smoke from the exhaust. Don't push it too hard.",
            "It crawls away from every stop. Power feels gone.",
        },
    },

    {
        name = "vehicle_steering_pull",
        minI = 2,
        -- Short event; the pull itself comes in periodic eased tugs, not a
        -- constant lean (see RWEVehiclePhysics.onPreUpdate).
        dur = { min = 2, max = 4 },
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle and RWEVehiclePhysics then
                local side = (math.random() < 0.5) and -1 or 1
                local pull = side * math.min(0.40, 0.12 + 0.04 * intensity)
                RWEVehiclePhysics.applyEventMods(vehicle, { steerPull = pull })
                vehicleEvents.trackPhysics(vehicle)
                local dir = side < 0 and "left" or "right"
                return string.format("Loose front axle! The wheel keeps tugging to the %s.", dir)
            end
            return "Steering feels off, but no vehicle is running."
        end,
        onMid = function(intensity)
            return "Still tugging every so often - keep a hand on the wheel."
        end,
        ambientMsgs = {
            "Every now and then the wheel jerks to one side.",
            "That tie rod really needs looking at.",
        },
    },

    {
        name = "vehicle_slippery_roads",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle and RWEVehiclePhysics then
                -- Greasy, low-traction conditions: calmer throttle and a
                -- lower safe speed so the machine is easier to keep straight.
                local accelScale = math.max(0.4, 1 - (0.10 * intensity))
                local speedScale = math.max(0.55, 1 - (0.08 * intensity))
                RWEVehiclePhysics.applyEventMods(vehicle, { accelScale = accelScale, speedScale = speedScale })
                vehicleEvents.trackPhysics(vehicle)
                return "Slippery going! Easy on the throttle until the roads dry out."
            end
            return "Roads are greasy out there - mind your footing."
        end,
        onMid = function(intensity)
            return "Surfaces are still slick. Take it steady."
        end,
        ambientMsgs = {
            "The tyres are scrabbling for grip on every pull-away.",
            "A light film of mud on the road has everything sliding.",
        },
    },
}

-- =====================
-- REGISTER VEHICLE EVENTS
-- =====================
local function registerVehicleEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[VehicleEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(vehicleEvents.eventList) do
        g_RandomWorldEvents:registerEvent({
            name         = e.name,
            category     = "vehicle",
            weight       = 1,
            duration     = e.dur or { min = 10, max = 30 },
            minIntensity = e.minI,
            canTrigger   = function() return g_currentMission ~= nil end,
            onStart      = e.func,
            onMid        = e.onMid,
            ambientMsgs  = e.ambientMsgs,
            onEnd = function()
                if g_RandomWorldEvents then
                    local d = g_RandomWorldEvents.EVENT_STATE

                    -- Restore any vehicle physics modifiers (speed / engine /
                    -- steering) applied by this event.
                    vehicleEvents.restoreTrackedPhysics()

                    if d.vehicleUpgrade then
                        local v = d.vehicleUpgrade.vehicle
                        if v and v.originalColor and v.setColor then
                            local r, g, b = unpack(v.originalColor)
                            v:setColor(r, g, b)
                            v.originalColor = nil
                        end
                        d.vehicleUpgrade = nil
                    end

                    d.vehicleAccident = nil
                end
                return nil
            end
        })
    end

    Logging.info("[VehicleEvents] Registered " .. #vehicleEvents.eventList .. " vehicle events")
    return true
end

-- =====================
-- DELAYED REGISTRATION
-- =====================
if g_RandomWorldEvents and g_RandomWorldEvents.registerEvent then
    registerVehicleEvents()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, registerVehicleEvents)
    Logging.info("[VehicleEvents] Added to pending registrations")
end

Logging.info("[VehicleEvents] Module loaded successfully")
