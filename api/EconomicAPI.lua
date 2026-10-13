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
--       name        = "myMod_corn_demand",
--       minIntensity = 1,
--       func        = function(intensity)
--         -- Server only; moves the corn selling price at the next market update
--         -- while this event runs (needs MarketDynamics).
--         RWEEconomicAPI:setPriceModifier("MAIZE", 1.10)
--         return "Corn buyers are busy: selling prices rise at the next market update."
--       end,
--     })
--   end
-- EC-6: RandomWorldEvents never writes money directly; money events post statement
-- lines at the next in-game day through RandomWorldEvents' own settlement.
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

--- Resolve a crop key to a fill type index: a numeric index is accepted when the
--- fill type manager knows it, a string is converted by name. Anything else is nil.
local function fillTypeIndexOf(cropType)
    if type(cropType) == "number" then
        if g_fillTypeManager ~= nil and type(g_fillTypeManager.getFillTypeByIndex) == "function"
           and g_fillTypeManager:getFillTypeByIndex(cropType) == nil then
            return nil
        end
        return cropType
    end
    if type(cropType) == "string" and g_fillTypeManager ~= nil and type(g_fillTypeManager.getFillTypeIndexByName) == "function" then
        return g_fillTypeManager:getFillTypeIndexByName(cropType)
    end
    return nil
end

--- Set a custom sell-price multiplier for one fill type while the current event runs
--- (third-party hook). EC-6: server only; the key is a fill type index, or a name
--- converted to one; anything else is refused. The entry is read by RandomWorldEvents'
--- registered MarketDynamics modifier, so it moves selling-point prices at the next
--- market update and only where MarketDynamics prices are available. It lives only
--- for the event that is active when it is set: the activation reset and the shared
--- end path both clear the table, so a custom term never outlives its event. With no
--- active event it is refused. Entries are not saved.
---@param cropType any   fill type index or name
---@param multiplier number  price scale factor (e.g. 1.20 = +20%), must be > 0
---@param durationMin number|nil  in-game minutes; nil = until the event ends
---@return boolean set
function RWEEconomicAPI:setPriceModifier(cropType, multiplier, durationMin)
    if not g_RandomWorldEvents then
        Logging.warning("[RWEEconomicAPI] setPriceModifier: core not available")
        return false
    end
    if g_server == nil then
        Logging.warning("[RWEEconomicAPI] setPriceModifier: server only, ignored on a client")
        return false
    end
    local state = g_RandomWorldEvents.EVENT_STATE
    if state.activeEvent == nil then
        Logging.warning("[RWEEconomicAPI] setPriceModifier: no active event, ignored (a custom term lives only for the event it is set during)")
        return false
    end
    local index = fillTypeIndexOf(cropType)
    if index == nil then
        Logging.warning("[RWEEconomicAPI] setPriceModifier: unknown fill type '%s', ignored", tostring(cropType))
        return false
    end
    if type(multiplier) ~= "number" or multiplier ~= multiplier or multiplier <= 0 or multiplier == math.huge then
        Logging.warning("[RWEEconomicAPI] setPriceModifier: multiplier must be a finite number above 0, ignored")
        return false
    end

    if not state.customPriceModifiers then
        state.customPriceModifiers = {}
    end

    local expiresAt = nil
    if durationMin and g_currentMission then
        expiresAt = g_currentMission.time + (durationMin * 60000)
    end

    state.customPriceModifiers[index] = { multiplier = multiplier, expiresAt = expiresAt }

    Logging.info(string.format(
        "[RWEEconomicAPI] Price modifier set: fillType=%s multiplier=%.2f duration=%s min",
        tostring(index), multiplier, tostring(durationMin)
    ))
    return true
end

--- Retrieve the active price modifier for a fill type (index or name), or nil if none/expired.
---@param cropType any
---@return number|nil
function RWEEconomicAPI:getPriceModifier(cropType)
    if not g_RandomWorldEvents then return nil end
    local mods = g_RandomWorldEvents.EVENT_STATE.customPriceModifiers
    local index = fillTypeIndexOf(cropType)
    if not mods or index == nil or not mods[index] then return nil end
    local mod = mods[index]
    if mod.expiresAt and g_currentMission and g_currentMission.time > mod.expiresAt then
        mods[index] = nil
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
