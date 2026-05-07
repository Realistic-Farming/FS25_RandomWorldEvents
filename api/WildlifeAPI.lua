-- =========================================================
-- RWEWildlifeAPI v2.0.0
-- Public subsystem API for the Wildlife event category.
-- Third-party mods consume this table to register custom
-- livestock/wildlife events and observe category activity.
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
-- =========================================================
--
-- USAGE (third-party mod):
--   if RWEWildlifeAPI and RWEWildlifeAPI.registerAnimalEffect then
--     RWEWildlifeAPI:registerAnimalEffect(
--       "myMod_wolf_sighting",
--       function(intensity)
--         if g_RandomWorldEvents then
--           g_RandomWorldEvents.EVENT_STATE.animalProductMalus = 0.08 * intensity
--         end
--         return "Wolf spotted near the farm! Livestock stressed."
--       end,
--       function()  -- onEnd (optional)
--         if g_RandomWorldEvents then
--           g_RandomWorldEvents.EVENT_STATE.animalProductMalus = nil
--         end
--       end,
--       {
--         ambientMsgs = {
--           "Your animals are unsettled — something is watching from the tree line.",
--           "Howling carried on the wind again last night.",
--         },
--         onMid = function() return "The wolf hasn't left — stress levels remain high." end,
--       }
--     )
--   end
-- =========================================================

---@class RWEWildlifeAPI
RWEWildlifeAPI = {
    _VERSION          = "2.0.0",
    _CATEGORY         = "wildlife",
    _defaultDuration  = { min = 15, max = 60 },

    _startCallbacks = {},
    _endCallbacks   = {},
    _pendingTicks   = {},
    _tickCounter    = 0,
}

-- Inject shared API surface.
RWEBaseAPI.mixin(RWEWildlifeAPI)

-- =====================
-- CATEGORY-SPECIFIC: CONVENIENCE WRAPPER
-- =====================

--- Convenience wrapper: register a wildlife/animal event with a simpler call signature.
--- Equivalent to registerEvent but surfaced with clear parameter names.
---
---   name    (string)           unique event identifier
---   onStart (function(intensity) → string|nil)
---   onEnd   (function() → nil)  optional cleanup handler
---   opts    (table?)            optional: {minIntensity, duration, weight, canTrigger,
---                                          onMid, ambientMsgs}
---@param name    string
---@param onStart function(intensity) → string|nil
---@param onEnd   function|nil
---@param opts    table|nil
---@return boolean
function RWEWildlifeAPI:registerAnimalEffect(name, onStart, onEnd, opts)
    if type(name) ~= "string" or type(onStart) ~= "function" then
        Logging.warning("[RWEWildlifeAPI] registerAnimalEffect: name (string) and onStart (function) are required")
        return false
    end

    opts = opts or {}

    return self:registerEvent({
        name         = name,
        func         = onStart,
        onEnd        = onEnd,
        minIntensity = opts.minIntensity or 1,
        weight       = opts.weight or 1,
        duration     = opts.duration,
        canTrigger   = opts.canTrigger,
        onMid        = opts.onMid,
        ambientMsgs  = opts.ambientMsgs,
    })
end

--- Returns the current animal product multiplier from active wildlife events.
--- Combines animalProductBonus and animalProductMalus from EVENT_STATE.
---@return number  net multiplier (1.0 = no change)
function RWEWildlifeAPI:getAnimalProductMultiplier()
    if not g_RandomWorldEvents then return 1.0 end
    local s = g_RandomWorldEvents.EVENT_STATE
    local m = 1.0
    if s.animalProductBonus then m = m * (1 + s.animalProductBonus) end
    if s.animalProductMalus then m = m * (1 - s.animalProductMalus) end
    return m
end

-- =====================
-- SELF-REGISTRATION WITH CORE
-- =====================

local function initWildlifeAPI()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerSubsystem then return false end
    g_RandomWorldEvents:registerSubsystem("wildlife", RWEWildlifeAPI)
    RWEWildlifeAPI:_flushPendingTicks()
    Logging.info("[RWEWildlifeAPI] v" .. RWEWildlifeAPI._VERSION .. " registered with RWE core")
    return true
end

if not initWildlifeAPI() then
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, initWildlifeAPI)
    Logging.info("[RWEWildlifeAPI] Queued for deferred registration")
end

Logging.info("[RWEWildlifeAPI] Module loaded (v" .. RWEWildlifeAPI._VERSION .. ")")
