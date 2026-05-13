-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25 Conversion
-- =========================================================
-- Random events that can occur. Settings can be changed!
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================

local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- Resolve mod version once at load time so it's available everywhere.
local modVersion = "?"
do
    local ok, info = pcall(function()
        return g_modManager and g_modManager:getModByName(modName)
    end)
    if ok and info and info.version then modVersion = info.version end
end

---@class RandomWorldEvents
RandomWorldEvents = {
    MOD_NAME = modName,
    VERSION  = modVersion,
    
    events = {
        enabled = true,
        frequency = 5,
        intensity = 2,
        showNotifications = true,
        showWarnings = true,
        showHUD = true,
        cooldown = 30,

        weatherEvents = false,
        economicEvents = true,
        vehicleEvents = true,
        fieldEvents = true,
        wildlifeEvents = true,
        specialEvents = true,

        debugLevel = 1
    },

    -- HUD scale stored at top-level (not under events/physics) for clarity
    hudScale = 1.0,
    
    debug = {
        enabled = false,
        debugLevel = 1,
        showDebugInfo = false
    },
    
    physics = {
        enabled = true,
        wheelGripMultiplier = 1.0,
        articulationDamping = 0.5,
        comStrength = 1.0,
        suspensionStiffness = 1.0,
        showPhysicsInfo = false,
        debugMode = false
    },
    
    modDirectory = modDirectory,
    isInitialized = false,
    needsSave = false,
    saveTime = nil,

    -- HUD instance (created in loadGUI)
    eventHUD = nil,

    -- Per-tick handler table populated by event modules.
    -- Each entry: [name] = function(rweInstance) ... end
    -- Called from applyActiveEventEffects() while an event is active.
    tickHandlers = {}
}

RandomWorldEvents.EVENT_STATE = {
    activeEvent = nil,
    eventStartTime = 0,
    eventDuration = 0,
    eventData = {},
    history = {},
    cooldownUntil = 0,

    -- Immersion: midpoint callback tracking
    midpointFired = false,

    -- Immersion: ambient message cycling
    -- nextAmbientTime = absolute game-time (ms) when next ambient msg fires
    nextAmbientTime = 0,
    ambientMsgIndex = 1,
}

RandomWorldEvents.EVENTS = {}
RandomWorldEvents.eventCounter = 0

-- Subsystem API registry — populated by each RWE[Category]API on load.
-- Access via g_RandomWorldEvents:getSubsystem("economic") etc.
RandomWorldEvents.subsystems = {}

local RandomWorldEvents_mt = Class(RandomWorldEvents)

-- =====================
-- CORE FUNCTIONS
-- =====================

function RandomWorldEvents:new(mission)
    local self = setmetatable({}, RandomWorldEvents_mt)
    self.mission = mission

    -- Per-instance subsystem registry (isolates across mission reloads).
    -- Class-level RandomWorldEvents.subsystems is the default; this shadows it.
    self.subsystems = {}

    self.settingsManager = self:createSettingsManager()

    self:loadSettings()

    self:registerConsoleCommands()

    Logging.info("[RandomWorldEvents] Core initialized successfully")

    return self
end

