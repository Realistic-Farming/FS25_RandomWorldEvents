-- =========================================================
-- RWESpecialAPI v2.0.0
-- Public subsystem API for the Special event category.
-- Third-party mods consume this table to register custom
-- special events with optional condition guards.
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
-- =========================================================
--
-- USAGE (third-party mod):
--   if RWESpecialAPI and RWESpecialAPI.registerSpecialTrigger then
--     RWESpecialAPI:registerSpecialTrigger(
--       "myMod_harvest_moon",
--       function()  -- condition: only trigger at night
--         return g_currentMission and
--                g_currentMission.environment and
--                not g_currentMission.environment.isSunOn
--       end,
--       function(intensity)
--         if g_RandomWorldEvents then
--           g_RandomWorldEvents.EVENT_STATE.yieldBonus = 0.08 * intensity
--         end
--         return string.format("Harvest moon! Yields +%.0f%%", intensity * 8)
--       end,
--       {
--         onMid = function() return "The moon hangs full overhead — keep harvesting!" end,
--         ambientMsgs = { "The night is bright as day under the harvest moon." },
--       }
--     )
--   end
-- =========================================================

---@class RWESpecialAPI
RWESpecialAPI = {
    _VERSION          = "2.0.0",
    _CATEGORY         = "special",
    _defaultDuration  = { min = 10, max = 60 },

    _startCallbacks = {},
    _endCallbacks   = {},
    _pendingTicks   = {},
    _tickCounter    = 0,
}

-- Inject shared API surface.
RWEBaseAPI.mixin(RWESpecialAPI)

-- =====================
-- CATEGORY-SPECIFIC: CONDITION-GATED TRIGGER
-- =====================

--- Register a special event that only enters the trigger pool when `condition` returns true.
--- This is the canonical way for third-party mods to add situation-specific special events
--- (e.g. only during night, only in winter, only when money is below a threshold).
---
---   name      (string)   unique event identifier
---   condition (function) → boolean; called by canTrigger each tick
---   func      (function(intensity)) → string|nil; onStart handler
---   opts      (table?)   optional overrides: {minIntensity, duration, weight, onEnd,
---                                              onMid, ambientMsgs}
---@param name      string
---@param condition function → boolean
---@param func      function(intensity) → string|nil
---@param opts      table|nil
---@return boolean
function RWESpecialAPI:registerSpecialTrigger(name, condition, func, opts)
    if type(name) ~= "string" then
        Logging.warning("[RWESpecialAPI] registerSpecialTrigger: name must be a string")
        return false
    end
    if type(condition) ~= "function" then
        Logging.warning("[RWESpecialAPI] registerSpecialTrigger: condition must be a function")
        return false
    end
    if type(func) ~= "function" then
        Logging.warning("[RWESpecialAPI] registerSpecialTrigger: func must be a function")
        return false
    end

    opts = opts or {}

    return self:registerEvent({
        name         = name,
        func         = func,
        minIntensity = opts.minIntensity or 1,
        weight       = opts.weight or 1,
        duration     = opts.duration,
        onEnd        = opts.onEnd,
        onMid        = opts.onMid,
        ambientMsgs  = opts.ambientMsgs,
        canTrigger   = function()
            if not g_currentMission then return false end
            local ok, result = pcall(condition)
            return ok and result == true
        end,
    })
end

-- =====================
-- SELF-REGISTRATION WITH CORE
-- =====================

local function initSpecialAPI()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerSubsystem then return false end
    g_RandomWorldEvents:registerSubsystem("special", RWESpecialAPI)
    RWESpecialAPI:_flushPendingTicks()
    Logging.info("[RWESpecialAPI] v" .. RWESpecialAPI._VERSION .. " registered with RWE core")
    return true
end

if not initSpecialAPI() then
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then RandomWorldEvents.pendingRegistrations = {} end
    table.insert(RandomWorldEvents.pendingRegistrations, initSpecialAPI)
    Logging.info("[RWESpecialAPI] Queued for deferred registration")
end

Logging.info("[RWESpecialAPI] Module loaded (v" .. RWESpecialAPI._VERSION .. ")")
