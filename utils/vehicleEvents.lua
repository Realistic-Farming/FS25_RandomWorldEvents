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
-- EC-6 (brief v1.7 sections 3.3, 3.4 and 3.8):
--   * vehicle_accident and vehicle_repair_bill no longer write any vehicle. Each
--     queues one invoice line per eligible farm (a farm with a motorized vehicle, or
--     a farm with a machine above 10 percent damage), settled at the next in-game
--     day. The notices describe an invoice; no machine was damaged or repaired.
--   * vehicle_speed_boost and vehicle_engine_trouble are arcade physics events:
--     host-local, eligible only with Arcade Physics on and the host player in a
--     vehicle on a listen server. Their factors are stored once in eventData at
--     activation, and their notices say the direction only.
-- =========================================================

local vehicleEvents = {}

vehicleEvents.getVehicle = function()
    -- FS25: the player's vehicle comes from g_localPlayer:getCurrentVehicle()
    -- (returns nil on foot). g_currentMission.controlledVehicle is a fallback.
    local player = g_localPlayer
    local cur = (player ~= nil and player.getCurrentVehicle ~= nil) and player:getCurrentVehicle() or nil
    local ctrl = (g_currentMission ~= nil) and g_currentMission.controlledVehicle or nil
    return cur or ctrl
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

local function key(name, part) return "rwe_event_" .. name .. "_" .. part end
local function title(name) return "rwe_event_" .. name .. "_title" end

local function ambients(name, count)
    local out = {}
    for n = 1, count do out[n] = key(name, "ambient" .. n) end
    return out
end

--- The host-local arcade eligibility (the core applies the same rule to every
--- arcade event; each event also carries it as its own canTrigger).
local function arcadeEligible()
    return g_RandomWorldEvents ~= nil and g_RandomWorldEvents:arcadeEligible()
end

--- Store the arcade factors once, at activation, and apply them to the host
--- player's vehicle. Every later line derives from the stored values.
local function applyArcadeFactors(speedScale, accelScale)
    local d = g_RandomWorldEvents ~= nil and g_RandomWorldEvents.EVENT_STATE.eventData or nil
    if type(d) == "table" then
        d.speedScale = speedScale
        d.accelScale = accelScale
    end
    local vehicle = vehicleEvents.getVehicle()
    if vehicle and RWEVehiclePhysics then
        RWEVehiclePhysics.applyEventMods(vehicle, { speedScale = speedScale, accelScale = accelScale })
        vehicleEvents.trackPhysics(vehicle)
    end
end

-- =====================
-- VEHICLE EVENTS
-- =====================
vehicleEvents.eventList = {
    {
        name = "vehicle_speed_boost",
        minI = 1,
        gate = "arcadePhysics",
        canTrigger = arcadeEligible,
        func = function(intensity)
            -- speedScale raises the real top speed (taller top gear);
            -- accelScale adds extra pull off the line.
            applyArcadeFactors(1.25 + (intensity * 0.12), 1.20 + (intensity * 0.06))
            return { key = key("vehicle_speed_boost", "start") }
        end,
        onMid = function(intensity) return { key = key("vehicle_speed_boost", "mid") } end,
        endNotice = { key = key("vehicle_speed_boost", "end") },
        ambientMsgs = ambients("vehicle_speed_boost", 3),
    },

    {
        name = "vehicle_accident",
        minI = 1,
        summaryKey = "rwe_summary_bill_accident",
        canTrigger = function()
            return RWESettlement ~= nil and RWESettlement.anyFarm(function(farm) return RWESettlement.farmHasMotorized(farm.farmId) end)
        end,
        func = function(intensity)
            if RWESettlement ~= nil then
                RWESettlement.queueForFarms("vehicle_accident", "VEHICLE_REPAIR", title("vehicle_accident"), function(farm)
                    if not RWESettlement.farmHasMotorized(farm.farmId) then return nil end
                    return -(math.random(500, 1500) * intensity)
                end)
            end
            return { key = key("vehicle_accident", "start") }
        end,
        ambientMsgs = ambients("vehicle_accident", 2),
    },

    {
        name = "vehicle_repair_bill",
        minI = 1,
        summaryKey = "rwe_summary_bill_inspection",
        canTrigger = function()
            return RWESettlement ~= nil and RWESettlement.anyFarm(function(farm) return #RWESettlement.farmDamagedVehicles(farm.farmId) > 0 end)
        end,
        func = function(intensity)
            if RWESettlement ~= nil then
                RWESettlement.queueForFarms("vehicle_repair_bill", "VEHICLE_REPAIR", title("vehicle_repair_bill"), function(farm)
                    local damaged = RWESettlement.farmDamagedVehicles(farm.farmId)
                    if #damaged == 0 then return nil end
                    local total = 0
                    for _ = 1, #damaged do total = total + math.random(500, 2000) end
                    return -total
                end)
            end
            return { key = key("vehicle_repair_bill", "start") }
        end,
    },

    {
        name = "vehicle_engine_trouble",
        minI = 2,
        gate = "arcadePhysics",
        canTrigger = arcadeEligible,
        func = function(intensity)
            -- Real "limp home": cut acceleration hard (sluggish engine)
            -- and shave the top speed. Both are engine-respected levers.
            applyArcadeFactors(math.max(0.5, 1 - (0.06 * intensity)), math.max(0.35, 1 - (0.12 * intensity)))
            return { key = key("vehicle_engine_trouble", "start") }
        end,
        onMid = function(intensity) return { key = key("vehicle_engine_trouble", "mid") } end,
        endNotice = { key = key("vehicle_engine_trouble", "end") },
        ambientMsgs = ambients("vehicle_engine_trouble", 3),
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
        local def = e
        g_RandomWorldEvents:registerEvent({
            name            = def.name,
            category        = "vehicle",
            weight          = 1,
            duration        = def.dur or { min = 10, max = 30 },
            minIntensity    = def.minI,
            gate            = def.gate,
            applyFlags      = def.applyFlags,
            summaryKey      = def.summaryKey,
            chooseSummary   = def.chooseSummary,
            ambientVariants = def.ambientVariants,
            canTrigger      = function() return g_currentMission ~= nil and (def.canTrigger == nil or def.canTrigger()) end,
            onStart         = def.func,
            onMid           = def.onMid,
            ambientMsgs     = def.ambientMsgs,
            onEnd = function()
                -- Restore any vehicle physics modifiers (speed / engine)
                -- applied by this event.
                vehicleEvents.restoreTrackedPhysics()
                -- Arcade events end with a host-local notice (the core never sends it).
                return def.endNotice
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
