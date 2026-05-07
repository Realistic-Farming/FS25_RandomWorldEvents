-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- Vehicle events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================

local vehicleEvents = {}

vehicleEvents.getFarmId = function()
    return g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 0
end

vehicleEvents.getVehicle = function()
    return g_currentMission and g_currentMission.controlledVehicle or nil
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

-- =====================
-- VEHICLE SPEED SYSTEM
-- =====================
vehicleEvents.applyVehicleSpeedBoost = function(vehicle, multiplier)
    if not vehicle or not vehicle.setSpeedLimit then return end
    if not vehicle.originalSpeedLimit then
        vehicle.originalSpeedLimit = vehicle.speedLimit or 100
    end
    vehicle.speedLimit = vehicle.originalSpeedLimit * multiplier
    vehicle:setSpeedLimit(vehicle.speedLimit)
    if vehicle.maxSpeed then
        if not vehicle.originalMaxSpeed then
            vehicle.originalMaxSpeed = vehicle.maxSpeed
        end
        vehicle.maxSpeed = vehicle.originalMaxSpeed * multiplier
    end
end

vehicleEvents.resetVehicleSpeed = function(vehicle)
    if not vehicle then return end
    if vehicle.originalSpeedLimit then
        vehicle.speedLimit = vehicle.originalSpeedLimit
        vehicle:setSpeedLimit(vehicle.speedLimit)
        vehicle.originalSpeedLimit = nil
    end
    if vehicle.originalMaxSpeed then
        vehicle.maxSpeed = vehicle.originalMaxSpeed
        vehicle.originalMaxSpeed = nil
    end
end

-- =====================
-- VEHICLE FUEL SYSTEM
-- =====================
vehicleEvents.fillVehicleFuel = function(vehicle)
    if not vehicle or not vehicle.getFillUnits then return 0 end
    local filledAmount = 0
    if vehicle.getFillUnitInformation then
        local fillUnits = vehicle:getFillUnitInformation()
        if fillUnits then
            for _, fillUnit in ipairs(fillUnits) do
                if fillUnit.fillType ~= FillType.UNKNOWN then
                    local toFill = fillUnit.capacity - fillUnit.fillLevel
                    if toFill > 0 then
                        vehicle:setFillUnitFillLevel(fillUnit.index, fillUnit.capacity, fillUnit.fillType)
                        filledAmount = filledAmount + toFill
                    end
                end
            end
        end
    end
    return filledAmount
end

vehicleEvents.drainVehicleFuel = function(vehicle, percentage)
    if not vehicle or not vehicle.getFillUnits then return 0 end
    local drainedAmount = 0
    if vehicle.getFillUnitInformation then
        local fillUnits = vehicle:getFillUnitInformation()
        if fillUnits then
            for _, fillUnit in ipairs(fillUnits) do
                if fillUnit.fillType ~= FillType.UNKNOWN then
                    local toDrain = fillUnit.fillLevel * (percentage / 100)
                    if toDrain > 0 then
                        vehicle:setFillUnitFillLevel(fillUnit.index, fillUnit.fillLevel - toDrain, fillUnit.fillType)
                        drainedAmount = drainedAmount + toDrain
                    end
                end
            end
        end
    end
    return drainedAmount
end

