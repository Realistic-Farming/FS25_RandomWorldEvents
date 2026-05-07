-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- Special events for FS25
-- =========================================================
-- Author: TisonK
-- =========================================================

local specialEvents = {}

specialEvents.eventList = {
    {
        name="time_acceleration", minI=1,
        func=function(intensity)
            if not g_RandomWorldEvents then return "Time is moving faster!" end
            if not g_RandomWorldEvents.EVENT_STATE.originalTimeScale then
                g_RandomWorldEvents.EVENT_STATE.originalTimeScale = g_currentMission.missionInfo.timeScale
            end
            g_currentMission.missionInfo.timeScale = g_RandomWorldEvents.EVENT_STATE.originalTimeScale * (5 * intensity)
            return string.format("Time warp! The clock is running %.0fx faster.", 5 * intensity)
        end,
        onMid = function(intensity)
            return string.format("Still in fast-forward — time running at %.0fx. Plan ahead.", 5 * intensity)
        end,
        ambientMsgs = {
            "The hours are blurring together. Sunrises come fast.",
            "Day and night are cycling like a strobe. Get as much done as you can.",
        },
    },

    {
        name="time_slowdown", minI=1,
        func=function(intensity)
            if not g_RandomWorldEvents then return "Time is slowing down!" end
            if not g_RandomWorldEvents.EVENT_STATE.originalTimeScale then
                g_RandomWorldEvents.EVENT_STATE.originalTimeScale = g_currentMission.missionInfo.timeScale
            end
            g_currentMission.missionInfo.timeScale = g_RandomWorldEvents.EVENT_STATE.originalTimeScale / (2 * intensity)
            return string.format("Time dilation! Every hour feels like %.0f.", 2 * intensity)
        end,
        onMid = function(intensity)
            return "Time is still crawling. Plenty of hours left — make them count."
        end,
        ambientMsgs = {
            "The sun seems to hang in the sky for ages today.",
            "You can hear every insect in the field. Time feels stretched.",
        },
    },

    {
        name="bonus_xp", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.xpBonus = 0.1 * intensity
            end
            return string.format("Reputation surge! +%.0f%% rep gain.", (0.1 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Still earning reputation faster — +%.0f%% ongoing.", (0.1 * intensity) * 100)
        end,
        ambientMsgs = {
            "Word's getting around about your operation. People are impressed.",
            "The local paper mentioned your farm. Good publicity.",
        },
    },

    {
        name="malus_xp", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.xpMalus = 0.1 * intensity
            end
            return string.format("Reputation dip! -%.0f%% rep gain for a while.", (0.1 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Reputation still recovering — keep your head down and work hard."
        end,
        ambientMsgs = {
            "Someone complained to the co-op. Best keep a low profile.",
            "A dispute with a neighbour is doing the rounds in town.",
        },
    },

    {
        name="money_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.moneyBonus = 0.1 * intensity
            end
            return string.format("Cash flowing! +€%d extra income per minute.", math.floor(500 * 0.1 * intensity))
        end,
        onMid = function(intensity)
            return string.format("Income boost still active — +€%d/min trickling in.", math.floor(500 * 0.1 * intensity))
        end,
        ambientMsgs = {
            "The farm account is ticking upward. A good stretch.",
            "Contracts and side deals are paying out today.",
        },
    },

    {
        name="money_malus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.moneyMalus = 0.1 * intensity
            end
            return string.format("Unexpected costs! -€%d per minute for a while.", math.floor(400 * 0.1 * intensity))
        end,
        onMid = function(intensity)
            return string.format("Costs still bleeding — -€%d/min. Sit tight.", math.floor(400 * 0.1 * intensity))
        end,
        ambientMsgs = {
            "Administration fees, permit renewals... it adds up fast.",
            "The accountant flagged a few unexpected charges this period.",
        },
    },

    {
        name="special_event_festival", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.marketBonus = 0.05 + 0.03 * intensity
                g_RandomWorldEvents.EVENT_STATE.moneyBonus  = 0.10 + 0.05 * intensity
            end
            return string.format("Harvest festival! Prices +%.0f%%, income +€%d/min!",
                (0.05 + 0.03 * intensity) * 100,
                math.floor(500 * (0.10 + 0.05 * intensity))
            )
        end,
        onMid = function(intensity)
            return "Festival is in full swing — stalls everywhere, buyers in a generous mood."
        end,
        ambientMsgs = {
            "Music drifting over the fields from the fairground. Good atmosphere.",
            "Visitors from the city are buying direct — premium prices.",
            "The town square is packed. The farm stand is doing brisk trade.",
            "Beer tent's full, the square smells of fried food. Classic harvest time.",
        },
    },

    {
        name="equipment_durability_boost", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.durabilityBoost = 0.15 + 0.05 * intensity
            end
            return string.format("Everything running sweet! Wear rate down %.0f%%.", (0.15 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Machines still holding up brilliantly — low wear ongoing."
        end,
        ambientMsgs = {
            "Conditions are kind on the equipment today. No unusual wear.",
            "Filters are clean, fluids look good — the fleet is in fine shape.",
        },
    },

    {
        name="equipment_durability_drop", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.durabilityMalus = 0.15 + 0.05 * intensity
            end
            return string.format("Rough patch! Equipment wear rate up %.0f%%.", (0.15 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Wear still elevated — %.0f%% above normal. Keep an eye on the machines.", (0.15 + 0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "Abrasive soil or grit in the air — everything is wearing faster.",
            "The stone content in this field is punishing. Watch the blades.",
            "Hydraulic temps running a bit high. Not critical, but keep an eye on it.",
        },
    },

    {
        name="bonus_trade_prices", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.tradeBonus = 0.10 + 0.05 * intensity
            end
            return string.format("Trade premium! +%.0f%% on all sales right now.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Premium prices holding — %.0f%% above board rate.", (0.10 + 0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "Every sell point is offering above the daily average today.",
            "Regional shortage has nudged every category upward. Sell what you can.",
        },
    },
}

-- =====================
-- TICK HANDLER
-- =====================
local function specialTickHandler(rwe)
    if not g_currentMission then return end
    local s = rwe.EVENT_STATE
    local t = g_currentMission.time
    local lastTick = s.lastSpecialTick or 0
    if t - lastTick < 60000 then return end
    s.lastSpecialTick = t

    local farmId = g_currentMission.player and g_currentMission.player.farmId or 0
    if farmId == 0 then return end

    local amount = 0
    if s.moneyBonus then amount = amount + math.floor(500 * s.moneyBonus) end
    if s.moneyMalus then amount = amount - math.floor(400 * s.moneyMalus) end

    if amount ~= 0 and g_currentMission.addMoney then
        g_currentMission:addMoney(amount, farmId, MoneyType.OTHER, false)
    end

    if (s.xpBonus or s.xpMalus) and g_farmManager then
        local farm = g_farmManager:getFarmById(farmId)
        if farm and farm.repPoints ~= nil then
            if s.xpBonus then
                farm.repPoints = farm.repPoints + math.floor(10 * s.xpBonus)
            end
            if s.xpMalus then
                farm.repPoints = math.max(0, farm.repPoints - math.floor(8 * s.xpMalus))
            end
        end
    end
end

-- =====================
-- REGISTER SPECIAL EVENTS
-- =====================
local function registerSpecialEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[SpecialEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(specialEvents.eventList) do
        g_RandomWorldEvents:registerEvent({
            name         = e.name,
            category     = "special",
            weight       = 1,
            duration     = { min = 10, max = 60 },
            minIntensity = e.minI,
            canTrigger   = function() return g_currentMission ~= nil end,
            onStart      = e.func,
            onMid        = e.onMid,
            ambientMsgs  = e.ambientMsgs,
            onEnd = function()
                if g_RandomWorldEvents then
                    local s = g_RandomWorldEvents.EVENT_STATE
                    if s.originalTimeScale then
                        g_currentMission.missionInfo.timeScale = s.originalTimeScale
                        s.originalTimeScale = nil
                    end
                    s.xpBonus         = nil
                    s.xpMalus         = nil
                    s.moneyBonus      = nil
                    s.moneyMalus      = nil
                    s.durabilityBoost = nil
                    s.durabilityMalus = nil
                    s.tradeBonus      = nil
                    s.marketBonus     = nil
                    s.lastSpecialTick = nil
                end
                return nil
            end
        })
    end

    g_RandomWorldEvents:registerTickHandler("specialEvents", specialTickHandler)

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
