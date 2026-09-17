-- =========================================================
-- Random World Events - FS25
-- =========================================================
-- Wildlife / animal events for FS25
-- Category: "wildlife"  (matches self.events.wildlifeEvents setting key)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- EC-6 (brief v1.7 sections 3.3, 3.8 and 3.9.1):
--   * The herd and pest events are PULL read-signals: RandomWorldEvents sets the
--     EVENT_STATE flags and the herd, disease and field systems decide what they
--     mean. Their notices describe conditions and name no product or yield figure.
--   * The five herd signals need an animal anywhere on the map (mapHasAnimals), which
--     reads no local player and no farm list. wildlife_pest_invasion needs none.
--   * feed_shortage and veterinary_windfall queue one statement line per farm that
--     owns animals (farmHasAnimals), settled at the next in-game day
--     (utils/RWESettlement.lua). Their shared notices never name a euro amount.
-- =========================================================

local animalEvents = {}

-- =====================
-- HELPERS
-- =====================

--- Any husbandry on the map, whatever its owner, has at least one animal.
function animalEvents.mapHasAnimals()
    return RWESettlement ~= nil and RWESettlement.mapHasAnimals()
end

--- A husbandry owned by this farm has at least one animal.
function animalEvents.farmHasAnimals(farmId)
    return RWESettlement ~= nil and RWESettlement.farmHasAnimals(farmId)
end

local function key(name, part) return "rwe_event_" .. name .. "_" .. part end
local function title(name) return "rwe_event_" .. name .. "_title" end

local function setFlag(field, value)
    if g_RandomWorldEvents then g_RandomWorldEvents.EVENT_STATE[field] = value end
end

local function ambients(name, count)
    local out = {}
    for n = 1, count do out[n] = key(name, "ambient" .. n) end
    return out
end

local function anyFarmWithAnimals()
    return RWESettlement ~= nil and RWESettlement.anyFarm(function(farm) return animalEvents.farmHasAnimals(farm.farmId) end)
end

--- A herd or field condition signal with no money line.
local function signal(name, minI, flags, ambientCount, canTrigger)
    local e = {
        name = name, minI = minI,
        summaryKey = "rwe_summary_" .. name,
        applyFlags = flags,
        canTrigger = canTrigger,
        onMid = function(intensity) return { key = key(name, "mid") } end,
        ambientMsgs = ambients(name, ambientCount),
    }
    e.func = function(intensity)
        e.applyFlags(intensity)
        return { key = key(name, "start") }
    end
    return e
end

-- =====================
-- WILDLIFE / ANIMAL EVENTS
-- =====================
animalEvents.eventList = {
    signal("animal_product_bonus", 1,
        function(i) setFlag("animalProductBonus", 0.10 + 0.05 * i) end, 3, animalEvents.mapHasAnimals),

    signal("animal_product_penalty", 1,
        function(i) setFlag("animalProductMalus", 0.10 + 0.05 * i) end, 3, animalEvents.mapHasAnimals),

    signal("wolf_sighting", 2,
        function(i) setFlag("animalProductMalus", 0.08 * i) end, 4, animalEvents.mapHasAnimals),

    signal("bumper_wool_season", 1,
        function(i)
            setFlag("animalProductBonus", 0.15 + 0.05 * i)
            setFlag("woolBonusSeason", true)
        end, 2, animalEvents.mapHasAnimals),

    signal("disease_scare", 3,
        function(i)
            setFlag("animalProductMalus", 0.20 + 0.05 * i)
            setFlag("diseaseScare", true)
        end, 4, animalEvents.mapHasAnimals),

    {
        name = "feed_shortage", minI = 2,
        summaryKey = "rwe_summary_money_animals_debit",
        canTrigger = anyFarmWithAnimals,
        applyFlags = function(intensity) setFlag("animalProductMalus", 0.10 * intensity) end,
        func = function(intensity)
            animalEvents.byName.feed_shortage.applyFlags(intensity)
            if RWESettlement ~= nil then
                RWESettlement.queueForFarms("feed_shortage", "OTHER", title("feed_shortage"), function(farm)
                    if not animalEvents.farmHasAnimals(farm.farmId) then return nil end
                    return -(2000 * intensity)
                end)
            end
            return { key = key("feed_shortage", "start") }
        end,
        onMid = function(intensity) return { key = key("feed_shortage", "mid") } end,
        ambientMsgs = ambients("feed_shortage", 3),
    },

    {
        name = "veterinary_windfall", minI = 1,
        summaryKey = "rwe_summary_money_animals_credit",
        canTrigger = anyFarmWithAnimals,
        func = function(intensity)
            if RWESettlement ~= nil then
                RWESettlement.queueForFarms("veterinary_windfall", "OTHER", title("veterinary_windfall"), function(farm)
                    if not animalEvents.farmHasAnimals(farm.farmId) then return nil end
                    return 1500 + 1000 * intensity
                end)
            end
            return { key = key("veterinary_windfall", "start") }
        end,
        ambientMsgs = ambients("veterinary_windfall", 1),
    },

    -- No husbandry requirement: pests affect fields, not livestock.
    signal("wildlife_pest_invasion", 1,
        function(i) setFlag("yieldMalus", 0.05 * i) end, 3, nil),
}

animalEvents.byName = {}
for _, e in ipairs(animalEvents.eventList) do animalEvents.byName[e.name] = e end

-- =====================
-- REGISTER ANIMAL EVENTS
-- =====================
local function registerAnimalEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[AnimalEvents] g_RandomWorldEvents not available yet")
        return false
    end

    for _, e in ipairs(animalEvents.eventList) do
        local def = e
        g_RandomWorldEvents:registerEvent({
            name            = def.name,
            category        = "wildlife",
            weight          = 1,
            duration        = { min = 15, max = 60 },
            minIntensity    = def.minI or 1,
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
                    s.animalProductBonus = nil
                    s.animalProductMalus = nil
                    s.woolBonusSeason    = nil
                    s.diseaseScare       = nil
                    s.yieldMalus         = 0
                end
                return nil
            end
        })
    end

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
