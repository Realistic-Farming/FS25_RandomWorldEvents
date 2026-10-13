-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- Special events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================
-- EC-6 (brief v1.7 sections 3.1, 3.3.6, 3.4.3 and 3.8):
--   * special_event_festival and bonus_trade_prices are price events through
--     MarketDynamics' registered modifier, eligible only while the price status is
--     "available". The festival's per-minute income trickle is removed; the festival
--     is price only.
--   * The equipment durability pair is arcade physics, off by default. It scales
--     usage wear on every vehicle in use and is eligible on any server with Arcade
--     Physics on, a dedicated one included (Design d3c0626). Its wear fraction is stored
--     once in eventData at activation and its notices say the direction only.
-- =========================================================

local specialEvents = {}

local function priceAvailable()
    return RWEMarketBridge ~= nil and RWEMarketBridge.priceStatus() == RWEMarketBridge.STATUS_AVAILABLE
end

local function durabilityEligible()
    return g_RandomWorldEvents ~= nil and g_RandomWorldEvents:durabilityEligible()
end

local function key(name, part) return "rwe_event_" .. name .. "_" .. part end

local function ambients(name, count)
    local out = {}
    for n = 1, count do out[n] = key(name, "ambient" .. n) end
    return out
end

local function setFlag(field, value)
    if g_RandomWorldEvents then g_RandomWorldEvents.EVENT_STATE[field] = value end
end

local function storeWear(fraction)
    local d = g_RandomWorldEvents ~= nil and g_RandomWorldEvents.EVENT_STATE.eventData or nil
    if type(d) == "table" then d.wearFraction = fraction end
end

specialEvents.eventList = {
    {
        name = "special_event_festival", minI = 1,
        summaryKey = "rwe_summary_price_rise",
        canTrigger = priceAvailable,
        applyFlags = function(intensity) setFlag("marketBonus", 0.05 + 0.03 * intensity) end,
        func = function(intensity)
            specialEvents.byName.special_event_festival.applyFlags(intensity)
            return { key = key("special_event_festival", "start") }
        end,
        onMid = function(intensity) return { key = key("special_event_festival", "mid") } end,
        ambientMsgs = ambients("special_event_festival", 4),
    },

    {
        name = "equipment_durability_boost", minI = 1, gate = "arcadePhysics", arcadeScope = "server",
        canTrigger = durabilityEligible,
        applyFlags = function(intensity) setFlag("durabilityBoost", 0.15 + 0.05 * intensity) end,
        func = function(intensity)
            specialEvents.byName.equipment_durability_boost.applyFlags(intensity)
            storeWear(0.15 + 0.05 * intensity)
            return { key = key("equipment_durability_boost", "start") }
        end,
        onMid = function(intensity) return { key = key("equipment_durability_boost", "mid") } end,
        endNotice = { key = key("equipment_durability_boost", "end") },
        ambientMsgs = ambients("equipment_durability_boost", 2),
    },

    {
        name = "equipment_durability_drop", minI = 1, gate = "arcadePhysics", arcadeScope = "server",
        canTrigger = durabilityEligible,
        applyFlags = function(intensity) setFlag("durabilityMalus", 0.15 + 0.05 * intensity) end,
        func = function(intensity)
            specialEvents.byName.equipment_durability_drop.applyFlags(intensity)
            storeWear(0.15 + 0.05 * intensity)
            return { key = key("equipment_durability_drop", "start") }
        end,
        onMid = function(intensity) return { key = key("equipment_durability_drop", "mid") } end,
        endNotice = { key = key("equipment_durability_drop", "end") },
        ambientMsgs = ambients("equipment_durability_drop", 3),
    },

    {
        name = "bonus_trade_prices", minI = 1,
        summaryKey = "rwe_summary_price_rise",
        canTrigger = priceAvailable,
        applyFlags = function(intensity) setFlag("tradeBonus", 0.10 + 0.05 * intensity) end,
        func = function(intensity)
            specialEvents.byName.bonus_trade_prices.applyFlags(intensity)
            return { key = key("bonus_trade_prices", "start") }
        end,
        onMid = function(intensity) return { key = key("bonus_trade_prices", "mid") } end,
        ambientMsgs = ambients("bonus_trade_prices", 2),
    },
}

specialEvents.byName = {}
for _, e in ipairs(specialEvents.eventList) do specialEvents.byName[e.name] = e end

-- =====================
-- REGISTER SPECIAL EVENTS
-- =====================
local function registerSpecialEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[SpecialEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(specialEvents.eventList) do
        local def = e
        g_RandomWorldEvents:registerEvent({
            name            = def.name,
            category        = "special",
            weight          = 1,
            duration        = { min = 10, max = 60 },
            minIntensity    = def.minI,
            gate            = def.gate,
            arcadeScope     = def.arcadeScope,
            applyFlags      = def.applyFlags,
            summaryKey      = def.summaryKey,
            chooseSummary   = def.chooseSummary,
            ambientVariants = def.ambientVariants,
            canTrigger      = function() return g_currentMission ~= nil and (def.canTrigger == nil or def.canTrigger()) end,
            onStart         = def.func,
            onMid           = def.onMid,
            ambientMsgs     = def.ambientMsgs,
            onEnd = function()
                if g_RandomWorldEvents then
                    local s = g_RandomWorldEvents.EVENT_STATE
                    s.durabilityBoost = nil
                    s.durabilityMalus = nil
                    s.tradeBonus      = nil
                    s.marketBonus     = nil
                end
                -- Arcade events end with a host-local notice (the core never sends it).
                return def.endNotice
            end
        })
    end

    Logging.info("[SpecialEvents] Registered " .. #specialEvents.eventList .. " special events")
    return true
end

-- =====================
-- DELAYED REGISTRATION
-- =====================
if g_RandomWorldEvents and g_RandomWorldEvents.registerEvent then
    registerSpecialEvents()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, registerSpecialEvents)
    Logging.info("[SpecialEvents] Added to pending registrations")
end

Logging.info("[SpecialEvents] Module loaded successfully")