function RandomWorldEvents:createSettingsManager()
    local manager = {
        MOD_NAME = self.MOD_NAME,
        XMLTAG = "RandomWorldEvents",
        
        defaultConfig = {
            events = {
                enabled = true,
                frequency = 5,
                intensity = 2,
                showNotifications = true,
                showWarnings = true,
                showHUD = true,
                cooldown = 30,
                weatherEvents = false,
                economicEvents = true,
                vehicleEvents = true,
                fieldEvents = true,
                wildlifeEvents = true,
                specialEvents = true,
                debugLevel = 1
            },
            hudScale = 1.0,
            debug = {
                enabled = false,
                debugLevel = 1,
                showDebugInfo = false
            },
            physics = {
                enabled = true,
                wheelGripMultiplier = 1.0,
                articulationDamping = 0.5,
                comStrength = 1.0,
                suspensionStiffness = 1.0,
                showPhysicsInfo = false,
                debugMode = false
            }
        }
    }
    
    -- Define methods after creating the table
    manager.getSavegameXmlFilePath = function()
        if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
            return ("%s/%s.xml"):format(g_currentMission.missionInfo.savegameDirectory, manager.MOD_NAME)
        end
        return nil
    end
    
    manager.loadSettings = function(settingsObject)
        local xmlPath = manager.getSavegameXmlFilePath()
        if xmlPath and fileExists(xmlPath) then
            local xml = XMLFile.load("rwe_Config", xmlPath)
            if xml then
                settingsObject.events.enabled = xml:getBool(manager.XMLTAG..".events.enabled", manager.defaultConfig.events.enabled)
                settingsObject.events.frequency = xml:getInt(manager.XMLTAG..".events.frequency", manager.defaultConfig.events.frequency)
                settingsObject.events.intensity = xml:getInt(manager.XMLTAG..".events.intensity", manager.defaultConfig.events.intensity)
                settingsObject.events.showNotifications = xml:getBool(manager.XMLTAG..".events.showNotifications", manager.defaultConfig.events.showNotifications)
                settingsObject.events.showWarnings = xml:getBool(manager.XMLTAG..".events.showWarnings", manager.defaultConfig.events.showWarnings)
                settingsObject.events.showHUD = xml:getBool(manager.XMLTAG..".events.showHUD", manager.defaultConfig.events.showHUD)
                settingsObject.events.cooldown = xml:getInt(manager.XMLTAG..".events.cooldown", manager.defaultConfig.events.cooldown)
                settingsObject.hudScale = xml:getFloat(manager.XMLTAG..".hudScale", manager.defaultConfig.hudScale)
                settingsObject.events.weatherEvents = xml:getBool(manager.XMLTAG..".events.weatherEvents", manager.defaultConfig.events.weatherEvents)
                settingsObject.events.economicEvents = xml:getBool(manager.XMLTAG..".events.economicEvents", manager.defaultConfig.events.economicEvents)
                settingsObject.events.vehicleEvents = xml:getBool(manager.XMLTAG..".events.vehicleEvents", manager.defaultConfig.events.vehicleEvents)
                settingsObject.events.fieldEvents = xml:getBool(manager.XMLTAG..".events.fieldEvents", manager.defaultConfig.events.fieldEvents)
                settingsObject.events.wildlifeEvents = xml:getBool(manager.XMLTAG..".events.wildlifeEvents", manager.defaultConfig.events.wildlifeEvents)
                settingsObject.events.specialEvents = xml:getBool(manager.XMLTAG..".events.specialEvents", manager.defaultConfig.events.specialEvents)
                settingsObject.events.debugLevel = xml:getInt(manager.XMLTAG..".events.debugLevel", manager.defaultConfig.events.debugLevel)

                settingsObject.debug.enabled = xml:getBool(manager.XMLTAG..".debug.enabled", manager.defaultConfig.debug.enabled)
                settingsObject.debug.debugLevel = xml:getInt(manager.XMLTAG..".debug.debugLevel", manager.defaultConfig.debug.debugLevel)
                settingsObject.debug.showDebugInfo = xml:getBool(manager.XMLTAG..".debug.showDebugInfo", manager.defaultConfig.debug.showDebugInfo)
                
                settingsObject.physics.enabled = xml:getBool(manager.XMLTAG..".physics.enabled", manager.defaultConfig.physics.enabled)
                settingsObject.physics.wheelGripMultiplier = xml:getFloat(manager.XMLTAG..".physics.wheelGripMultiplier", manager.defaultConfig.physics.wheelGripMultiplier)
                settingsObject.physics.articulationDamping = xml:getFloat(manager.XMLTAG..".physics.articulationDamping", manager.defaultConfig.physics.articulationDamping)
                settingsObject.physics.comStrength = xml:getFloat(manager.XMLTAG..".physics.comStrength", manager.defaultConfig.physics.comStrength)
                settingsObject.physics.suspensionStiffness = xml:getFloat(manager.XMLTAG..".physics.suspensionStiffness", manager.defaultConfig.physics.suspensionStiffness)
                settingsObject.physics.showPhysicsInfo = xml:getBool(manager.XMLTAG..".physics.showPhysicsInfo", manager.defaultConfig.physics.showPhysicsInfo)
                settingsObject.physics.debugMode = xml:getBool(manager.XMLTAG..".physics.debugMode", manager.defaultConfig.physics.debugMode)
                
                xml:delete()
                return
            end
        end
        
        -- Use deep copy to avoid reference issues
        settingsObject.events   = {}
        settingsObject.debug    = {}
        settingsObject.physics  = {}
        settingsObject.hudScale = manager.defaultConfig.hudScale

        for k, v in pairs(manager.defaultConfig.events) do
            settingsObject.events[k] = v
        end
        for k, v in pairs(manager.defaultConfig.debug) do
            settingsObject.debug[k] = v
        end
        for k, v in pairs(manager.defaultConfig.physics) do
            settingsObject.physics[k] = v
        end
    end
    
    manager.saveSettings = function(settingsObject)
        local xmlPath = manager.getSavegameXmlFilePath()
        if not xmlPath then 
            Logging.warning("[RWE] No savegame path found")
            return 
        end
        
        local xml = XMLFile.create("rwe_Config", xmlPath, manager.XMLTAG)
        if xml then
            -- Save events settings
            xml:setBool(manager.XMLTAG..".events.enabled", settingsObject.events.enabled)
            xml:setInt(manager.XMLTAG..".events.frequency", settingsObject.events.frequency)
            xml:setInt(manager.XMLTAG..".events.intensity", settingsObject.events.intensity)
            xml:setBool(manager.XMLTAG..".events.showNotifications", settingsObject.events.showNotifications)
            xml:setBool(manager.XMLTAG..".events.showWarnings", settingsObject.events.showWarnings)
            xml:setBool(manager.XMLTAG..".events.showHUD", settingsObject.events.showHUD)
            xml:setInt(manager.XMLTAG..".events.cooldown", settingsObject.events.cooldown)
            xml:setFloat(manager.XMLTAG..".hudScale", settingsObject.hudScale or 1.0)
            xml:setBool(manager.XMLTAG..".events.weatherEvents", settingsObject.events.weatherEvents)
            xml:setBool(manager.XMLTAG..".events.economicEvents", settingsObject.events.economicEvents)
            xml:setBool(manager.XMLTAG..".events.vehicleEvents", settingsObject.events.vehicleEvents)
            xml:setBool(manager.XMLTAG..".events.fieldEvents", settingsObject.events.fieldEvents)
            xml:setBool(manager.XMLTAG..".events.wildlifeEvents", settingsObject.events.wildlifeEvents)
            xml:setBool(manager.XMLTAG..".events.specialEvents", settingsObject.events.specialEvents)
            xml:setInt(manager.XMLTAG..".events.debugLevel", settingsObject.events.debugLevel)
            
            -- Save debug settings
            xml:setBool(manager.XMLTAG..".debug.enabled", settingsObject.debug.enabled)
            xml:setInt(manager.XMLTAG..".debug.debugLevel", settingsObject.debug.debugLevel)
            xml:setBool(manager.XMLTAG..".debug.showDebugInfo", settingsObject.debug.showDebugInfo)
            
            -- Save physics settings
            xml:setBool(manager.XMLTAG..".physics.enabled", settingsObject.physics.enabled)
            xml:setFloat(manager.XMLTAG..".physics.wheelGripMultiplier", settingsObject.physics.wheelGripMultiplier)
            xml:setFloat(manager.XMLTAG..".physics.articulationDamping", settingsObject.physics.articulationDamping)
            xml:setFloat(manager.XMLTAG..".physics.comStrength", settingsObject.physics.comStrength)
            xml:setFloat(manager.XMLTAG..".physics.suspensionStiffness", settingsObject.physics.suspensionStiffness)
            xml:setBool(manager.XMLTAG..".physics.showPhysicsInfo", settingsObject.physics.showPhysicsInfo)
            xml:setBool(manager.XMLTAG..".physics.debugMode", settingsObject.physics.debugMode)
            
            xml:save()
            xml:delete()
            self:dbg("Settings saved successfully")
        else
            Logging.error("[RWE] Failed to create XML file for settings")
        end
    end
    
    return manager