-- =====================
-- VEHICLE DAMAGE SYSTEM
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
    if g_currentMission and g_currentMission.addMoney then
        g_currentMission:addMoney(-repairCost, vehicleEvents.getFarmId(), MoneyType.VEHICLE_REPAIR, true)
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
            if vehicle then
                local multiplier = 1.2 + (intensity * 0.1)
                vehicleEvents.applyVehicleSpeedBoost(vehicle, multiplier)
                if g_RandomWorldEvents then
                    g_RandomWorldEvents.EVENT_STATE.vehicleSpeedBoost = { vehicle = vehicle, multiplier = multiplier }
                end
                return string.format("Turbo day! Your machine is running %.0f%% faster.", (multiplier - 1) * 100)
            end
            return "Speed boost available — climb into a vehicle to feel it!"
        end,
        onMid = function(intensity)
            local mult = 1.2 + intensity * 0.1
            return string.format("Still running hot! +%.0f%% speed boost continues.", (mult - 1) * 100)
        end,
        ambientMsgs = {
            "The engine note is higher than usual — everything feels responsive today.",
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
                return "Free fuel — tanks were already full."
            end
            return "Free fuel waiting — get in a vehicle!"
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
                    return string.format("Fuel leak! %.0fL drained — check your tank connections.", drainedAmount)
                end
                return "Fuel leak warning — but the tank was already low."
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
                if g_currentMission and g_currentMission.addMoney then
                    g_currentMission:addMoney(-repairCost, vehicleEvents.getFarmId(), MoneyType.VEHICLE_REPAIR, true)
                end
                if g_RandomWorldEvents then
                    g_RandomWorldEvents.EVENT_STATE.vehicleAccident = { vehicle = vehicle, damagePercent = damagePercent }
                end
                return string.format("Fender bender! %.0f%% damage — €%d repair bill already submitted.", damagePercent, repairCost)
            end
            return "Something scraped past, but nobody was in a vehicle."
        end,
        ambientMsgs = {
            "The dent is nagging at you. Should've watched that gatepost.",
            "Workshop called — parts are on order. Shouldn't affect performance too badly.",
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
                return string.format("%d machine%s serviced. Total bill: €%d.", repairedCount, repairedCount > 1 and "s" or "", totalCost)
            end
            return "Service van arrived — all machines already in top shape."
        end,
    },

    {
        name = "vehicle_free_upgrade",
        minI = 1,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle then
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
            return "Free upgrade kit arrived — get in a vehicle!"
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
            return "Cleaning crew arrived — machines were already gleaming."
        end,
    },

    {
        name = "vehicle_engine_trouble",
        minI = 2,
        func = function(intensity)
            local vehicle = vehicleEvents.getVehicle()
            if vehicle then
                if vehicle.getMotor then
                    local motor = vehicle:getMotor()
                    if motor then
                        if not motor.originalPower then
                            motor.originalPower = motor.maxPower or 100
                        end
                        motor.maxPower = motor.originalPower * (1 - (0.1 * intensity))
                        if g_RandomWorldEvents then
                            g_RandomWorldEvents.EVENT_STATE.engineTrouble = {
                                vehicle = vehicle,
                                motor   = motor,
                                originalPower = motor.originalPower
                            }
                        end
                        return string.format("Engine misfiring! -%.0f%% power — limp it home.", intensity * 10)
                    end
                end
            end
            return "Engine warning light came on, but no vehicle is running."
        end,
        onMid = function(intensity)
            return string.format("Engine still struggling — down %.0f%% power. Get to the workshop soon.", intensity * 10)
        end,
        ambientMsgs = {
            "The revs are hunting. Something isn't right under the hood.",
            "Black smoke from the exhaust. Don't push it too hard.",
            "The dashboard warning light is still on. Power feels sluggish.",
        },
    },
}

-- =====================
-- TICK HANDLER
-- =====================
local function vehicleTickHandler(rwe)
    local eventData = rwe.EVENT_STATE
    if not eventData.vehicleSpeedBoost then return end
    local vehicle = g_currentMission and g_currentMission.controlledVehicle
    if vehicle and vehicle == eventData.vehicleSpeedBoost.vehicle then
        vehicleEvents.applyVehicleSpeedBoost(vehicle, eventData.vehicleSpeedBoost.multiplier)
    end
end

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
            duration     = { min = 10, max = 30 },
            minIntensity = e.minI,
            canTrigger   = function() return g_currentMission ~= nil end,
            onStart      = e.func,
            onMid        = e.onMid,
            ambientMsgs  = e.ambientMsgs,
            onEnd = function()
                if g_RandomWorldEvents then
                    local d = g_RandomWorldEvents.EVENT_STATE
                    if d.vehicleSpeedBoost then
                        vehicleEvents.resetVehicleSpeed(d.vehicleSpeedBoost.vehicle)
                        d.vehicleSpeedBoost = nil
                    end
                    if d.vehicleUpgrade then
                        local v = d.vehicleUpgrade.vehicle
                        if v and v.originalColor then
                            local r, g, b = unpack(v.originalColor)
                            v:setColor(r, g, b)
                            v.originalColor = nil
                        end
                        d.vehicleUpgrade = nil
                    end
                    if d.engineTrouble then
                        local motor = d.engineTrouble.motor
                        if motor and d.engineTrouble.originalPower then
                            motor.maxPower = d.engineTrouble.originalPower
                        end
                        d.engineTrouble = nil
                    end
                    d.vehicleAccident = nil
                end
                return nil
            end
        })
    end

    g_RandomWorldEvents:registerTickHandler("vehicleEvents", vehicleTickHandler)

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
