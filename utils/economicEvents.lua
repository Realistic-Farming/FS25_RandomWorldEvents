-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- Economic events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================
-- EC-6 (brief v1.7 sections 3.1 and 3.3):
--   * Price events move selling-point prices only through MarketDynamics' registered
--     modifier (integrations/RWEMarketBridge.lua) and are eligible only while that
--     price status is "available". Their notices name the direction and "the next
--     market update", never a figure.
--   * Money events queue one statement line per eligible farm at event start, with
--     the amount fixed then; the lines settle at the next in-game day
--     (utils/RWESettlement.lua). Shared notices never name a euro amount; each paid
--     farm sees its own amount privately.
--   * Loan charges read only the farm's native loan, never its cash.
--   * Retired on Arissani's 2026-09-16 rulings: seed_discount, fertilizer_discount,
--     equipment_discount and tax_refund. Economic events go from 14 to 10.
-- =========================================================

local economicEvents = {}

local function mgr() return g_RandomWorldEvents end

local function priceAvailable()
    return RWEMarketBridge ~= nil and RWEMarketBridge.priceStatus() == RWEMarketBridge.STATUS_AVAILABLE
end

local function oldMarketExcluded(name)
    return RWEMarketBridge ~= nil and RWEMarketBridge.isOldMarketExcluded(name)
end

local function title(name) return "rwe_event_" .. name .. "_title" end
local function key(name, part) return "rwe_event_" .. name .. "_" .. part end

--- A money event: queue one line per candidate farm, amountFor(farm, i) returning a
--- signed whole amount or nil for an ineligible farm.
local function queueLines(name, moneyTypeName, intensity, amountFor)
    if RWESettlement == nil then return 0 end
    return RWESettlement.queueForFarms(name, moneyTypeName, title(name), function(farm) return amountFor(farm, intensity) end)
end

local function anyFarm(predicate)
    return RWESettlement ~= nil and RWESettlement.anyFarm(predicate)
end

local function setFlag(field, value)
    local m = mgr()
    if m ~= nil then m.EVENT_STATE[field] = value end
end

