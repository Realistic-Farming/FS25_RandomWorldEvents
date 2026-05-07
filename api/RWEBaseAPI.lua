-- =========================================================
-- RWEBaseAPI v1.0.0
-- Shared mixin for all RWE subsystem APIs.
--
-- Provides the common surface that every category API repeats:
--   registerEvent, triggerEvent, isEventActive, getActiveEvent,
--   getProgress, getRemainingTime, onEventStart, onEventEnd,
--   registerTickHandler, getVersion.
--
-- Usage — call this in each API table at load time:
--   RWEBaseAPI.mixin(RWEMyAPI)
--
-- The calling table MUST already have:
--   _VERSION    (string)
--   _CATEGORY   (string)
--   _startCallbacks, _endCallbacks, _pendingTicks, _tickCounter
--
-- Category-specific helpers (e.g. setPriceModifier) remain in
-- the per-category file and are not touched here.
-- =========================================================
-- Author: TisonK  |  Part of FS25_RandomWorldEvents
-- =========================================================

---@class RWEBaseAPI
RWEBaseAPI = {}

--- Inject all shared methods into a category API table.
---@param target table  The category API table (e.g. RWEEconomicAPI)
function RWEBaseAPI.mixin(target)
    assert(type(target) == "table", "RWEBaseAPI.mixin: target must be a table")
    assert(type(target._CATEGORY) == "string", "RWEBaseAPI.mixin: target._CATEGORY must be a string")

    -- =====================
    -- REGISTRATION
    -- =====================

    --- Register a new event in this category.
    --- @param def table  Event definition (name, func required; see DEVELOPMENT.md)
    --- @return boolean
    function target:registerEvent(def)
        if type(def) ~= "table" then
            Logging.warning("[RWE" .. self._CATEGORY .. "API] registerEvent: def must be a table")
            return false
        end
        if not def.name or not def.func then
            Logging.warning("[RWE" .. self._CATEGORY .. "API] registerEvent: def.name and def.func are required")
            return false
        end
        if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
            Logging.warning("[RWE" .. self._CATEGORY .. "API] registerEvent: core not ready for '"
                .. tostring(def.name) .. "'. Call from onMissionLoaded, not at file scope.")
            return false
        end

        local api      = self
        local userFunc = def.func
        local userEnd  = def.onEnd
        local userMid  = def.onMid  -- optional midpoint narrative

        local coreDef = {
            name         = def.name,
            category     = self._CATEGORY,
            weight       = def.weight or 1,
            duration     = def.duration or self._defaultDuration or { min = 15, max = 60 },
            minIntensity = def.minIntensity or 1,
            canTrigger   = def.canTrigger or function() return g_currentMission ~= nil end,
            ambientMsgs  = def.ambientMsgs,   -- optional table of periodic flavor strings
            onMid        = userMid,            -- optional midpoint handler

            onStart = function(intensity)
                local msg = userFunc(intensity)
                for _, cb in ipairs(api._startCallbacks) do pcall(cb, def, intensity) end
                return msg
            end,

            onEnd = function(intensity)
                -- Run category-specific cleanup first (defined per-API via _onEndCleanup)
                if api._onEndCleanup then pcall(api._onEndCleanup, api) end

                local msg = userEnd and userEnd() or nil
                for _, cb in ipairs(api._endCallbacks) do pcall(cb, def) end
                return msg
            end,
        }

        g_RandomWorldEvents:registerEvent(coreDef)
        return true
    end

    -- =====================
    -- QUERYING
    -- =====================

    --- Returns a shallow copy of all events registered in this category.
    ---@return table[]
    function target:getEventList()
        if not g_RandomWorldEvents then return {} end
        local result = {}
        for _, event in pairs(g_RandomWorldEvents.EVENTS) do
            if event.category == self._CATEGORY then
                local copy = {}
                for k, v in pairs(event) do copy[k] = v end
                table.insert(result, copy)
            end
        end
        return result
    end

    --- Returns true while any event in this category is active.
    ---@return boolean
    function target:isEventActive()
        if not g_RandomWorldEvents then return false end
        local id = g_RandomWorldEvents.EVENT_STATE.activeEvent
        if not id then return false end
        local event = g_RandomWorldEvents.EVENTS[id]
        return event ~= nil and event.category == self._CATEGORY
    end

    --- Returns the active event definition for this category, or nil.
    ---@return table|nil
    function target:getActiveEvent()
        if not g_RandomWorldEvents then return nil end
        local id = g_RandomWorldEvents.EVENT_STATE.activeEvent
        if not id then return nil end
        local event = g_RandomWorldEvents.EVENTS[id]
        if event and event.category == self._CATEGORY then return event end
        return nil
    end

    --- Returns how far through the active event we are (0.0 → 1.0).
    --- Returns 0 if no event of this category is active.
    ---@return number
    function target:getProgress()
        if not self:isEventActive() then return 0 end
        local s = g_RandomWorldEvents.EVENT_STATE
        if not s.eventDuration or s.eventDuration <= 0 then return 1 end
        local elapsed = (g_currentMission and g_currentMission.time or 0) - (s.eventStartTime or 0)
        return math.max(0, math.min(1, elapsed / s.eventDuration))
    end

    --- Returns the seconds remaining in the active event, or 0.
    ---@return number
    function target:getRemainingTime()
        if not self:isEventActive() then return 0 end
        local s = g_RandomWorldEvents.EVENT_STATE
        if not s.eventDuration then return 0 end
        local elapsed = (g_currentMission and g_currentMission.time or 0) - (s.eventStartTime or 0)
        local remainingMs = math.max(0, (s.eventStartTime + s.eventDuration) - (g_currentMission and g_currentMission.time or 0))
        return math.floor(remainingMs / 1000)
    end

    -- =====================
    -- MANUAL TRIGGER
    -- =====================

    --- Manually fire a named event at the given intensity (1-5).
    --- Bypasses cooldown; respects the "another event active" guard.
    ---@param name string
    ---@param intensity number  1-5
    ---@return string  status/result message
    function target:triggerEvent(name, intensity)
        if not g_RandomWorldEvents then
            return "[RWE" .. self._CATEGORY .. "API] Core not available"
        end
        if g_RandomWorldEvents.EVENT_STATE.activeEvent ~= nil then
            return "[RWE" .. self._CATEGORY .. "API] Another event is already active: "
                .. tostring(g_RandomWorldEvents.EVENT_STATE.activeEvent)
        end
        local event = g_RandomWorldEvents.EVENTS[name]
        if not event then
            return "[RWE" .. self._CATEGORY .. "API] Event not found: " .. tostring(name)
        end
        if event.category ~= self._CATEGORY then
            return "[RWE" .. self._CATEGORY .. "API] Event '" .. name
                .. "' belongs to category '" .. tostring(event.category)
                .. "', not '" .. self._CATEGORY .. "'"
        end

        -- Delegate to core so all lifecycle hooks fire correctly.
        return g_RandomWorldEvents:triggerNamedEvent(name, math.max(1, math.min(5, math.floor(intensity or 1))))
    end

    -- =====================
    -- SUBSCRIBERS
    -- =====================

    --- Subscribe to event-start notifications for this category.
    ---@param cb function(eventDef, intensity)
    function target:onEventStart(cb)
        if type(cb) == "function" then table.insert(self._startCallbacks, cb) end
    end

    --- Subscribe to event-end notifications for this category.
    ---@param cb function(eventDef)
    function target:onEventEnd(cb)
        if type(cb) == "function" then table.insert(self._endCallbacks, cb) end
    end

    -- =====================
    -- TICK HANDLERS
    -- =====================

    --- Register a per-tick callback (fires ~every 60 in-game seconds while any event is active).
    --- Safe to call before the core is ready; buffered and flushed on core init.
    ---@param fn function(rweInstance)
    function target:registerTickHandler(fn)
        if type(fn) ~= "function" then return end
        self._tickCounter = self._tickCounter + 1
        local key = "RWE" .. self._CATEGORY .. "API_tick_" .. self._tickCounter
        if g_RandomWorldEvents and g_RandomWorldEvents.registerTickHandler then
            g_RandomWorldEvents:registerTickHandler(key, fn)
        else
            table.insert(self._pendingTicks, { key = key, fn = fn })
        end
    end

    --- Flush pending tick handlers after core becomes available.
    --- Called from each API's initXxxAPI() function.
    function target:_flushPendingTicks()
        if not g_RandomWorldEvents or not g_RandomWorldEvents.registerTickHandler then return end
        for _, entry in ipairs(self._pendingTicks) do
            g_RandomWorldEvents:registerTickHandler(entry.key, entry.fn)
        end
        self._pendingTicks = {}
    end

    -- =====================
    -- VERSION
    -- =====================

    ---@return string
    function target:getVersion()
        return self._VERSION
    end
end

Logging.info("[RWEBaseAPI] Mixin loaded")
