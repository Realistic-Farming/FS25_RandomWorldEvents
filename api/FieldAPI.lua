-- =========================================================
-- RWEFieldAPI v2.0.0
-- Public subsystem API for the Field event category.
-- Third-party mods consume this table to register custom
-- field events and query/override per-field yield values.
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
-- =========================================================
--
-- USAGE (third-party mod):
--   if RWEFieldAPI and RWEFieldAPI.registerEvent then
--     RWEFieldAPI:registerEvent({
--       name        = "myMod_soil_enrichment",
--       minIntensity = 1,
--       ambientMsgs = {
--         "The rain has been soaking deep into the topsoil.",
--         "Worms are working overtime — the fields smell earthy and rich.",
--       },
--       func = function(intensity)
--         if g_RandomWorldEvents then
--           g_RandomWorldEvents.EVENT_STATE.yieldBonus = 0.05 * intensity
--         end
--         return "Soil enriched! Yield +" .. intensity * 5 .. "%"
--       end,
--       onMid = function(intensity)
--         return "Soil enrichment is in full effect — crops are responding!"
--       end,
--     })
--   end
-- =========================================================

---@class RWEFieldAPI
RWEFieldAPI = {
    _VERSION          = "2.0.0",
    _CATEGORY         = "field",
    _defaultDuration  = { min = 30, max = 120 },

    _startCallbacks = {},
    _endCallbacks   = {},
    _pendingTicks   = {},
    _tickCounter    = 0,
}

-- Inject shared API surface.
RWEBaseAPI.mixin(RWEFieldAPI)

-- Override the default canTrigger: field events need at least one field on the map.
-- Individual events may still supply their own canTrigger.
RWEFieldAPI._defaultCanTrigger = function()
    if not g_fieldManager then return false end
    local fields = g_fieldManager:getFields()
    return fields ~= nil and #fields > 0
end

-- Patch registerEvent to inject the field-aware canTrigger default.
local baseRegister = RWEFieldAPI.registerEvent
function RWEFieldAPI:registerEvent(def)
    if type(def) == "table" and not def.canTrigger then
        def = setmetatable({ canTrigger = RWEFieldAPI._defaultCanTrigger }, { __index = def })
    end
    return baseRegister(self, def)
end

-- =====================
-- CATEGORY-SPECIFIC: FIELD YIELD QUERY
-- =====================

--- Returns the current yield multiplier applied by active field events.
--- Combines yieldBonus and yieldMalus from EVENT_STATE.
---@return number  net yield multiplier (1.0 = no change)
function RWEFieldAPI:getYieldMultiplier()
    if not g_RandomWorldEvents then return 1.0 end
    local s  = g_RandomWorldEvents.EVENT_STATE
    local m  = 1.0
    if s.yieldBonus  then m = m * (1 + s.yieldBonus)  end
    if s.yieldMalus  then m = m * (1 - s.yieldMalus)  end
    if s.harvestBonus then m = m * (1 + s.harvestBonus) end
    if s.harvestMalus then m = m * (1 - s.harvestMalus) end
    return m
end

-- =====================
-- SELF-REGISTRATION WITH CORE
-- =====================

local function initFieldAPI()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerSubsystem then return false end
    g_RandomWorldEvents:registerSubsystem("field", RWEFieldAPI)
    RWEFieldAPI:_flushPendingTicks()
    Logging.info("[RWEFieldAPI] v" .. RWEFieldAPI._VERSION .. " registered with RWE core")
    return true
end

if not initFieldAPI() then
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, initFieldAPI)
    Logging.info("[RWEFieldAPI] Queued for deferred registration")
end

Logging.info("[RWEFieldAPI] Module loaded (v" .. RWEFieldAPI._VERSION .. ")")