-- =====================
-- ECONOMIC EVENTS
-- =====================
economicEvents.eventList = {
    {
        name = "government_subsidy", minI = 1,
        summaryKey = "rwe_summary_money_every_credit",
        canTrigger = function()
            return not oldMarketExcluded("government_subsidy") and anyFarm(function() return true end)
        end,
        func = function(intensity)
            queueLines("government_subsidy", "OTHER", intensity, function(farm, i) return 5000 + 2500 * i end)
            return { key = key("government_subsidy", "start") }
        end,
    },

    {
        name = "market_boom", minI = 1,
        summaryKey = "rwe_summary_price_rise",
        canTrigger = priceAvailable,
        applyFlags = function(intensity) setFlag("marketBonus", 0.1 + intensity * 0.05) end,
        func = function(intensity)
            economicEvents.byName.market_boom.applyFlags(intensity)
            return { key = key("market_boom", "start") }
        end,
        onMid = function(intensity) return { key = key("market_boom", "mid") } end,
        ambientMsgs = { key("market_boom", "ambient1"), key("market_boom", "ambient2"), key("market_boom", "ambient3"), key("market_boom", "ambient4") },
    },

    {
        name = "market_crash", minI = 1,
        summaryKey = "rwe_summary_price_fall",
        canTrigger = priceAvailable,
        applyFlags = function(intensity) setFlag("marketMalus", 0.1 + intensity * 0.05) end,
        func = function(intensity)
            economicEvents.byName.market_crash.applyFlags(intensity)
            return { key = key("market_crash", "start") }
        end,
        onMid = function(intensity) return { key = key("market_crash", "mid") } end,
        ambientMsgs = { key("market_crash", "ambient1"), key("market_crash", "ambient2"), key("market_crash", "ambient3"), key("market_crash", "ambient4") },
    },

    {
        name = "sudden_expense", minI = 1,
        summaryKey = "rwe_summary_money_every_debit",
        canTrigger = function() return anyFarm(function() return true end) end,
        func = function(intensity)
            queueLines("sudden_expense", "OTHER", intensity, function(farm, i) return -(2000 + 1000 * i) end)
            return { key = key("sudden_expense", "start") }
        end,
    },

    {
        name = "farmer_donation", minI = 1,
        summaryKey = "rwe_summary_money_every_credit",
        canTrigger = function() return anyFarm(function() return true end) end,
        func = function(intensity)
            queueLines("farmer_donation", "OTHER", intensity, function(farm, i) return 1000 * i end)
            return { key = key("farmer_donation", "start") }
        end,
    },

    {
        name = "insurance_bonus", minI = 1,
        summaryKey = "rwe_summary_money_every_credit",
        canTrigger = function() return anyFarm(function() return true end) end,
        func = function(intensity)
            queueLines("insurance_bonus", "OTHER", intensity, function(farm, i) return 3000 + 1000 * i end)
            return { key = key("insurance_bonus", "start") }
        end,
    },

    {
        name = "price_fixing", minI = 2,
        summaryKey = "rwe_summary_price_rise",
        canTrigger = priceAvailable,
        applyFlags = function(intensity)
            setFlag("priceFixing", 0.15 + 0.05 * intensity)
            setFlag("priceFixingDuration", 15 * intensity)
        end,
        func = function(intensity)
            economicEvents.byName.price_fixing.applyFlags(intensity)
            return { key = key("price_fixing", "start") }
        end,
        onMid = function(intensity) return { key = key("price_fixing", "mid") } end,
        ambientMsgs = { key("price_fixing", "ambient1"), key("price_fixing", "ambient2") },
    },

    {
        name = "loan_interest", minI = 1,
        summaryKey = "rwe_summary_money_loan",
        -- Eligible when at least one farm's native loan gives a line of at least 1 at
        -- the lowest intensity; a higher intensity only raises the line.
        canTrigger = function()
            return anyFarm(function(farm) return RWESettlement.loanLine(farm, 0.02, 1) ~= nil end)
        end,
        func = function(intensity)
            queueLines("loan_interest", "LOAN_INTEREST", intensity, function(farm, i)
                local line = RWESettlement.loanLine(farm, 0.02, i)
                return line ~= nil and -line or nil
            end)
            return { key = key("loan_interest", "start") }
        end,
    },

    {
        name = "export_opportunity", minI = 3,
        summaryKey = "rwe_summary_price_rise",
        canTrigger = priceAvailable,
        applyFlags = function(intensity)
            setFlag("exportBonus", 0.25 + 0.05 * intensity)
            setFlag("exportDuration", 30 * intensity)
        end,
        func = function(intensity)
            economicEvents.byName.export_opportunity.applyFlags(intensity)
            return { key = key("export_opportunity", "start") }
        end,
        onMid = function(intensity) return { key = key("export_opportunity", "mid") } end,
        ambientMsgs = { key("export_opportunity", "ambient1"), key("export_opportunity", "ambient2"), key("export_opportunity", "ambient3"), key("export_opportunity", "ambient4") },
    },

    {
        name = "economic_crisis", minI = 4,
        -- Parts recorded at activation, never recomputed from later loans or status:
        -- crisisHasPrice (price status available) and crisisHasLoan (a loan line queued).
        canTrigger = function()
            if oldMarketExcluded("economic_crisis") then return false end
            return priceAvailable() or anyFarm(function(farm) return RWESettlement.loanLine(farm, 0.05, 1) ~= nil end)
        end,
        applyFlags = function(intensity)
            setFlag("economicCrisis", {
                marketMalus = 0.2 + 0.1 * intensity,
                loanPenalty = 0.05 * intensity,
                duration    = 60 * intensity,
            })
        end,
        func = function(intensity)
            economicEvents.byName.economic_crisis.applyFlags(intensity)
            local hasPrice = priceAvailable()
            local loans = queueLines("economic_crisis", "LOAN_INTEREST", intensity, function(farm, i)
                local line = RWESettlement.loanLine(farm, 0.05, i)
                return line ~= nil and -line or nil
            end)
            local m = mgr()
            local d = m ~= nil and m.EVENT_STATE.eventData or {}
            d.crisisHasPrice = hasPrice
            d.crisisHasLoan = loans > 0
            if d.crisisHasPrice and d.crisisHasLoan then return { key = key("economic_crisis", "start_both") } end
            if d.crisisHasLoan then return { key = key("economic_crisis", "start_loan") } end
            return { key = key("economic_crisis", "start_price") }
        end,
        --- The start copy's row, which is also the saved and synced summary.
        chooseSummary = function(d)
            if d.crisisHasPrice == true and d.crisisHasLoan == true then return "rwe_summary_crisis_both" end
            if d.crisisHasLoan == true then return "rwe_summary_crisis_loan" end
            if d.crisisHasPrice == true then return "rwe_summary_crisis_price" end
            return nil
        end,
        onMid = function(intensity) return { key = key("economic_crisis", "mid") } end,
        endNotice = { key = key("economic_crisis", "end") },
        ambientVariants = {
            both = { key("economic_crisis", "ambient_both1"), key("economic_crisis", "ambient_both2"), key("economic_crisis", "ambient_both3") },
            price = { key("economic_crisis", "ambient_price1"), key("economic_crisis", "ambient_price2"), key("economic_crisis", "ambient_price3") },
            loan = { key("economic_crisis", "ambient_loan1"), key("economic_crisis", "ambient_loan2"), key("economic_crisis", "ambient_loan3") },
        },
    },
}

economicEvents.byName = {}
for _, e in ipairs(economicEvents.eventList) do economicEvents.byName[e.name] = e end

-- =====================
-- REGISTER ECONOMIC EVENTS
-- =====================
local function registerEconomicEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[EconomicEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(economicEvents.eventList) do
        local def = e
        g_RandomWorldEvents:registerEvent({
            name            = def.name,
            category        = "economic",
            weight          = 1,
            duration        = { min = 15, max = 60 },
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
                    s.marketBonus         = nil
                    s.marketMalus         = nil
                    s.priceFixing         = nil
                    s.priceFixingDuration = nil
                    s.exportBonus         = nil
                    s.exportDuration      = nil
                    s.economicCrisis      = nil
                end
                return def.endNotice
            end
        })
    end

    Logging.info("[EconomicEvents] Registered " .. #economicEvents.eventList .. " economic events")
    return true
end

-- =====================
-- DELAYED REGISTRATION
-- =====================
if g_RandomWorldEvents and g_RandomWorldEvents.registerEvent then
    registerEconomicEvents()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, registerEconomicEvents)
    Logging.info("[EconomicEvents] Added to pending registrations")
end

Logging.info("[EconomicEvents] Module loaded successfully")
