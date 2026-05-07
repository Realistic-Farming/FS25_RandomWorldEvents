-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- Economic events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================

local economicEvents = {}

economicEvents.getFarmId = function()
    return g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 0
end

economicEvents.getFarmMoney = function()
    local farmId = economicEvents.getFarmId()
    if farmId > 0 and g_farmManager then
        local farm = g_farmManager:getFarmById(farmId)
        return farm and farm.money or 0
    end
    return 0
end

-- =====================
-- ECONOMIC EVENTS
-- =====================
economicEvents.eventList = {
    {
        name="government_subsidy", minI=1,
        func=function(intensity)
            local amount = 5000 + intensity * 2500
            if g_currentMission and g_currentMission.addMoney then
                g_currentMission:addMoney(amount, economicEvents.getFarmId(), MoneyType.OTHER, true)
            end
            return string.format("Government subsidy! +€%d landed in your account.", amount)
        end,
        -- Instant payout — no duration effects, so no ambient/mid needed.
    },

    {
        name="market_boom", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.marketBonus = 0.1 + intensity * 0.05
            end
            return string.format("MARKET BOOM! Sell prices up %.0f%%!", (0.1 + intensity * 0.05) * 100)
        end,
        onMid = function(intensity)
            return string.format("Market boom still running — %.0f%% bonus on all sales.", (0.1 + intensity * 0.05) * 100)
        end,
        ambientMsgs = {
            "Trading floors are buzzing — buyers are hungry for your crops.",
            "Commodity futures hit a seasonal high. Time to sell big.",
            "Local co-op reports record purchase volumes this week.",
            "Grain trucks are lined up at every silo in the region.",
        },
    },

    {
        name="market_crash", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.marketMalus = 0.1 + intensity * 0.05
            end
            return string.format("MARKET CRASH! Sell prices down %.0f%%!", (0.1 + intensity * 0.05) * 100)
        end,
        onMid = function(intensity)
            return string.format("Market crash continues — prices still %.0f%% below normal. Hold if you can.", (0.1 + intensity * 0.05) * 100)
        end,
        ambientMsgs = {
            "Traders are dumping stock — oversupply has tanked the market.",
            "The regional grain exchange reports no bids at yesterday's prices.",
            "Farmers across the county are holding off on sales, hoping for recovery.",
            "Market analysts say the slump may last several more days.",
        },
    },

    {
        name="sudden_expense", minI=1,
        func=function(intensity)
            local amount = 2000 + 1000 * intensity
            if g_currentMission and g_currentMission.addMoney then
                g_currentMission:addMoney(-amount, economicEvents.getFarmId(), MoneyType.OTHER, true)
            end
            return string.format("Unexpected expense! -€%d deducted.", amount)
        end,
    },

    {
        name="farmer_donation", minI=1,
        func=function(intensity)
            local amount = 1000 * intensity
            if g_currentMission and g_currentMission.addMoney then
                g_currentMission:addMoney(amount, economicEvents.getFarmId(), MoneyType.OTHER, true)
            end
            return string.format("Neighbour donated €%d — community spirit!", amount)
        end,
    },

    {
        name="seed_discount", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.seedDiscount = 0.1 + 0.05 * intensity
            end
            return string.format("Seed sale on at the co-op! -%.0f%% while stocks last.", (0.1 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Seed discount still active — stock up before the sale ends!"
        end,
        ambientMsgs = {
            "The co-op's seed aisles are busy — farmers filling their boots.",
            "Suppliers are clearing last season's inventory at reduced rates.",
        },
    },

    {
        name="fertilizer_discount", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.fertilizerDiscount = 0.1 + 0.05 * intensity
            end
            return string.format("Fertilizer on sale! -%.0f%% at all suppliers.", (0.1 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Fertilizer discount still running — keep stocking up."
        end,
        ambientMsgs = {
            "Freight costs fell this week, passing savings down to growers.",
            "A new shipment arrived at the depot — prices haven't recovered yet.",
        },
    },

    {
        name="fuel_discount", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.fuelDiscount = 0.1 + 0.05 * intensity
            end
            return string.format("Fuel prices drop! -%.0f%% at the pump today.", (0.1 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Fuel's still cheap — keep those engines running."
        end,
        ambientMsgs = {
            "Crude oil glut on global markets is trickling down to farm diesel.",
            "The local fuel supplier is matching the regional price drop.",
        },
    },

    {
        name="equipment_discount", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.equipmentDiscount = 0.1 + 0.05 * intensity
            end
            return string.format("Dealer clearance sale! Equipment -%.0f%%.", (0.1 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Clearance sale halfway through — still time to upgrade your fleet."
        end,
        ambientMsgs = {
            "The dealership lot is packed with discounted demo models.",
            "End-of-year clearance means serious savings on new iron.",
        },
    },

    {
        name="insurance_bonus", minI=1,
        func=function(intensity)
            local amount = 3000 + intensity * 1000
            if g_currentMission and g_currentMission.addMoney then
                g_currentMission:addMoney(amount, economicEvents.getFarmId(), MoneyType.OTHER, true)
            end
            return string.format("Insurance payout! +€%d deposited.", amount)
        end,
    },

    {
        name="tax_refund", minI=1,
        func=function(intensity)
            local farmMoney = economicEvents.getFarmMoney()
            local refundAmount = math.min(farmMoney * 0.05 * intensity, 10000)
            if refundAmount > 100 and g_currentMission and g_currentMission.addMoney then
                g_currentMission:addMoney(refundAmount, economicEvents.getFarmId(), MoneyType.OTHER, true)
                return string.format("Tax refund processed! +€%d", math.floor(refundAmount))
            end
            return "Small tax adjustment posted — check your account."
        end,
    },

    {
        name="price_fixing", minI=2,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.priceFixing = 0.15 + 0.05 * intensity
                g_RandomWorldEvents.EVENT_STATE.priceFixingDuration = 15 * intensity
            end
            return string.format("Price fixing deal! Guaranteed +%.0f%% on all sales.", (0.15 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Price deal still in force — locking in +%.0f%% margins.", (0.15 + 0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "Buyers' consortium is honouring the fixed-price agreement.",
            "Traders grumble about the ceiling, but your receipts look great.",
        },
    },

    {
        name="loan_interest", minI=1,
        func=function(intensity)
            local farmMoney = economicEvents.getFarmMoney()
            local interest = farmMoney * 0.02 * intensity
            if interest > 100 and g_currentMission and g_currentMission.addMoney then
                g_currentMission:addMoney(-interest, economicEvents.getFarmId(), MoneyType.LOAN_INTEREST, true)
                return string.format("Loan interest due! -€%d withdrawn.", math.floor(interest))
            end
            return "Loan statement arrived — minimal interest charged this period."
        end,
    },

    {
        name="export_opportunity", minI=3,
        func=function(intensity)
            local bonus = 0.25 + 0.05 * intensity
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.exportBonus = bonus
                g_RandomWorldEvents.EVENT_STATE.exportDuration = 30 * intensity
            end
            return string.format("Export window open! +%.0f%% on everything you sell.", bonus * 100)
        end,
        onMid = function(intensity)
            local bonus = 0.25 + 0.05 * intensity
            return string.format("Export opportunity halfway — still +%.0f%% premium. Move that grain!", bonus * 100)
        end,
        ambientMsgs = {
            "Shipping containers are waiting at the port — foreign buyers are bidding up.",
            "The export agent called again — prices are holding strong overseas.",
            "International demand is soaking up everything the region can produce.",
            "Dock workers are running overtime to handle the export surge.",
        },
    },

    {
        name="economic_crisis", minI=4,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.economicCrisis = {
                    marketMalus = 0.2 + 0.1 * intensity,
                    loanPenalty = 0.05 * intensity,
                    duration    = 60 * intensity
                }
            end
            return string.format("ECONOMIC CRISIS! Market -%.0f%%, loan costs +%.0f%%.",
                (0.2 + 0.1 * intensity) * 100,
                (0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Crisis deepening — markets down %.0f%% and no recovery in sight yet.", (0.2 + 0.1 * intensity) * 100)
        end,
        ambientMsgs = {
            "Banks are tightening lending — even sound farms are feeling the squeeze.",
            "Commodity boards issued an emergency warning: expect further price drops.",
            "Neighbours are cutting back. Hard to sell anything at a fair price.",
            "The regional agricultural office confirms widespread financial stress.",
            "Futures markets gapped down again overnight. Brace yourself.",
        },
    },
}

-- =====================
-- TICK HANDLER
-- =====================
local function economicTickHandler(rwe)
    local s = rwe.EVENT_STATE
    if not g_currentMission then return end

    local t = g_currentMission.time
    local lastTick = s.lastEconomicTick or 0
    if t - lastTick < 60000 then return end
    s.lastEconomicTick = t

    local farmId = g_currentMission.player and g_currentMission.player.farmId or 0
    if farmId == 0 then return end

    local amount = 0

    if s.seedDiscount then
        local savings = math.floor(500 * s.seedDiscount)
        amount = amount + savings
    end
    if s.fertilizerDiscount then
        local savings = math.floor(400 * s.fertilizerDiscount)
        amount = amount + savings
    end
    if s.fuelDiscount then
        local savings = math.floor(300 * s.fuelDiscount)
        amount = amount + savings
    end
    if s.equipmentDiscount then
        local savings = math.floor(350 * s.equipmentDiscount)
        amount = amount + savings
    end

    if s.economicCrisis and s.economicCrisis.loanPenalty then
        local penalty = math.floor(1000 * s.economicCrisis.loanPenalty)
        amount = amount - penalty
    end

    if amount ~= 0 and g_currentMission.addMoney then
        g_currentMission:addMoney(amount, farmId, MoneyType.OTHER, false)
    end
end

-- =====================
-- REGISTER ECONOMIC EVENTS
-- =====================
local function registerEconomicEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[EconomicEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(economicEvents.eventList) do
        g_RandomWorldEvents:registerEvent({
            name         = e.name,
            category     = "economic",
            weight       = 1,
            duration     = { min = 15, max = 60 },
            minIntensity = e.minI,
            canTrigger   = function() return g_currentMission ~= nil end,
            onStart      = e.func,
            onMid        = e.onMid,
            ambientMsgs  = e.ambientMsgs,
            onEnd = function()
                if g_RandomWorldEvents then
                    local s = g_RandomWorldEvents.EVENT_STATE
                    s.marketBonus        = nil
                    s.marketMalus        = nil
                    s.seedDiscount       = nil
                    s.fertilizerDiscount = nil
                    s.fuelDiscount       = nil
                    s.equipmentDiscount  = nil
                    s.priceFixing        = nil
                    s.exportBonus        = nil
                    s.economicCrisis     = nil
                    s.lastEconomicTick   = nil
                end
                return nil  -- silent end; the HUD timer expiry is sufficient feedback
            end
        })
    end

    g_RandomWorldEvents:registerTickHandler("economicEvents", economicTickHandler)

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
