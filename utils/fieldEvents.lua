-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- Field events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================

local fieldEvents = {}

-- Server-authoritative money. addMoney must run only on the server in multiplayer,
-- or every client applies the change (desync); the engine syncs the balance back.
local function rweAddMoney(...)
    if g_currentMission and g_currentMission:getIsServer() then
        g_currentMission:addMoney(...)
    end
end

fieldEvents.eventList = {
    {
        name="crop_yield_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.yieldBonus = 0.05 * intensity
            end
            return string.format("Perfect growing conditions! Yields up %.0f%%.", (0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Crops still thriving — %.0f%% yield bonus active.", (0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "The fields look unusually lush. Something in the air this week.",
            "Neighbours are commenting on the colour of your crop — deep green all the way.",
            "Agronomist says conditions are near perfect. Make the most of it.",
            "Rain and sun in just the right balance — the stalks are heavy.",
        },
    },

    {
        name="crop_yield_penalty", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.yieldMalus = 0.05 * intensity
            end
            return string.format("Poor conditions — yields down %.0f%%.", (0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Conditions haven't improved — still %.0f%% below normal yield.", (0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "The crop looks thinner than last season. Hard to say why.",
            "Soil moisture levels are off. The plants are stressed.",
            "Agronomist flagged a nutrient issue — yields will suffer this run.",
        },
    },

    {
        name="fertilizer_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.fertilizerBonus = 0.10 + 0.05 * intensity
            end
            return string.format("Nutrient surge! Fertilizer %.0f%% more effective.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Soil is absorbing fertilizer exceptionally well — keep applying."
        end,
        ambientMsgs = {
            "The nitrogen is working overtime today. Fields are drinking it up.",
            "Soil temp is ideal for nutrient uptake — spreader is earning its keep.",
        },
    },

    {
        name="fertilizer_penalty", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.fertilizerMalus = 0.10 + 0.05 * intensity
            end
            return string.format("Soil lock-up — fertilizer %.0f%% less effective.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Soil chemistry still fighting the fertilizer. Efficiency remains low."
        end,
        ambientMsgs = {
            "pH is off in the top fields — nutrients aren't binding properly.",
            "Heavy rain is washing fertilizer down before it can be absorbed.",
        },
    },

    {
        name="seed_growth_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.seedBonus = 0.10 + 0.05 * intensity
            end
            return string.format("Fast germination! Seeds %.0f%% more productive.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Seedlings are pushing up fast — this batch is vigorous."
        end,
        ambientMsgs = {
            "Germination rates are unusually high this planting. Very few gaps.",
            "The new batch of seeds is showing exceptional vigour in the rows.",
        },
    },

    {
        name="seed_growth_penalty", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.seedMalus = 0.10 + 0.05 * intensity
            end
            return string.format("Poor germination — %.0f%% growth setback.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Patchy emergence across the field — growth penalty ongoing."
        end,
        ambientMsgs = {
            "Gaps in the rows. The cold snap hit germination hard.",
            "A few patches didn't take at all. Replanting would cost more than it's worth.",
        },
    },

    {
        name="harvest_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.harvestBonus = 0.10 + 0.05 * intensity
            end
            return string.format("Premium harvest! Sell prices up %.0f%%.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Harvest premium still active — %.0f%% above market rate.", (0.10 + 0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "Quality assessors at the silo are grading everything top tier today.",
            "Buyers are paying above the board rate for this quality of grain.",
            "Moisture content is perfect — driers are sitting idle. Straight to storage.",
        },
    },

    {
        name="harvest_penalty", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.harvestMalus = 0.10 + 0.05 * intensity
            end
            return string.format("Low-grade harvest — prices down %.0f%%.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Quality still down — %.0f%% price penalty continuing.", (0.10 + 0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "The silo is rejecting some loads — protein content is too low.",
            "Moisture is high after the rain. The drier is running non-stop.",
            "Market graders are being strict today. Even decent grain is marked down.",
        },
    },

    {
        name="field_sale_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.fieldSaleBonus = 0.05 * intensity
            end
            return string.format("Regional demand spike! Field sale prices up %.0f%%.", (0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Demand is holding — still %.0f%% above normal at the sell point.", (0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "The regional mill is calling farmers directly — they need volume now.",
            "Word from the co-op: they're short on stocks and prices are up.",
        },
    },

    {
        name="field_sale_penalty", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.fieldSaleMalus = 0.05 * intensity
            end
            return string.format("Market glut — field sale prices down %.0f%%.", (0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Oversupply continues — %.0f%% below normal at the silo.", (0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "Silos in the region are full — buyers are being picky about price.",
            "Import prices dropped overnight. Domestic grain has nowhere to go.",
        },
    },
}

-- =====================
-- TICK HANDLER
-- =====================
local function fieldTickHandler(rwe)
    if not g_currentMission then return end
    local s = rwe.EVENT_STATE
    local t = g_currentMission.time
    local lastTick = s.lastFieldTick or 0
    if t - lastTick < 60000 then return end
    s.lastFieldTick = t

    local farmId = g_currentMission.player and g_currentMission.player.farmId or 0
    if farmId == 0 then return end

    local amount = 0
    if s.fertilizerBonus then amount = amount + math.floor(500 * s.fertilizerBonus) end
    if s.fertilizerMalus then amount = amount - math.floor(400 * s.fertilizerMalus) end
    if s.seedBonus       then amount = amount + math.floor(300 * s.seedBonus)       end
    if s.seedMalus       then amount = amount - math.floor(250 * s.seedMalus)       end

    if amount ~= 0 and g_currentMission.addMoney then
        rweAddMoney(amount, farmId, MoneyType.OTHER, false)
    end
end

-- =====================
-- REGISTER FIELD EVENTS
-- =====================
local function registerFieldEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[FieldEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(fieldEvents.eventList) do
        g_RandomWorldEvents:registerEvent({
            name         = e.name,
            category     = "field",
            weight       = 1,
            duration     = { min = 30, max = 120 },
            minIntensity = e.minI,
            canTrigger   = function()
                if g_fieldManager then
                    local fields = g_fieldManager:getFields()
                    return fields ~= nil and #fields > 0
                end
                return g_currentMission ~= nil
            end,
            onStart     = e.func,
            onMid       = e.onMid,
            ambientMsgs = e.ambientMsgs,
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
                    s.lastFieldTick   = nil
                end
                return nil
            end
        })
    end

    g_RandomWorldEvents:registerTickHandler("fieldEvents", fieldTickHandler)

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