end

function RandomWorldEvents:loadSettings()
    if self.settingsManager and self.settingsManager.loadSettings then
        self.settingsManager.loadSettings(self)
        self:dbg("Settings loaded")
    else
        Logging.error("[RandomWorldEvents] Settings manager not properly initialized")
    end
end

function RandomWorldEvents:saveSettings()
    if self.settingsManager and self.settingsManager.saveSettings then
        self.settingsManager.saveSettings(self)
        self:dbg("Settings saved")
    else
        Logging.error("[RandomWorldEvents] Settings manager not properly initialized")
    end
end

function RandomWorldEvents:registerConsoleCommands()
    addConsoleCommand("rwe", "Random World Events commands", "consoleCommandHelp", self)
    addConsoleCommand("rweStatus", "Show RWE status", "consoleCommandStatus", self)
    addConsoleCommand("rweTest", "Test random event", "consoleCommandTest", self)
    addConsoleCommand("rweEnd", "End current event", "consoleCommandEnd", self)
    addConsoleCommand("rweDebug", "Toggle debug mode", "consoleCommandDebug", self)
    addConsoleCommand("rweList", "List available events", "consoleCommandList", self)
    addConsoleCommand("rweSettings", "Open settings screen", "consoleCommandSettings", self)
    
    self:dbg("Console commands registered")
end

-- =====================
-- EVENT SYSTEM
-- =====================

function RandomWorldEvents:getFarmId()
    return g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 0
end

function RandomWorldEvents:getVehicle()
    return g_currentMission and g_currentMission.controlledVehicle or nil
end

function RandomWorldEvents:registerEvent(eventData)
    self.eventCounter = self.eventCounter + 1
    self.EVENTS[eventData.name] = eventData
    self:dbg("Registered event: " .. eventData.name)
    return eventData.name
end

-- Register a per-tick handler called while any event is active.
-- name   : string key (used for deduplication/replacement)
-- handler: function(rweInstance) called each frame during an active event
function RandomWorldEvents:registerTickHandler(name, handler)
    self.tickHandlers[name] = handler
    self:dbg("Registered tick handler: " .. name)
end

-- Register a subsystem API table under a category name.
-- Called automatically by each api/[Category]API.lua on load.
-- name     : category string key (e.g. "economic", "field")
-- apiTable : the RWE[Category]API global table
function RandomWorldEvents:registerSubsystem(name, apiTable)
    self.subsystems[name] = apiTable
    self:dbg("Subsystem registered: " .. tostring(name))
end

-- Return the registered subsystem API for the given category, or nil.
-- Usage: local econ = g_RandomWorldEvents:getSubsystem("economic")
---@param name string
---@return table|nil
function RandomWorldEvents:getSubsystem(name)
    return self.subsystems[name]
end

-- Debug log helper — only prints when debug.enabled is true.
-- level 1 = verbose (default), level 2 = detailed, level 3 = trace
function RandomWorldEvents:dbg(msg, level)
    if self.debug and self.debug.enabled then
        if (self.debug.debugLevel or 1) >= (level or 1) then
            Logging.info("[RWE-DBG] " .. tostring(msg))
        end
    end
end

