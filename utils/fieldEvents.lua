-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- Field events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================
-- EC-6 (brief v1.7 sections 3.1, 3.8 and 3.9.1):
--   * The crop, fertilizer and seed events are PULL read-signals: RandomWorldEvents
--     sets the EVENT_STATE flags and the owning systems decide what they mean. Their
--     notices describe conditions and name no yield, fertilizer or seed percentage.
--   * Harvest and field-sale events are price events through MarketDynamics'
--     registered modifier, eligible only while the price status is "available".
--   * Every field event keeps the field loop's own fields-exist check (it used to be
--     the loop's shared canTrigger); it now travels in each event's own canTrigger.
--   * While MarketDynamics needs an update, the crop-yield pair is ineligible: an
--     older MarketDynamics prices those two names by itself.
-- =========================================================

local fieldEvents = {}

local function priceAvailable()
    return RWEMarketBridge ~= nil and RWEMarketBridge.priceStatus() == RWEMarketBridge.STATUS_AVAILABLE
end

local function oldMarketExcluded(name)
    return RWEMarketBridge ~= nil and RWEMarketBridge.isOldMarketExcluded(name)
end

--- The field loop's fields-exist check (unchanged from the pre-EC-6 loop).
function fieldEvents.fieldsExist()
    if g_fieldManager then
        local fields = g_fieldManager:getFields()
        return fields ~= nil and #fields > 0
    end
    return g_currentMission ~= nil
end

local function key(name, part) return "rwe_event_" .. name .. "_" .. part end

local function setFlag(field, value)
    if g_RandomWorldEvents then g_RandomWorldEvents.EVENT_STATE[field] = value end
end

--- A condition signal: sets flags, needs fields, and (for the crop-yield pair) is
--- excluded while an older MarketDynamics would price it.
local function signal(name, flags, ambientCount, extraCheck)
    local e = {
        name = name, minI = 1,
        summaryKey = "rwe_summary_" .. name,
        applyFlags = flags,
        canTrigger = function()
            if extraCheck ~= nil and not extraCheck() then return false end
            return fieldEvents.fieldsExist()
        end,
        onMid = function(intensity) return { key = key(name, "mid") } end,
        ambientMsgs = {},
    }
    e.func = function(intensity)
        e.applyFlags(intensity)
        return { key = key(name, "start") }
    end
    for n = 1, ambientCount do e.ambientMsgs[n] = key(name, "ambient" .. n) end
    return e
end

--- A price event: sets flags for other readers, needs fields and an available market.
local function priceEvent(name, summaryKey, flags, ambientCount)
    local e = signal(name, flags, ambientCount, priceAvailable)
    e.summaryKey = summaryKey
    return e
end

fieldEvents.eventList = {
    signal("crop_yield_bonus",
        function(i) setFlag("yieldBonus", 0.05 * i) end, 4,
        function() return not oldMarketExcluded("crop_yield_bonus") end),
    signal("crop_yield_penalty",
        function(i) setFlag("yieldMalus", 0.05 * i) end, 3,
        function() return not oldMarketExcluded("crop_yield_penalty") end),
    signal("fertilizer_bonus",
        function(i) setFlag("fertilizerBonus", 0.10 + 0.05 * i) end, 2),
    signal("fertilizer_penalty",
        function(i) setFlag("fertilizerMalus", 0.10 + 0.05 * i) end, 2),
    signal("seed_growth_bonus",
        function(i) setFlag("seedBonus", 0.10 + 0.05 * i) end, 2),
    signal("seed_growth_penalty",
        function(i) setFlag("seedMalus", 0.10 + 0.05 * i) end, 2),
    priceEvent("harvest_bonus", "rwe_summary_price_rise",
        function(i) setFlag("harvestBonus", 0.10 + 0.05 * i) end, 3),
    priceEvent("harvest_penalty", "rwe_summary_price_fall",
        function(i) setFlag("harvestMalus", 0.10 + 0.05 * i) end, 3),
    priceEvent("field_sale_bonus", "rwe_summary_price_rise",
        function(i) setFlag("fieldSaleBonus", 0.05 * i) end, 2),
    priceEvent("field_sale_penalty", "rwe_summary_price_fall",
        function(i) setFlag("fieldSaleMalus", 0.05 * i) end, 2),
}

-- =====================
-- REGISTER FIELD EVENTS
-- =====================
local function registerFieldEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[FieldEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(fieldEvents.eventList) do
        local def = e
        g_RandomWorldEvents:registerEvent({
            name            = def.name,
            category        = "field",
            weight          = 1,
            duration        = { min = 30, max = 120 },
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
                if g_RandomWorldEvents then
                    local s = g_RandomWorldEvents.EVENT_STATE
                    s.yieldBonus      = nil
                    s.yieldMalus      = nil
                    s.fertilizerBonus = nil
                    s.fertilizerMalus = nil
                    s.seedBonus       = nil
                    s.seedMalus       = nil
                    s.harvestBonus    = nil
                    s.harvestMalus    = nil
                    s.fieldSaleBonus  = nil
                    s.fieldSaleMalus  = nil
                end
                return nil
            end
        })
    end

    Logging.info("[FieldEvents] Registered " .. #fieldEvents.eventList .. " field events")
    return true
end

-- =====================
-- DELAYED REGISTRATION
-- =====================
if g_RandomWorldEvents and g_RandomWorldEvents.registerEvent then
    registerFieldEvents()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, registerFieldEvents)
    Logging.info("[FieldEvents] Added to pending registrations")
end

Logging.info("[FieldEvents] Module loaded successfully")
