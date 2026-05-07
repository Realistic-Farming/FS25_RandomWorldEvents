-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- Wildlife / animal events for FS25
-- Category: "wildlife"  (matches self.events.wildlifeEvents setting key)
-- =========================================================
-- BUG FIX: This file previously contained a verbatim copy of
-- specialEvents.lua (Bug #1 in CLAUDE.md). It now contains
-- proper wildlife/livestock events.
-- =========================================================
-- Author: TisonK
-- =========================================================

local animalEvents = {}

-- =====================
-- HELPERS
-- =====================
animalEvents.getFarmId = function()
    return g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 0
end

-- Check that at least one animal husbandry exists on the map.
animalEvents.hasAnimals = function()
    if not g_currentMission then return false end
    -- g_currentMission.husbandries is the standard FS25 collection
    local h = g_currentMission.husbandries
    if h and type(h) == "table" then
        for _ in pairs(h) do return true end
    end
    return false
end

-- =====================
-- WILDLIFE / ANIMAL EVENTS
-- =====================
animalEvents.eventList = {
    {
        name="animal_product_bonus", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.animalProductBonus = 0.10 + 0.05 * intensity
            end
            return string.format("Happy herd! Animal product value up %.0f%%.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return string.format("Animals still thriving — %.0f%% product bonus active.", (0.10 + 0.05 * intensity) * 100)
        end,
        ambientMsgs = {
            "The cows are calm and well-fed. Milk output is ahead of quota.",
            "Buyers at the dairy are complimenting the butterfat content.",
            "Animals pacing the paddock contentedly. A good stretch for the herd.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="animal_product_penalty", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.animalProductMalus = 0.10 + 0.05 * intensity
            end
            return string.format("Stressed herd — animal product value down %.0f%%.", (0.10 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Animals still on edge — product output below normal."
        end,
        ambientMsgs = {
            "Something's unsettling the herd. Hard to say what.",
            "Milk yield is down. The vet checked — no illness, just stress.",
            "Livestock seem restless. Keep an eye on the water and feed.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="wolf_sighting", minI=2,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.animalProductMalus = 0.08 * intensity
            end
            return "Wolf spotted near the boundary! Livestock are on edge."
        end,
        onMid = function(intensity)
            return "Wolf still in the area — animals remain stressed. Guard the paddocks."
        end,
        ambientMsgs = {
            "Howling in the dark again last night. The dogs were barking for hours.",
            "Tracks found at the fence line. The wolf is circling.",
            "Livestock are bunching in the centre of the field — a sure sign of anxiety.",
            "Neighbour lost a sheep last night. Keep your perimeter secure.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="bumper_wool_season", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.animalProductBonus = 0.15 + 0.05 * intensity
                g_RandomWorldEvents.EVENT_STATE.woolBonusSeason    = true
            end
            return string.format("Wool market surge! Animal products up %.0f%%.", (0.15 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Wool premium still in effect — shear while prices last."
        end,
        ambientMsgs = {
            "International textile mills are buying aggressively this season.",
            "Shearing contractor says fleece quality is exceptional this year.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="disease_scare", minI=3,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.animalProductMalus = 0.20 + 0.05 * intensity
                g_RandomWorldEvents.EVENT_STATE.diseaseScare        = true
            end
            return string.format("Disease alert! Animal products down %.0f%% — inspectors are coming.", (0.20 + 0.05 * intensity) * 100)
        end,
        onMid = function(intensity)
            return "Inspectors still on-site — restrictions in force. Products remain penalised."
        end,
        ambientMsgs = {
            "Vet made an unannounced visit. Samples have gone to the lab.",
            "Movement restrictions in the district until the all-clear is given.",
            "Buyers are cautious — they're waiting on the health certificate.",
            "Radio says the outbreak is in the next county, but inspectors aren't taking chances.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="feed_shortage", minI=2,
        func=function(intensity)
            local farmId = animalEvents.getFarmId()
            local penalty = 2000 * intensity
            if g_currentMission and g_currentMission.addMoney and farmId > 0 then
                g_currentMission:addMoney(-penalty, farmId, MoneyType.OTHER, true)
            end
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.animalProductMalus = 0.10 * intensity
            end
            return string.format("Feed shortage! Emergency supplies cost €%d — output down %.0f%%.", penalty, 10 * intensity)
        end,
        onMid = function(intensity)
            return "Feed deliveries are still disrupted. Keep rationing carefully."
        end,
        ambientMsgs = {
            "The grain merchant is apologising — logistics issues on their end.",
            "Animals are getting by, but they're not at full production weight.",
            "A neighbouring farm offered to share silage. Grateful, but costly.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="veterinary_windfall", minI=1,
        func=function(intensity)
            local farmId = animalEvents.getFarmId()
            local amount = 1500 + intensity * 1000
            if g_currentMission and g_currentMission.addMoney and farmId > 0 then
                g_currentMission:addMoney(amount, farmId, MoneyType.OTHER, true)
            end
            return string.format("Animal welfare subsidy paid out! +€%d from the scheme.", amount)
        end,
        ambientMsgs = {
            "Government inspector gave you a clean bill of health — scheme payment incoming.",
        },
        canTrigger = animalEvents.hasAnimals,
    },

    {
        name="wildlife_pest_invasion", minI=1,
        func=function(intensity)
            if g_RandomWorldEvents then
                g_RandomWorldEvents.EVENT_STATE.yieldMalus = 0.05 * intensity
            end
            return string.format("Pest invasion! Rabbits and deer cutting field yields by %.0f%%.", 5 * intensity)
        end,
        onMid = function(intensity)
            return "Pests still active — traps and fencing crews are working on it."
        end,
        ambientMsgs = {
            "Rabbit warrens multiplying at the field edge. Crops are taking a hit.",
            "Deer tracks through the young crop again this morning.",
            "Pest control van on the road. They said it'll take a few days.",
        },
        -- No hasAnimals requirement — affects fields, not livestock.
    },
}

-- =====================
-- TICK HANDLER
-- Delivers per-minute cash effects for active animal bonuses/maluses.
-- =====================
local function animalTickHandler(rwe)
    if not g_currentMission then return end
    local s = rwe.EVENT_STATE
    local t = g_currentMission.time
    local lastTick = s.lastAnimalTick or 0
    if t - lastTick < 60000 then return end
    s.lastAnimalTick = t

    local farmId = g_currentMission.player and g_currentMission.player.farmId or 0
    if farmId == 0 then return end

    local amount = 0
    if s.animalProductBonus then
        amount = amount + math.floor(400 * s.animalProductBonus)
    end
    if s.animalProductMalus then
        amount = amount - math.floor(300 * s.animalProductMalus)
    end

    if amount ~= 0 and g_currentMission.addMoney then
        g_currentMission:addMoney(amount, farmId, MoneyType.OTHER, false)
    end
end

-- =====================
-- REGISTER ANIMAL EVENTS
-- =====================
local function registerAnimalEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[AnimalEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(animalEvents.eventList) do
        g_RandomWorldEvents:registerEvent({
            name         = e.name,
            category     = "wildlife",
            weight       = 1,
            duration     = { min = 15, max = 60 },
            minIntensity = e.minI or 1,
            canTrigger   = e.canTrigger or function() return g_currentMission ~= nil end,
            onStart      = e.func,
            onMid        = e.onMid,
            ambientMsgs  = e.ambientMsgs,
            onEnd = function()
                if g_RandomWorldEvents then
                    local s = g_RandomWorldEvents.EVENT_STATE
                    s.animalProductBonus = nil
                    s.animalProductMalus = nil
                    s.woolBonusSeason    = nil
                    s.diseaseScare       = nil
                    s.yieldMalus         = s.yieldMalus  -- only clear if this event set it
                    s.lastAnimalTick     = nil
                end
                return nil
            end
        })
    end

    g_RandomWorldEvents:registerTickHandler("animalEvents", animalTickHandler)

    Logging.info("[AnimalEvents] Registered " .. #animalEvents.eventList .. " wildlife/animal events")
    return true
end

-- =====================
-- DELAYED REGISTRATION
-- =====================
if g_RandomWorldEvents and g_RandomWorldEvents.registerEvent then
    registerAnimalEvents()
else
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, registerAnimalEvents)
    Logging.info("[AnimalEvents] Added to pending registrations")
end

Logging.info("[AnimalEvents] Module loaded successfully")