function RandomWorldEvents:triggerRandomEvent()
    if not self.events.enabled then
        self:dbg("triggerRandomEvent: events disabled")
        return false
    end

    if self.EVENT_STATE.activeEvent ~= nil then
        self:dbg("triggerRandomEvent: event already active: " .. tostring(self.EVENT_STATE.activeEvent))
        return false
    end
    
    local available = {}
    for eventId, event in pairs(self.EVENTS) do
        local categoryKey = event.category .. "Events"
        local categoryEnabled = self.events[categoryKey]
        local canTrigger = event.canTrigger()
        local intensityOk = self.events.intensity >= (event.minIntensity or 1)
        
        if categoryEnabled and canTrigger and intensityOk then
            table.insert(available, eventId)
        end
    end
    
    if #available == 0 then
        self:dbg("triggerRandomEvent: no events passed canTrigger/category/intensity checks")
        return false
    end
    self:dbg(string.format("triggerRandomEvent: %d events eligible", #available))

    -- Weighted random selection: sum weights, pick by accumulated roll
    local totalWeight = 0
    for _, eid in ipairs(available) do
        totalWeight = totalWeight + (self.EVENTS[eid].weight or 1)
    end
    local roll = math.random() * totalWeight
    local cumulative = 0
    local eventId = available[#available]  -- fallback to last
    for _, eid in ipairs(available) do
        cumulative = cumulative + (self.EVENTS[eid].weight or 1)
        if roll <= cumulative then
            eventId = eid
            break
        end
    end
    local event = self.EVENTS[eventId]
    self:_activateEvent(event, self.events.intensity)
    return true
end

--- Trigger a specific named event at a given intensity (1-5).
--- Used by subsystem API triggerEvent calls so all lifecycle hooks fire correctly.
--- Returns the onStart message string, or an error string if activation failed.
---@param name string  event key in self.EVENTS
---@param intensity number  1-5
---@return string
function RandomWorldEvents:triggerNamedEvent(name, intensity)
    if self.EVENT_STATE.activeEvent ~= nil then
        return "[RWE] Another event is already active: " .. tostring(self.EVENT_STATE.activeEvent)
    end
    local event = self.EVENTS[name]
    if not event then
        return "[RWE] Event not found: " .. tostring(name)
    end
    local safeIntensity = math.max(1, math.min(5, math.floor(intensity or 1)))
    local msg = self:_activateEvent(event, safeIntensity)
    self:dbg(string.format("triggerNamedEvent: '%s' at intensity %d", name, safeIntensity))
    return msg or ("Triggered: " .. name)
end

--- Internal: write EVENT_STATE for a new event and fire onStart + opening notify.
--- Returns the onStart message string (may be nil for silent events).
---@param event table   event definition from self.EVENTS
---@param intensity number  1-5
---@return string|nil
function RandomWorldEvents:_activateEvent(event, intensity)
    local duration = 0
    if type(event.duration) == "table" then
        duration = math.random(event.duration.min, event.duration.max) * 60000
    end

    self.EVENT_STATE.activeEvent    = event.name
    self.EVENT_STATE.eventStartTime = g_currentMission.time
    self.EVENT_STATE.eventDuration  = duration

    -- Reset per-event immersion state
    self.EVENT_STATE.midpointFired   = false
    self.EVENT_STATE.ambientMsgIndex = 1
    -- First ambient message fires after 10% of the event duration (min 60 s)
    local firstAmbientDelay = math.max(60000, duration * 0.10)
    self.EVENT_STATE.nextAmbientTime = g_currentMission.time + firstAmbientDelay

    Logging.info(string.format("[RWE] Event activated: %s (intensity=%d, duration=%.1f min)",
        event.name, intensity, duration / 60000))

    local message = event.onStart(intensity)
    self:notifyEvent(message, event.category, true)
    return message
end

--- Show a rich event notification.
-- Uses HUD flash queue when available; falls back to ingame notification.
-- @param message     Display text (nil = silent)
-- @param categoryKey Event category string
-- @param isPositive  true = good event, false/nil = neutral, "warn" = warning
function RandomWorldEvents:notifyEvent(message, categoryKey, isPositive)
    if not message then return end

    -- Always push to HUD flash queue (even if HUD is hidden — it queues for when shown)
    if self.eventHUD then
        self.eventHUD:pushFlash(message, categoryKey, isPositive)
    end

    -- Also show the standard ingame notification if enabled
    if self.events.showNotifications and g_currentMission then
        local notifType
        if isPositive == true then
            notifType = FSBaseMission.INGAME_NOTIFICATION_OK
        elseif isPositive == "warn" then
            notifType = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        else
            notifType = FSBaseMission.INGAME_NOTIFICATION_INFO
        end
        g_currentMission:addIngameNotification(notifType, message)
    end
end

-- =====================
-- PHYSICS SYSTEM (FS25)
-- =====================

function RandomWorldEvents:updatePhysics(vehicle)
    if not self.physics.enabled or vehicle == nil then
        return
    end

    if vehicle.getIsActiveForInput == nil or not vehicle:getIsActiveForInput() then
        return
    end

    if vehicle.wheels and self.physics.wheelGripMultiplier then
        local grip = self.physics.wheelGripMultiplier
        for _, wheel in pairs(vehicle.wheels) do
            if wheel.physics ~= nil then
                wheel.physics.frictionScale = grip
            end
        end
    end

    if vehicle.wheels and self.physics.suspensionStiffness then
        for _, wheel in pairs(vehicle.wheels) do
            if wheel.suspension ~= nil then
                local originalForce = wheel.suspension.originalSpringForce or wheel.suspension.springForce
                wheel.suspension.originalSpringForce = originalForce
                wheel.suspension.springForce = originalForce * self.physics.suspensionStiffness
            end
        end
    end
end

-- =====================
-- UPDATE LOOPS
-- =====================

function RandomWorldEvents:update(dt)
    if not self.isInitialized then return end

    -- Tick HUD
    if self.eventHUD then
        self.eventHUD:update(dt)
    end

    -- Debug heartbeat every ~30 seconds of game time
    if self.debug and self.debug.enabled then
        self._dbgNextHeartbeat = self._dbgNextHeartbeat or 0
        if g_currentMission.time > self._dbgNextHeartbeat then
            self._dbgNextHeartbeat = g_currentMission.time + 30000
            local cooldownLeft = math.max(0, math.floor(((self.EVENT_STATE.cooldownUntil or 0) - g_currentMission.time) / 1000))
            self:dbg(string.format(
                "heartbeat | active=%s cooldown=%ds enabled=%s freq=%d intensity=%d",
                tostring(self.EVENT_STATE.activeEvent or "none"),
                cooldownLeft,
                tostring(self.events.enabled),
                self.events.frequency,
                self.events.intensity
            ))
        end
    end

    -- Event system update
    if self.events.enabled then
        if g_currentMission.time > (self.EVENT_STATE.cooldownUntil or 0) then
            local chance = self.events.frequency * 0.001
            local roll = math.random()
            if roll <= chance then
                self:dbg(string.format("roll %.4f <= chance %.4f — attempting trigger", roll, chance), 2)
                self:triggerRandomEvent()
                local cooldownMs = self.events.cooldown * 60000
                local frequencyFactor = (11 - self.events.frequency) / 10
                self.EVENT_STATE.cooldownUntil = g_currentMission.time + (cooldownMs * frequencyFactor)
                self:dbg(string.format("cooldown set: %.1f min", (cooldownMs * frequencyFactor) / 60000), 2)
            end
        else
            -- Only log cooldown at level 3 (very verbose)
            if self.debug and self.debug.enabled and (self.debug.debugLevel or 1) >= 3 then
                local remaining = math.floor(((self.EVENT_STATE.cooldownUntil or 0) - g_currentMission.time) / 1000)
                if remaining > 0 and not self._dbgLastCooldownLog or
                   (self._dbgLastCooldownLog and g_currentMission.time > self._dbgLastCooldownLog + 5000) then
                    self:dbg("in cooldown: " .. remaining .. "s remaining", 3)
                    self._dbgLastCooldownLog = g_currentMission.time
                end
            end
        end
    end
    
    if self.EVENT_STATE.activeEvent then
        self:applyActiveEventEffects()
        self:_tickImmersion()

        if g_currentMission.time > (self.EVENT_STATE.eventStartTime + (self.EVENT_STATE.eventDuration or 0)) then
            local event = self.EVENTS[self.EVENT_STATE.activeEvent]
            if event and event.onEnd then
                local message = event.onEnd()
                self:notifyEvent(message, event and event.category, nil)
            end
            Logging.info("[RWE] Event ended: " .. tostring(self.EVENT_STATE.activeEvent))
            self.EVENT_STATE.activeEvent = nil
        end
    end
    
    if self.physics.enabled then
        local vehicle = g_currentMission.controlledVehicle
        if vehicle then
            if PhysicsUtils and PhysicsUtils.applyAdvancedPhysics then
                PhysicsUtils:applyAdvancedPhysics(vehicle)
            else
                self:updatePhysics(vehicle)
            end
        end
    end
end

-- Called each frame while an event is active. Dispatches to all registered
-- tick handlers so event modules can apply continuous per-frame effects
-- (e.g. vehicle speed boost reapplication) without monkey-patching :update.
function RandomWorldEvents:applyActiveEventEffects()
    for _, handler in pairs(self.tickHandlers) do
        handler(self)
    end
end

--- Drive midpoint callbacks and ambient flavor messages for the active event.
--- Called every frame from update() while an event is active.
--- Both subsystems are no-ops for events that don't define onMid / ambientMsgs.
function RandomWorldEvents:_tickImmersion()
    local s = self.EVENT_STATE
    if not s.activeEvent or not g_currentMission then return end

    local event    = self.EVENTS[s.activeEvent]
    if not event then return end

    local now      = g_currentMission.time
    local elapsed  = now - s.eventStartTime
    local duration = s.eventDuration or 0

    -- ── Midpoint callback ─────────────────────────────────────────────────
    -- Fires once when the event is ≥ 50% complete (duration > 0 required).
    -- Uses "warn" urgency so it stands out from the start notification.
    if not s.midpointFired and duration > 0 and elapsed >= duration * 0.50 then
        s.midpointFired = true
        if event.onMid then
            local ok, msg = pcall(event.onMid, self.events.intensity)
            if ok and msg then
                self:notifyEvent(msg, event.category, "warn")
                self:dbg("Midpoint fired for: " .. s.activeEvent)
            end
        end
    end

    -- ── Ambient flavor messages ───────────────────────────────────────────
    -- Cycles through event.ambientMsgs on a timer.
    -- Interval: 15 % of duration (min 90 s, max 5 min) so messages feel
    -- proportional regardless of whether an event lasts 10 or 90 minutes.
    if event.ambientMsgs and #event.ambientMsgs > 0 and now >= s.nextAmbientTime then
        local msgs  = event.ambientMsgs
        local idx   = ((s.ambientMsgIndex - 1) % #msgs) + 1
        local msg   = msgs[idx]
        s.ambientMsgIndex = idx + 1

        -- Ambient messages use nil isPositive → INGAME_NOTIFICATION_INFO
        if msg then
            self:notifyEvent(msg, event.category, nil)
        end

        -- Schedule next ambient tick
        local interval = math.max(90000, math.min(300000, duration * 0.15))
        s.nextAmbientTime = now + interval
    end
end

-- =====================
-- CONSOLE COMMANDS
-- =====================

function RandomWorldEvents:consoleCommandHelp()
    print("=== Random World Events Commands ===")
    print("rwe          - Show this help")
    print("rweStatus    - Show current status")
    print("rweTest      - Force-trigger random event")
    print("rweEnd       - End current event")
    print("rweSettings  - Open settings screen (also F3)")
    print("rweDebug on|off - Toggle debug mode")
    print("rweList [category] - List registered events")
    print("================================")
    return "Random World Events commands listed above"
end

function RandomWorldEvents:consoleCommandStatus()
    local status = string.format(
        "=== RWE Status ===\n" ..
        "Events enabled: %s\n" ..
        "Frequency: %d/10\n" ..
        "Intensity: %d/5\n" ..
        "Active event: %s\n" ..
        "Cooldown active: %s\n" ..
        "Physics enabled: %s\n" ..
        "=========================",
        tostring(self.events.enabled),
        self.events.frequency,
        self.events.intensity,
        self.EVENT_STATE.activeEvent or "None",
        tostring(g_currentMission.time < self.EVENT_STATE.cooldownUntil),
        tostring(self.physics.enabled)
    )
    print(status)
    return status
end

function RandomWorldEvents:consoleCommandTest()
    local success = self:triggerRandomEvent()
    if success then
        return "Random event triggered successfully"
    else
        return "Failed to trigger random event"
    end
end

function RandomWorldEvents:consoleCommandEnd()
    if not self.EVENT_STATE.activeEvent then
        return "No active event to end"
    end
    
    local event = self.EVENTS[self.EVENT_STATE.activeEvent]
    if event and event.onEnd then
        local message = event.onEnd()
        self:notifyEvent(message, event and event.category, nil)
    end
    
    self.EVENT_STATE.activeEvent = nil
    return "Event ended"
end

function RandomWorldEvents:consoleCommandDebug(mode)
    if mode == "on" then
        self.debug.enabled = true
        self.debug.showDebugInfo = true
        return "Debug mode ENABLED"
    elseif mode == "off" then
        self.debug.enabled = false
        self.debug.showDebugInfo = false
        return "Debug mode DISABLED"
    else
        self.debug.enabled = not self.debug.enabled
        self.debug.showDebugInfo = self.debug.enabled
        return "Debug mode: " .. (self.debug.enabled and "ENABLED" or "DISABLED")
    end
end

function RandomWorldEvents:consoleCommandList(category)
    print("=== Available Events ===")
    local total = 0
    for name, event in pairs(self.EVENTS) do
        if not category or event.category == category then
            print(string.format("%s (%s)", name, event.category))
            total = total + 1
        end
    end
    print(string.format("Total: %d events", total))
    print("========================")
    return string.format("Listed %d events", total)
end

-- Settings: open with Shift+O or this command
function RandomWorldEvents:consoleCommandSettings()
    if self.settingsPanel then
        self.settingsPanel:toggle()
        return "Settings panel toggled"
    end
    return "Settings: open ESC > Settings and scroll to 'Random World Events'"
end

-- =====================
-- EVENT MODULES LOADER
-- =====================

function RandomWorldEvents:loadEventModules()
    -- Process any pending registrations that were collected
    if RandomWorldEvents and RandomWorldEvents.pendingRegistrations then
        self:dbg("Processing " .. #RandomWorldEvents.pendingRegistrations .. " pending registrations")
        for _, registrationFunc in ipairs(RandomWorldEvents.pendingRegistrations) do
            if type(registrationFunc) == "function" then
                registrationFunc()
            end
        end
        RandomWorldEvents.pendingRegistrations = {}
        self:dbg("All pending registrations processed")
    end
    
    -- PhysicsUtils self-initializes via the pendingRegistrations queue above;
    -- no second :new() call needed here.

    Logging.info("[RWE] Loaded " .. self.eventCounter .. " events total")
end

-- =====================
-- GUI LOADER
-- =====================

function RandomWorldEvents:loadGUI()
    -- Create the event HUD overlay
    self.eventHUD = RWEEventHUD.new(self)
    if self.eventHUD then
        self.eventHUD.scale = self.hudScale or 1.0
        self:dbg("Event HUD created")
    else
        Logging.warning("[RWE] RWEEventHUD not available — HUD disabled")
    end

    -- Create the custom settings panel (Shift+O)
    self.settingsPanel = RWESettingsPanel.new(self)
    if self.settingsPanel then
        self:dbg("Custom Settings Panel created")
    end

    -- Settings are also injected into ESC > Settings via RWESettingsIntegration.
    self:dbg("GUI ready")
end

-- =====================
-- FS25 INTEGRATION
-- =====================

local rweManager
local installInputHooks  -- forward declaration: defined below load/update, called from load

local function load(mission)
    if rweManager == nil then
        Logging.info("[RandomWorldEvents] Initializing...")
        
        -- Create the manager
        rweManager = RandomWorldEvents:new(mission)
        
        if not rweManager then
            Logging.error("[RWE] Failed to create RandomWorldEvents instance")
            return
        end
        
        -- Store in global namespace BEFORE loading modules
        getfenv(0)["g_RandomWorldEvents"] = rweManager
        -- Cross-mod bridge: other mods detect via mission property
        mission.randomWorldEvents = rweManager
        
        -- Now load event modules
        rweManager:loadEventModules()

        -- Install input hooks early (before player/vehicle registerActionEvents fires).
        -- The PLAYER context hook intercepts PlayerInputComponent.registerActionEvents
        -- which fires during mission loading — it must be in place before that happens.
        installInputHooks()

        -- Mark as initialized
        rweManager.isInitialized = true

        -- Show notification
        if rweManager.events.enabled and rweManager.events.showNotifications then
            mission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                "Random World Events v" .. modVersion .. " loaded"
            )
        end

        Logging.info("[RandomWorldEvents] Initialized successfully")
    end
end

local function update(mission, dt)
    if rweManager and rweManager.isInitialized then
        rweManager:update(dt)
    end
end

local function delete(mission)
    if rweManager then
        -- Restore hooked functions before teardown
        if rweManager._playerInputHookOriginal and PlayerInputComponent then
            PlayerInputComponent.registerActionEvents = rweManager._playerInputHookOriginal
        end
        if rweManager._vehicleInputHookOriginal and InputBinding then
            InputBinding.endActionEventsModification = rweManager._vehicleInputHookOriginal
        end

        if rweManager.eventHUD then
            rweManager.eventHUD:saveLayout()
            rweManager.eventHUD:delete()
            rweManager.eventHUD = nil
        end
        if rweManager.settingsPanel then
            rweManager.settingsPanel:delete()
            rweManager.settingsPanel = nil
        end
        rweManager:saveSettings()
        rweManager = nil
        getfenv(0)["g_RandomWorldEvents"] = nil
        if g_currentMission then g_currentMission.randomWorldEvents = nil end
        Logging.info("[RandomWorldEvents] Shutting down")
    end
end

-- =====================
-- INPUT CALLBACKS
-- No arguments: FS25 passes none to action callbacks registered via registerActionEvent.
-- =====================

function RandomWorldEvents:onToggleHUDInput()
    if self.eventHUD then
        self.eventHUD:toggleVisibility()
    end
end

function RandomWorldEvents:onToggleSettingsInput()
    if self.settingsPanel then
        self.settingsPanel:toggle()
    end
end

-- =====================
-- INPUT REGISTRATION
-- Mirrors the SoilFertilizer pattern:
--   PLAYER context  → hook PlayerInputComponent.registerActionEvents
--   VEHICLE context → hook InputBinding.endActionEventsModification
-- FSBaseMission.registerActionEvents targets the base class and never fires in FS25.
-- =====================

installInputHooks = function()
    if not rweManager then return end

    -- ── PLAYER context ────────────────────────────────────────────────────
    if PlayerInputComponent and PlayerInputComponent.registerActionEvents then
        local originalPlayerReg = PlayerInputComponent.registerActionEvents
        rweManager._playerInputHookOriginal = originalPlayerReg

        PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
            originalPlayerReg(inputComponent, ...)

            -- Only for the local owning player
            if not (inputComponent.player and inputComponent.player.isOwner) then return end
            -- Guard against double-registration
            if g_RandomWorldEvents and g_RandomWorldEvents.hudPlayerEventId then return end
            if not g_RandomWorldEvents then return end

            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

            local hudOk, hudId = g_inputBinding:registerActionEvent(
                InputAction.RWE_TOGGLE_HUD, g_RandomWorldEvents,
                g_RandomWorldEvents.onToggleHUDInput,
                false, true, false, true
            )
            if hudOk and hudId then
                g_RandomWorldEvents.hudPlayerEventId = hudId
                g_inputBinding:setActionEventText(hudId, g_i18n:getText("input_RWE_TOGGLE_HUD") or "Toggle RWE HUD")
                Logging.info("[RWE] HUD toggle registered in PLAYER context")
            else
                Logging.warning("[RWE] HUD toggle PLAYER registration failed")
            end

            local spOk, spId = g_inputBinding:registerActionEvent(
                InputAction.RWE_TOGGLE_SETTINGS, g_RandomWorldEvents,
                g_RandomWorldEvents.onToggleSettingsInput,
                false, true, false, true
            )
            if spOk and spId then
                g_RandomWorldEvents.settingsPlayerEventId = spId
                g_inputBinding:setActionEventText(spId, g_i18n:getText("input_RWE_TOGGLE_SETTINGS") or "RWE Settings")
                -- Cache key hint for the settings panel close button
                local ok, ktext = pcall(function()
                    return g_inputBinding:getActionDisplayName(InputAction.RWE_TOGGLE_SETTINGS)
                end)
                g_RandomWorldEvents.settingsKeyHint = (ok and ktext and ktext ~= "") and ktext or "Shift+O"
                Logging.info("[RWE] Settings toggle registered in PLAYER context")
            else
                Logging.warning("[RWE] Settings toggle PLAYER registration failed")
            end

            g_inputBinding:endActionEventsModification()
        end
        Logging.info("[RWE] PlayerInputComponent hook installed")
    end

    -- ── VEHICLE context ───────────────────────────────────────────────────
    if InputBinding and InputBinding.endActionEventsModification then
        local _rweVehicleHookActive = false
        local originalEndMod = InputBinding.endActionEventsModification
        rweManager._vehicleInputHookOriginal = originalEndMod

        InputBinding.endActionEventsModification = function(binding, ignoreCheck)
            -- Capture context name BEFORE the original resets it
            local contextName = ""
            if binding.registrationContext and
               binding.registrationContext ~= InputBinding.NO_REGISTRATION_CONTEXT then
                contextName = binding.registrationContext.name or ""
            end

            originalEndMod(binding, ignoreCheck)

            if contextName ~= Vehicle.INPUT_CONTEXT_NAME then return end
            if _rweVehicleHookActive then return end
            if not g_RandomWorldEvents then return end

            _rweVehicleHookActive = true

            -- Only remove vehicle-context IDs. Player-context IDs were registered
            -- once at loadFinished and must NOT be cleared here — doing so forces
            -- re-registration which creates fresh event IDs and discards the user's
            -- saved key binding, causing the "must rebind every session" issue.
            local mgr = g_RandomWorldEvents
            local staleVehicleIds = { "hudVehicleEventId", "settingsVehicleEventId" }
            for _, field in ipairs(staleVehicleIds) do
                local oldId = mgr[field]
                if oldId then
                    pcall(function() binding:removeActionEvent(oldId) end)
                    mgr[field] = nil
                end
            end

            -- Register in VEHICLE context
            binding:beginActionEventsModification(Vehicle.INPUT_CONTEXT_NAME)

            local vHudOk, vHudId = binding:registerActionEvent(
                InputAction.RWE_TOGGLE_HUD, mgr,
                mgr.onToggleHUDInput,
                false, true, false, true
            )
            if vHudOk and vHudId then
                mgr.hudVehicleEventId = vHudId
                binding:setActionEventText(vHudId, g_i18n:getText("input_RWE_TOGGLE_HUD") or "Toggle RWE HUD")
                Logging.debug("[RWE] HUD toggle registered in VEHICLE context")
            end

            local vSpOk, vSpId = binding:registerActionEvent(
                InputAction.RWE_TOGGLE_SETTINGS, mgr,
                mgr.onToggleSettingsInput,
                false, true, false, true
            )
            if vSpOk and vSpId then
                mgr.settingsVehicleEventId = vSpId
                binding:setActionEventTextVisibility(vSpId, false)
                Logging.debug("[RWE] Settings toggle registered in VEHICLE context")
            end

            binding:endActionEventsModification()

            _rweVehicleHookActive = false
        end
        Logging.info("[RWE] InputBinding.endActionEventsModification hooked for VEHICLE context")
    end
end

local function draw(mission)
    if rweManager then
        -- HUD only draws when no GUI/menu is open
        if g_gui and not g_gui:getIsGuiVisible() then
            if rweManager.eventHUD then
                rweManager.eventHUD:draw()
            end
        end
        -- Settings panel draws independently — it has its own isOpen guard
        -- and must always render when open so hitboxes are rebuilt each frame
        if rweManager.settingsPanel then
            rweManager.settingsPanel:draw()
        end
    end
end

local function mouseEvent(mission, posX, posY, isDown, isUp, button)
    if rweManager then
        if rweManager.settingsPanel and rweManager.settingsPanel.isOpen then
            rweManager.settingsPanel:onMouseEvent(posX, posY, isDown, isUp, button)
            return true -- consumed — base game camera never sees this
        end
        if rweManager.eventHUD then
            rweManager.eventHUD:onMouseEvent(posX, posY, isDown, isUp, button)
        end
    end
end

local function loadFinished(mission, ...)
    if rweManager and not rweManager.guiLoaded then
        rweManager:loadGUI()
        rweManager.guiLoaded = true

        -- Direct PLAYER context registration as a safety net:
        -- PlayerInputComponent.registerActionEvents may have already fired during
        -- mission loading before our hook in installInputHooks() could intercept it.
        -- This ensures bindings work on-foot without the user needing to rebind.
        if g_inputBinding and g_RandomWorldEvents and not g_RandomWorldEvents.hudPlayerEventId then
            local mgr = g_RandomWorldEvents
            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

            local hudOk, hudId = g_inputBinding:registerActionEvent(
                InputAction.RWE_TOGGLE_HUD, mgr, mgr.onToggleHUDInput,
                false, true, false, true)
            if hudOk and hudId then
                mgr.hudPlayerEventId = hudId
                g_inputBinding:setActionEventText(hudId, g_i18n:getText("input_RWE_TOGGLE_HUD") or "Toggle RWE HUD")
                Logging.info("[RWE] HUD toggle registered (PLAYER context, loadFinished fallback)")
            end

            local spOk, spId = g_inputBinding:registerActionEvent(
                InputAction.RWE_TOGGLE_SETTINGS, mgr, mgr.onToggleSettingsInput,
                false, true, false, true)
            if spOk and spId then
                mgr.settingsPlayerEventId = spId
                g_inputBinding:setActionEventText(spId, g_i18n:getText("input_RWE_TOGGLE_SETTINGS") or "RWE Settings")
                -- Cache key hint text for the settings panel close button
                local ok, ktext = pcall(function()
                    return g_inputBinding:getActionDisplayName(InputAction.RWE_TOGGLE_SETTINGS)
                end)
                mgr.settingsKeyHint = (ok and ktext and ktext ~= "") and ktext or "Shift+O"
                Logging.info("[RWE] Settings toggle registered (PLAYER context, loadFinished fallback)")
            end

            g_inputBinding:endActionEventsModification()
        end
    end
end

-- Hook into FS25
Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadFinished)
FSBaseMission.update     = Utils.appendedFunction(FSBaseMission.update,     update)
FSBaseMission.draw       = Utils.appendedFunction(FSBaseMission.draw,       draw)
FSBaseMission.mouseEvent = Utils.prependedFunction(FSBaseMission.mouseEvent, mouseEvent)
FSBaseMission.delete     = Utils.appendedFunction(FSBaseMission.delete,     delete)

Logging.info("========================================")
Logging.info("   FS25 Random World Events v" .. modVersion .. "   ")
Logging.info("           Successfully Loaded          ")
Logging.info("     Type 'rwe' in console for help     ")
Logging.info("========================================")

return RandomWorldEvents