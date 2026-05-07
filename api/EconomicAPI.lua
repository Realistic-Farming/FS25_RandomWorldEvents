-- =========================================================
-- RWEEconomicAPI v2.0.0
-- Public subsystem API for the Economic event category.
-- Third-party mods consume this table to register custom
-- economic events and observe category activity.
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
-- =========================================================
--
-- USAGE (third-party mod):
--   if RWEEconomicAPI and RWEEconomicAPI.registerEvent then
--     RWEEconomicAPI:registerEvent({
--       name        = "myMod_corn_subsidy",
--       minIntensity = 1,
--       ambientMsgs = {
--         "Grain buyers are flooding the market!",
--         "Export terminals are overwhelmed with orders.",
--       },
--       func        = function(intensity)
--         g_currentMission:addMoney(intensity * 1000, ...)
--         return "Corn subsidy! +" .. intensity * 1000 .. "€"
--       end,
--       onMid = function(intensity)
--         return "Subsidies are peaking — sell now!"
--       end,
--     })
--   end
-- =========================================================

---@class RWEEconomicAPI
RWEEconomicAPI = {
    _VERSION          = "2.0.0",
    _CATEGORY         = "economic",
    _defaultDuration  = { min = 15, max = 60 },

    _startCallbacks = {},
    _endCallbacks   = {},
    _pendingTicks   = {},
    _tickCounter    = 0,
}

-- Inject shared API surface.
RWEBaseAPI.mixin(RWEEconomicAPI)

-- Category-specific cleanup called from mixin's onEnd wrapper.
function RWEEconomicAPI._onEndCleanup(api)
    api:clearPriceModifiers()
end

-- =====================
-- CATEGORY-SPECIFIC: PRICE MODIFIER
-- =====================

--- Set a custom crop price multiplier for a duration (third-party hook).
--- Pass nil for durationMin to apply indefinitely until the active event ends.
---@param cropType any   FillType constant or string key
---@param multiplier number  price scale factor (e.g. 1.20 = +20%)
---@param durationMin number|nil  duration in in-game minutes; nil = until event ends
function RWEEconomicAPI:setPriceModifier(cropType, multiplier, durationMin)
    if not g_RandomWorldEvents then
        Logging.warning("[RWEEconomicAPI] setPriceModifier: core not available")
        return
    end

    local state = g_RandomWorldEvents.EVENT_STATE
    if not state.customPriceModifiers then
        state.customPriceModifiers = {}
    end

    local expiresAt = nil
    if durationMin and g_currentMission then
        expiresAt = g_currentMission.time + (durationMin * 60000)
    end

    state.customPriceModifiers[cropType] = { multiplier = multiplier, expiresAt = expiresAt }

    Logging.info(string.format(
        "[RWEEconomicAPI] Price modifier set: crop=%s multiplier=%.2f duration=%s min",
        tostring(cropType), multiplier, tostring(durationMin)
    ))
end

--- Retrieve the active price modifier for a given crop type, or nil if none/expired.
---@param cropType any
---@return number|nil
function RWEEconomicAPI:getPriceModifier(cropType)
    if not g_RandomWorldEvents then return nil end
    local mods = g_RandomWorldEvents.EVENT_STATE.customPriceModifiers
    if not mods or not mods[cropType] then return nil end
    local mod = mods[cropType]
    if mod.expiresAt and g_currentMission and g_currentMission.time > mod.expiresAt then
        mods[cropType] = nil
        return nil
    end
    return mod.multiplier
end

--- Clear all custom price modifiers (called automatically on event end).
function RWEEconomicAPI:clearPriceModifiers()
    if not g_RandomWorldEvents then return end
    g_RandomWorldEvents.EVENT_STATE.customPriceModifiers = nil
end

-- =====================
-- SELF-REGISTRATION WITH CORE
-- =====================

local function initEconomicAPI()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerSubsystem then return false end
    g_RandomWorldEvents:registerSubsystem("economic", RWEEconomicAPI)
    RWEEconomicAPI:_flushPendingTicks()
    Logging.info("[RWEEconomicAPI] v" .. RWEEconomicAPI._VERSION .. " registered with RWE core")
    return true
end

if not initEconomicAPI() then
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, initEconomicAPI)
    Logging.info("[RWEEconomicAPI] Queued for deferred registration")
end

Logging.info("[RWEEconomicAPI] Module loaded (v" .. RWEEconomicAPI._VERSION .. ")")
