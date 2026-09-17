-- 2026-08-22 (Wizard): with MasterHUD installed this mod's own HUD hide/move keys must not
-- merely be inert, they must not REGISTER at all - that is what removes their rows from the
-- F1 legend and the Controls list. Probed on TaxMod first: skipping registration does remove
-- the row, so the pattern is used suite-wide. Only HUD hide/move actions are gated; every
-- other action this mod registers is untouched.
local function __rfMhOwnsHudKeys()
    return ((g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD) ~= nil
end

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

-- Hot-reload latch (FuelCosts reference): g_currentModDirectory and
-- g_currentModName are nil on a live re-source, so they are latched into
-- module globals on first load, with a g_modsDirectory loose-folder fallback.
RandomWorldEventsModDirectory = RandomWorldEventsModDirectory
    or g_currentModDirectory
    or (g_modsDirectory ~= nil and (g_modsDirectory .. "FS25_RandomWorldEvents/") or nil)
RandomWorldEventsModName = RandomWorldEventsModName or g_currentModName or "FS25_RandomWorldEvents"
local modDirectory = RandomWorldEventsModDirectory
local modName = RandomWorldEventsModName

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

        -- Arcade-physics opt-in (default OFF). When ON, the retained physics
        -- events (speed boost, engine trouble, equipment durability) may fire,
        -- out of the economy: speed and engine on the host player's own vehicle,
        -- durability on the usage wear of every vehicle in use.
        arcadePhysics = false,

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
    activeIntensity = nil,  -- intensity (1-5) the active event was triggered at (companion read API)
    activeCategory = nil,   -- category of the active event (companion read API)
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

-- RSF-F201 item 12: the input-hook record home. The settings literal above is a
-- bare table on purpose (its constructor re-establishes the defaults on every
-- load), so it cannot hold a session-lived record. This latched table survives a
-- script reload the way the mod's other `X = X or {}` modules do, and holds only
-- the input-hook record: captured predecessors, install latch, owner binding.
-- No other participant reads or writes it.
RWE_InputHookRecord = RWE_InputHookRecord or {}

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
                arcadePhysics = false,
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
            },
            -- Release-gate opt-in (default false), orthogonal to difficulty. See ReleaseGate.lua.
            experimentalSystems = false
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
                settingsObject.events.arcadePhysics = xml:getBool(manager.XMLTAG..".events.arcadePhysics", manager.defaultConfig.events.arcadePhysics)
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

                settingsObject.experimentalSystems = xml:getBool(manager.XMLTAG..".experimentalSystems", manager.defaultConfig.experimentalSystems)

                -- Load saved event state (temp fields; applied in loadFinished when g_currentMission.time is valid)
                local savedEvent = xml:getString(manager.XMLTAG..".eventState.activeEvent", "")
                settingsObject._savedActiveEvent = savedEvent ~= "" and savedEvent or nil
                settingsObject._savedActiveIntensity = xml:getInt(manager.XMLTAG..".eventState.intensity", 0)
                settingsObject._savedRemainingMs = xml:getFloat(manager.XMLTAG..".eventState.remainingMs", 0)
                settingsObject._savedCooldownRemainingMs = xml:getFloat(manager.XMLTAG..".eventState.cooldownRemainingMs", 0)
                settingsObject._savedMidpointFired = xml:getBool(manager.XMLTAG..".eventState.midpointFired", false)

                -- EC-6: the event summary, the crisis parts and the pending settlement lines.
                local summaryKey = xml:getString(manager.XMLTAG..".eventState#summaryKey", "")
                settingsObject._savedSummaryKey = summaryKey ~= "" and summaryKey or nil
                local summaryArgs = {}
                local i = 0
                while true do
                    local arg = xml:getString(string.format("%s.eventState.summaryArg(%d)#value", manager.XMLTAG, i))
                    if arg == nil then break end
                    summaryArgs[#summaryArgs + 1] = arg
                    i = i + 1
                end
                settingsObject._savedSummaryArgs = summaryArgs
                settingsObject._savedCrisisHasPrice = xml:getBool(manager.XMLTAG..".eventState#crisisHasPrice", false)
                settingsObject._savedCrisisHasLoan = xml:getBool(manager.XMLTAG..".eventState#crisisHasLoan", false)
                settingsObject._savedSettlement = RWESettlement ~= nil and RWESettlement.loadFromXML(xml, manager.XMLTAG..".eventState") or {}

                -- The savegame-coupled state as it stands on disk: re-written unchanged
                -- by every save that is not a real game save (see saveSettings).
                settingsObject._savedStateSnapshot = {
                    activeEvent = settingsObject._savedActiveEvent,
                    intensity = settingsObject._savedActiveIntensity,
                    remainingMs = settingsObject._savedRemainingMs,
                    cooldownRemainingMs = settingsObject._savedCooldownRemainingMs,
                    midpointFired = settingsObject._savedMidpointFired,
                    summaryKey = settingsObject._savedSummaryKey,
                    summaryArgs = summaryArgs,
                    crisisHasPrice = settingsObject._savedCrisisHasPrice,
                    crisisHasLoan = settingsObject._savedCrisisHasLoan,
                    settlement = RWESettlement ~= nil and RWESettlement.validateSaved(settingsObject._savedSettlement) or {},
                }

                xml:delete()
                return
            end
        end
        
        -- Use deep copy to avoid reference issues
        settingsObject.events   = {}
        settingsObject.debug    = {}
        settingsObject.physics  = {}
        settingsObject.hudScale = manager.defaultConfig.hudScale
        settingsObject.experimentalSystems = manager.defaultConfig.experimentalSystems

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
    
    manager.saveSettings = function(settingsObject, opts)
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
            xml:setBool(manager.XMLTAG..".events.arcadePhysics", settingsObject.events.arcadePhysics == true)
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

            xml:setBool(manager.XMLTAG..".experimentalSystems", settingsObject.experimentalSystems == true)

            -- EC-6: the event snapshot and the pending settlement lines are savegame-coupled
            -- state. Only a real game save (opts.savegame) writes the current state; every
            -- other write (a settings change, quitting) re-writes the snapshot of the last
            -- real save, or of load. Otherwise quitting without saving would persist lines
            -- the savegame never had (paid again on the next load) or drop lines it still
            -- owes.
            local snap
            if opts ~= nil and opts.savegame then
                snap = settingsObject:currentStateSnapshot()
                settingsObject._savedStateSnapshot = snap
            else
                snap = settingsObject._savedStateSnapshot or {}
            end

            -- Save active event state as remaining time so timers survive reload
            if snap.activeEvent ~= nil then
                xml:setString(manager.XMLTAG..".eventState.activeEvent", snap.activeEvent)
                xml:setFloat(manager.XMLTAG..".eventState.remainingMs", snap.remainingMs or 0)
                xml:setBool(manager.XMLTAG..".eventState.midpointFired", snap.midpointFired == true)
                xml:setInt(manager.XMLTAG..".eventState.intensity", snap.intensity or 0)
                xml:setString(manager.XMLTAG..".eventState#summaryKey", snap.summaryKey or "")
                for i, arg in ipairs(snap.summaryArgs or {}) do
                    xml:setString(string.format("%s.eventState.summaryArg(%d)#value", manager.XMLTAG, i - 1), tostring(arg))
                end
                xml:setBool(manager.XMLTAG..".eventState#crisisHasPrice", snap.crisisHasPrice == true)
                xml:setBool(manager.XMLTAG..".eventState#crisisHasLoan", snap.crisisHasLoan == true)
            else
                xml:setString(manager.XMLTAG..".eventState.activeEvent", "")
            end
            xml:setFloat(manager.XMLTAG..".eventState.cooldownRemainingMs", snap.cooldownRemainingMs or 0)
            if RWESettlement ~= nil then
                RWESettlement.saveListToXML(xml, manager.XMLTAG..".eventState", snap.settlement or {})
            end

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

--- @param opts table|nil  { savegame = true } only from the game's save cycle
function RandomWorldEvents:saveSettings(opts)
    if self.settingsManager and self.settingsManager.saveSettings then
        self.settingsManager.saveSettings(self, opts)
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
    addConsoleCommand("rweRelease", "Release gate: show STABLE vs experimental-LOCKED systems", "consoleCommandRelease", self)
    
    self:dbg("Console commands registered")
end

--- Release-gate opt-in. True when the player has explicitly enabled experimental
--- (LOCKED) systems. Orthogonal to difficulty: the two locks stack, see ReleaseGate.lua.
---@return boolean
function RandomWorldEvents:allowsExperimentalSystems()
    return self.experimentalSystems == true
end

--- Arcade-physics opt-in (redesign): the retained vehicle-physics events
--- (speed boost, engine trouble, equipment durability) only fire when this is
--- ON. Default OFF. Speed boost and engine trouble act on the host player's own
--- vehicle; the equipment durability pair scales usage wear on every vehicle in
--- use, decided on the server (Design d3c0626). Never the economy. Admin key
--- RandomWorldEvents.arcadePhysics.
---@return boolean
function RandomWorldEvents:allowsArcadePhysics()
    return self.events.arcadePhysics == true
end

-- =====================
-- DIFFICULTY (Option-Scaling Spine)
-- Difficulty rides the spine: the World-events dial scales event frequency
-- and base intensity; the Economy dial scales economic magnitude. When the
-- spine (or its profile) is absent every read is neutral, meaning RWE falls
-- back to its own configured frequency/intensity untouched.
-- =====================

--- Read the Option-Scaling Spine profile (if present) and resolve the two dials
--- RWE rides on. Neutral (nil) when the spine is absent or its profile is not
--- registered. Each factor is a multiplier around 1.0 (0.4 relaxed .. 1.7
--- punishing on the canonical World-events curve).
---@return table|nil  { worldEvents = number, economy = number }
function RandomWorldEvents:getDifficulty()
    if OptionScalingResolver == nil or OptionScalingResolver.readProfile == nil then
        return nil
    end
    local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
    local profile = OptionScalingResolver.readProfile(hub)
    if profile == nil then return nil end
    return {
        worldEvents = OptionScalingResolver.resolve({ dial = "worldEvents", base = 1.0, neutral = 1.0 }, profile),
        economy     = OptionScalingResolver.resolve({ dial = "economy",     base = 1.0, neutral = 1.0 }, profile),
    }
end

--- Difficulty factor for one dial (1.0 = neutral, spine absent or dial off).
---@param dial string  "worldEvents" or "economy"
---@return number
function RandomWorldEvents:getDifficultyFactor(dial)
    local d = self:getDifficulty()
    if d == nil or d[dial] == nil then return 1.0 end
    return d[dial]
end

--- Spine-scaled event frequency (1-10). Neutral when the spine is absent.
---@return number
function RandomWorldEvents:getEffectiveFrequency()
    local f = tonumber(self.events.frequency) or 5
    local scaled = f * self:getDifficultyFactor("worldEvents")
    return math.max(1, math.min(10, math.floor(scaled)))
end

--- Spine-scaled base intensity (1-5) used to trigger and scale events.
--- Neutral when the spine is absent.
---@return number
function RandomWorldEvents:getBaseIntensity()
    local i = tonumber(self.events.intensity) or 2
    local scaled = i * self:getDifficultyFactor("worldEvents")
    return math.max(1, math.min(5, math.floor(scaled)))
end

function RandomWorldEvents:consoleCommandRelease()
    if not ReleaseGate then return "Release gate not loaded" end
    return ReleaseGate.status(self.experimentalSystems == true)
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

-- =====================
-- COMPANION READ API
-- Read-only surface for companion mods (e.g. DairyCore) reached via
-- g_currentMission.randomWorldEvents. RWE runs at most one event at a time and
-- is server-authoritative; these read the server-side event state.
-- =====================

--- The currently active world event, or nil when none is active.
--- @return table|nil  A fresh copy: { name, intensity (1-5), category, remainingMs }.
function RandomWorldEvents:getActiveEvent()
    local es = self.EVENT_STATE
    if es == nil or es.activeEvent == nil then return nil end
    local now = g_currentMission and g_currentMission.time or 0
    return {
        name        = es.activeEvent,
        intensity   = es.activeIntensity or self.events.intensity or 1,
        category    = es.activeCategory,
        remainingMs = math.max(0, (es.eventStartTime + (es.eventDuration or 0)) - now),
    }
end

--- Intensity (1-5) of the currently active event, or 0 when none is active.
--- Falls back to the configured global intensity if an event is active but its
--- stored intensity is missing (e.g. a pre-upgrade save).
function RandomWorldEvents:getEventIntensity()
    local es = self.EVENT_STATE
    if es == nil or es.activeEvent == nil then return 0 end
    return es.activeIntensity or self.events.intensity or 1
end

--- True while a world event is active.
---@return boolean
function RandomWorldEvents:isEventActive()
    local es = self.EVENT_STATE
    return es ~= nil and es.activeEvent ~= nil
end

--- Progress through the active event (0.0 -> 1.0), or 0 when none is active.
---@return number
function RandomWorldEvents:getProgress()
    if not self:isEventActive() then return 0 end
    local s = self.EVENT_STATE
    if s.eventDuration == nil or s.eventDuration <= 0 then return 1 end
    local elapsed = (g_currentMission and g_currentMission.time or 0) - (s.eventStartTime or 0)
    return math.max(0, math.min(1, elapsed / s.eventDuration))
end

--- Seconds remaining in the active event, or 0 when none is active.
---@return number
function RandomWorldEvents:getRemainingTime()
    if not self:isEventActive() then return 0 end
    local s = self.EVENT_STATE
    if s.eventDuration == nil then return 0 end
    local now = g_currentMission and g_currentMission.time or 0
    local remainingMs = math.max(0, (s.eventStartTime or 0) + s.eventDuration - now)
    return math.floor(remainingMs / 1000)
end

--- Intensity (1-5) of the currently active event, or nil when none is active.
--- Neutral is nil (nothing active), matching the redesign read contract; use
--- getEventIntensity() if a numeric 0-when-inactive is preferred.
---@return number|nil
function RandomWorldEvents:getIntensity()
    local es = self.EVENT_STATE
    if es == nil or es.activeEvent == nil then return nil end
    return es.activeIntensity or self.events.intensity or 1
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

-- =====================
-- EC-6: ELIGIBILITY, NOTICES, SHARED STATE, END PATH
-- =====================

--- True for the four arcade-physics events (stored gate). Their notices, broadcast
--- and save-resume stay host-local; the durability pair's wear effect does not.
function RandomWorldEvents:isArcadeEvent(event)
    return type(event) == "table" and event.gate == "arcadePhysics"
end

--- The host player's current vehicle, or nil.
function RandomWorldEvents:getLocalVehicle()
    local player = g_localPlayer
    local cur = (player ~= nil and type(player.getCurrentVehicle) == "function") and player:getCurrentVehicle() or nil
    return cur or (g_currentMission ~= nil and g_currentMission.controlledVehicle) or nil
end

--- Speed boost and engine trouble are host-local: the toggle is on, this machine is
--- a listen server with a local player, and that player is in a vehicle. A
--- dedicated server (no local player) and a pure client never start one.
function RandomWorldEvents:arcadeEligible()
    return self:allowsArcadePhysics() and g_server ~= nil and g_localPlayer ~= nil and self:getLocalVehicle() ~= nil
end

--- The equipment durability pair (arcadeScope "server") scales usage wear on every
--- vehicle in use, which the server decides (Design d3c0626), so it needs only the
--- toggle and a server: a dedicated server with no local player starts one too.
function RandomWorldEvents:durabilityEligible()
    return self:allowsArcadePhysics() and g_server ~= nil
end

--- True for an arcade event whose effect the server decides for every vehicle.
function RandomWorldEvents:isServerScopedArcadeEvent(event)
    return self:isArcadeEvent(event) and event.arcadeScope == "server"
end

--- The same eligibility for the scheduler and for every forced trigger: the stored
--- gate and the event's own canTrigger (price status, the old-market exclusion,
--- eligible farms, map conditions). Returns ok, reason.
function RandomWorldEvents:eventEligibility(event)
    if type(event) ~= "table" then return false, "unknown event" end
    if self:isServerScopedArcadeEvent(event) then
        if not self:durabilityEligible() then
            return false, "equipment durability events need Arcade Physics on, on the server"
        end
    elseif self:isArcadeEvent(event) and not self:arcadeEligible() then
        return false, "arcade physics events need Arcade Physics on and the host player in a vehicle on a listen server"
    end
    local ok, can = pcall(event.canTrigger)
    if ok and can then return true end
    if RWEMarketBridge ~= nil then
        local status = RWEMarketBridge.priceStatus()
        if RWEMarketBridge.isOldMarketExcluded(event.name) then
            return false, "update MarketDynamics to enable this event (status " .. tostring(status) .. ")"
        end
        if RWEMarketBridge.isPriceEvent(event.name) and status ~= RWEMarketBridge.STATUS_AVAILABLE then
            return false, "market price events are unavailable (status " .. tostring(status) .. ")"
        end
    end
    return false, ok and "no eligible farm or map condition for this event" or ("canTrigger error: " .. tostring(can))
end

--- Resolve a notice to display text. A notice is { key = "...", args = { ... } } with
--- string arguments (each resolved as a translation key when one exists), or a
--- plain string (a translation key when one exists, else literal text from a
--- third-party event). A missing key falls back to the key itself and logs once.
function RandomWorldEvents:noticeText(notice)
    if notice == nil then return nil end
    local function t(key)
        if type(key) == "string" and g_i18n ~= nil and type(g_i18n.hasText) == "function" and g_i18n:hasText(key) then
            return g_i18n:getText(key)
        end
        return nil
    end
    if type(notice) == "string" then return t(notice) or notice end
    if type(notice) ~= "table" or type(notice.key) ~= "string" or notice.key == "" then return nil end
    local template = t(notice.key)
    if template == nil then
        self._missingKeys = self._missingKeys or {}
        if not self._missingKeys[notice.key] then
            self._missingKeys[notice.key] = true
            Logging.warning("[RWE] missing translation key '%s'", notice.key)
        end
        return notice.key
    end
    local args = {}
    for i, a in ipairs(notice.args or {}) do args[i] = t(a) or tostring(a) end
    if #args == 0 then return template end
    local ok, text = pcall(string.format, template, unpack(args))
    if ok then return text end
    return template
end

--- The translated title of an event: rwe_event_<name>_title, or the raw id (logged once).
function RandomWorldEvents:eventTitle(name)
    if name == nil then return "" end
    local key = "rwe_event_" .. tostring(name) .. "_title"
    if g_i18n ~= nil and type(g_i18n.hasText) == "function" and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    self._missingKeys = self._missingKeys or {}
    if not self._missingKeys[key] then
        self._missingKeys[key] = true
        Logging.warning("[RWE] missing translation key '%s'", key)
    end
    return tostring(name)
end

local function stringArgs(args)
    local out = {}
    for _, a in ipairs(type(args) == "table" and args or {}) do
        if type(a) == "string" then out[#out + 1] = a end
    end
    return out
end

--- Choose the active shared event's figure-free summary into eventData. Arcade
--- events get none. The crisis chooses its row from the recorded parts.
function RandomWorldEvents:chooseSummary(event)
    local d = self.EVENT_STATE.eventData
    if type(d) ~= "table" then d = {}; self.EVENT_STATE.eventData = d end
    d.summaryKey, d.summaryArgs = nil, {}
    if type(event) ~= "table" or self:isArcadeEvent(event) then return end
    if type(event.chooseSummary) == "function" then
        local ok, key, args = pcall(event.chooseSummary, d)
        if ok and type(key) == "string" then d.summaryKey, d.summaryArgs = key, stringArgs(args) end
    elseif type(event.summaryKey) == "string" then
        d.summaryKey = event.summaryKey
    end
end

--- The shared state every client sees. The only numbers are intensity and
--- remainingMs. While an arcade event holds the slot, the event is empty.
function RandomWorldEvents:sharedState()
    local es = self.EVENT_STATE
    local p = {
        activeEvent = "", activeIntensity = 0, activeCategory = "", remainingMs = 0, midpointFired = false,
        priceStatus = RWEMarketBridge ~= nil and RWEMarketBridge.priceStatus() or "",
        summaryKey = "", summaryArgs = {}, crisisHasPrice = false, crisisHasLoan = false,
        noticeKind = "", noticeKey = "", noticeArgs = {},
    }
    local event = es.activeEvent ~= nil and self.EVENTS[es.activeEvent] or nil
    if es.activeEvent ~= nil and not self:isArcadeEvent(event) then
        local now = g_currentMission ~= nil and g_currentMission.time or 0
        local d = type(es.eventData) == "table" and es.eventData or {}
        p.activeEvent = es.activeEvent
        p.activeIntensity = es.activeIntensity or 0
        p.activeCategory = es.activeCategory or ""
        p.remainingMs = math.max(0, (es.eventStartTime or 0) + (es.eventDuration or 0) - now)
        p.midpointFired = es.midpointFired == true
        p.summaryKey = d.summaryKey or ""
        p.summaryArgs = stringArgs(d.summaryArgs)
        if es.activeEvent == "economic_crisis" then
            p.crisisHasPrice = d.crisisHasPrice == true
            p.crisisHasLoan = d.crisisHasLoan == true
        end
    end
    return p
end

--- Attach a notice to a shared state payload (only a keyed notice travels).
local function withNotice(p, kind, notice)
    if type(notice) == "table" and type(notice.key) == "string" and notice.key ~= "" then
        p.noticeKind, p.noticeKey, p.noticeArgs = kind, notice.key, stringArgs(notice.args)
    elseif type(notice) == "string" and g_i18n ~= nil and type(g_i18n.hasText) == "function" and g_i18n:hasText(notice) then
        p.noticeKind, p.noticeKey, p.noticeArgs = kind, notice, {}
    end
    return p
end
RandomWorldEvents._withNotice = withNotice

--- Broadcast the shared state to every client. Server only.
function RandomWorldEvents:broadcastState(p)
    if g_server == nil or RWEEventStateEvent == nil then return false end
    local ok = pcall(RWEEventStateEvent.broadcast, p or self:sharedState())
    return ok
end

--- Client: apply the synced display copy. Never runs onEnd, onMid, tick handlers,
--- settlement or the price modifier.
function RandomWorldEvents:applySyncedState(p)
    if g_server ~= nil or type(p) ~= "table" then return end
    local es = self.EVENT_STATE
    if RWEMarketBridge ~= nil then
        RWEMarketBridge.clientPriceStatus = (p.priceStatus ~= nil and p.priceStatus ~= "") and p.priceStatus or nil
    end
    if p.activeEvent == nil or p.activeEvent == "" then
        es.activeEvent, es.activeIntensity, es.activeCategory = nil, nil, nil
        es.eventData = {}
        es.midpointFired = false
    else
        es.activeEvent     = p.activeEvent
        es.activeIntensity = (tonumber(p.activeIntensity) or 0) > 0 and p.activeIntensity or nil
        es.activeCategory  = (p.activeCategory ~= nil and p.activeCategory ~= "") and p.activeCategory or nil
        es.eventStartTime  = g_currentMission ~= nil and g_currentMission.time or 0
        es.eventDuration   = tonumber(p.remainingMs) or 0
        es.midpointFired   = p.midpointFired == true
        es.eventData = {
            summaryKey = (p.summaryKey ~= nil and p.summaryKey ~= "") and p.summaryKey or nil,
            summaryArgs = stringArgs(p.summaryArgs),
            crisisHasPrice = p.crisisHasPrice == true,
            crisisHasLoan = p.crisisHasLoan == true,
        }
    end
    if p.noticeKey ~= nil and p.noticeKey ~= "" then
        local positive = nil
        if p.noticeKind == "start" then positive = true elseif p.noticeKind == "mid" then positive = "warn" end
        local category = (p.activeCategory ~= nil and p.activeCategory ~= "") and p.activeCategory or nil
        self:notifyEvent(self:noticeText({ key = p.noticeKey, args = p.noticeArgs }), category, positive)
    end
end

--- The one server end path for every reason (timer, console, arcade toggle off,
--- price status). Clients never run it.
function RandomWorldEvents:_endActiveEvent(reason)
    if g_server == nil then return false end
    local es = self.EVENT_STATE
    local name = es.activeEvent
    if name == nil then return false end
    local event = self.EVENTS[name]
    local arcade = self:isArcadeEvent(event)
    local notice = nil
    if event ~= nil and type(event.onEnd) == "function" then
        local ok, result = pcall(event.onEnd)
        if ok then
            notice = result
        else
            Logging.warning("[RWE] onEnd failed for %s: %s", tostring(name), tostring(result))
        end
    end
    local category = es.activeCategory
    Logging.info("[RWE] Event ended: %s (%s)", tostring(name), tostring(reason))
    es.activeEvent          = nil
    es.activeIntensity      = nil
    es.activeCategory       = nil
    es.eventData            = {}
    es.customPriceModifiers = nil
    if notice ~= nil then
        self:notifyEvent(self:noticeText(notice), category, nil)
    end
    if not arcade then
        local p = withNotice(self:sharedState(), "end", notice)
        p.activeCategory = category or ""
        self:broadcastState(p)
    end
    return true
end

--- The live price-status rule (EC-6 3.7.7), called once per change by the watch:
--- (1) end or narrow the active event the same way roll and restore judge it,
--- (2) send the state, (3) ask a current MarketDynamics to recompose its quotes.
function RandomWorldEvents:onPriceStatusChanged(status)
    if g_server == nil or RWEMarketBridge == nil then return end
    local es = self.EVENT_STATE
    local name = es.activeEvent
    local available = status == RWEMarketBridge.STATUS_AVAILABLE
    local updateNeeded = status == RWEMarketBridge.STATUS_UPDATE_NEEDED
    local ended = false
    if name == "economic_crisis" then
        local d = type(es.eventData) == "table" and es.eventData or {}
        es.eventData = d
        if not available then d.crisisHasPrice = false end   -- never revived during the event
        if updateNeeded or d.crisisHasLoan ~= true then
            ended = self:_endActiveEvent("price_status")
        elseif not available then
            self:chooseSummary(self.EVENTS[name])
            es.ambientMsgIndex = 1
        end
    elseif name ~= nil then
        if (RWEMarketBridge.isPriceEvent(name) and not available)
           or (updateNeeded and RWEMarketBridge.OLD_READER_EXTRA[name] == true) then
            ended = self:_endActiveEvent("price_status")
        end
    end
    if not ended then
        self:broadcastState(self:sharedState())
    end
    if RWEMarketBridge.market == "current" then
        RWEMarketBridge.refresh()
    end
end

--- The savegame-coupled state as it stands now (written only by a real save).
function RandomWorldEvents:currentStateSnapshot()
    local es = self.EVENT_STATE
    local now = g_currentMission ~= nil and g_currentMission.time or 0
    local snap = {
        cooldownRemainingMs = math.max(0, (es.cooldownUntil or 0) - now),
        settlement = RWESettlement ~= nil and RWESettlement.serialize() or {},
    }
    if es.activeEvent ~= nil then
        local d = type(es.eventData) == "table" and es.eventData or {}
        snap.activeEvent = es.activeEvent
        snap.intensity = es.activeIntensity or 0
        snap.remainingMs = math.max(0, (es.eventStartTime or 0) + (es.eventDuration or 0) - now)
        snap.midpointFired = es.midpointFired == true
        snap.summaryKey = d.summaryKey
        snap.summaryArgs = stringArgs(d.summaryArgs)
        snap.crisisHasPrice = d.crisisHasPrice == true
        snap.crisisHasLoan = d.crisisHasLoan == true
    end
    return snap
end

function RandomWorldEvents:triggerRandomEvent()
    if g_server == nil then
        return false
    end
    if not self.events.enabled then
        self:dbg("triggerRandomEvent: events disabled")
        return false
    end

    if self.EVENT_STATE.activeEvent ~= nil then
        self:dbg("triggerRandomEvent: event already active: " .. tostring(self.EVENT_STATE.activeEvent))
        return false
    end

    local baseIntensity = self:getBaseIntensity()
    local available = {}
    local ids = {}
    for eventId in pairs(self.EVENTS) do ids[#ids + 1] = eventId end
    table.sort(ids)
    for _, eventId in ipairs(ids) do
        local event = self.EVENTS[eventId]
        local categoryKey = event.category .. "Events"
        local categoryEnabled = self.events[categoryKey]
        local intensityOk = baseIntensity >= (event.minIntensity or 1)
        -- EC-6: the stored gate and the event's own canTrigger, the same check a
        -- forced trigger applies.
        local eligible = self:eventEligibility(event)

        if categoryEnabled and intensityOk and eligible then
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
    self:_activateEvent(event, self:getBaseIntensity())
    return true
end

--- Trigger a specific named event at a given intensity (1-5).
--- Used by subsystem API triggerEvent calls so all lifecycle hooks fire correctly.
--- Returns the onStart message string, or an error string if activation failed.
---@param name string  event key in self.EVENTS
---@param intensity number  1-5
---@return string
function RandomWorldEvents:triggerNamedEvent(name, intensity)
    if g_server == nil then
        return "[RWE] Not triggered: events start on the server only"
    end
    if self.EVENT_STATE.activeEvent ~= nil then
        return "[RWE] Another event is already active: " .. tostring(self.EVENT_STATE.activeEvent)
    end
    local event = self.EVENTS[name]
    if not event then
        return "[RWE] Event not found: " .. tostring(name)
    end
    -- EC-6: a forced event may bypass probability and cooldown only, never price
    -- status, the old-market exclusion, eligible farms or arcade eligibility.
    local eligible, why = self:eventEligibility(event)
    if not eligible then
        return "[RWE] Not triggered: " .. tostring(name) .. ": " .. tostring(why)
    end
    local safeIntensity = math.max(1, math.min(5, math.floor(intensity or 1)))
    local msg = self:_activateEvent(event, safeIntensity)
    self:dbg(string.format("triggerNamedEvent: '%s' at intensity %d", name, safeIntensity))
    return msg or ("Triggered: " .. name)
end

--- Internal: write EVENT_STATE for a new event and fire onStart + opening notify.
--- EC-6: resets eventData and the custom price terms, chooses the figure-free
--- summary, shows the start notice here and sends the shared state (never for an
--- arcade event, which is host-local). Returns the start notice text (may be nil).
---@param event table   event definition from self.EVENTS
---@param intensity number  1-5
---@return string|nil
function RandomWorldEvents:_activateEvent(event, intensity)
    local duration = 0
    if type(event.duration) == "table" then
        duration = math.random(event.duration.min, event.duration.max) * 60000
    end

    self.EVENT_STATE.eventData            = {}
    self.EVENT_STATE.customPriceModifiers = nil
    self.EVENT_STATE.activeEvent     = event.name
    self.EVENT_STATE.activeIntensity = intensity
    self.EVENT_STATE.activeCategory  = event.category
    self.EVENT_STATE.eventStartTime  = g_currentMission.time
    self.EVENT_STATE.eventDuration   = duration

    -- Reset per-event immersion state
    self.EVENT_STATE.midpointFired   = false
    self.EVENT_STATE.ambientMsgIndex = 1
    -- First ambient message fires after 10% of the event duration (min 60 s)
    local firstAmbientDelay = math.max(60000, duration * 0.10)
    self.EVENT_STATE.nextAmbientTime = g_currentMission.time + firstAmbientDelay

    Logging.info(string.format("[RWE] Event activated: %s (intensity=%d, duration=%.1f min)",
        event.name, intensity, duration / 60000))

    local notice = event.onStart(intensity)
    self:chooseSummary(event)
    local text = self:noticeText(notice)
    self:notifyEvent(text, event.category, true)
    if not self:isArcadeEvent(event) then
        self:broadcastState(withNotice(self:sharedState(), "start", notice))
    end
    return text
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
--
-- The terrain "traction governor" and all event-driven vehicle physics
-- now live in the RWEVehiclePhysics vehicle specialization
-- (utils/VehiclePhysics.lua), which only touches real engine fields.
-- The old per-frame updatePhysics() here wrote to non-existent fields
-- (wheel.physics.frictionScale / wheel.suspension.springForce) and has
-- been removed. The core keeps only an optional debug readout below.

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

    -- EC-6 client gate, unconditional: a client displays the synced state only. It
    -- never runs the scheduler, tick handlers, notices of its own, an end, settlement
    -- or the price modifier, whatever its own events-enabled setting says. The display
    -- copy ends only when the server's end state arrives.
    if g_server == nil then return end

    -- Restored settlement lines bind to their Farm objects once the farms exist.
    if RWESettlement ~= nil then RWESettlement.bindRestored() end

    -- The price-status watch runs every update, whether or not an event is active
    -- or events are enabled. An unchanged read does nothing.
    if RWEMarketBridge ~= nil then RWEMarketBridge.watch(self) end

    -- Switching Arcade Physics off ends an active arcade event at once.
    local activeDef = self.EVENT_STATE.activeEvent ~= nil and self.EVENTS[self.EVENT_STATE.activeEvent] or nil
    if activeDef ~= nil and self:isArcadeEvent(activeDef) and not self:allowsArcadePhysics() then
        self:_endActiveEvent("arcade_physics_off")
    end

    -- Event system update
    if self.events.enabled then
        if g_currentMission.time > (self.EVENT_STATE.cooldownUntil or 0) then
            local chance = self:getEffectiveFrequency() * 0.001
            local roll = math.random()
            if roll <= chance then
                self:dbg(string.format("roll %.4f <= chance %.4f — attempting trigger", roll, chance), 2)
                local triggered = self:triggerRandomEvent()
                local cooldownMs = self.events.cooldown * 60000
                local frequencyFactor = (11 - self.events.frequency) / 10
                if triggered then
                    self.EVENT_STATE.cooldownUntil = g_currentMission.time + (cooldownMs * frequencyFactor)
                    self:dbg(string.format("cooldown set: %.1f min", (cooldownMs * frequencyFactor) / 60000), 2)
                end
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

        if self.EVENT_STATE.activeEvent ~= nil
           and g_currentMission.time > (self.EVENT_STATE.eventStartTime + (self.EVENT_STATE.eventDuration or 0)) then
            self:_endActiveEvent("timer")
        end
    end
    
    -- Optional debug telemetry only. Real physics is applied per-vehicle by
    -- the RWEVehiclePhysics specialization, not from this loop.
    if self.physics.showPhysicsInfo and PhysicsUtils and PhysicsUtils.showPhysicsInfo then
        local vehicle = g_currentMission.controlledVehicle
        if vehicle then
            PhysicsUtils:showPhysicsInfo(vehicle)
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
        local notice = nil
        if event.onMid then
            -- Midpoint narrative must mirror the intensity the event was
            -- actually activated at (spine-scaled), not the raw setting.
            local midIntensity = s.activeIntensity or self:getBaseIntensity()
            local ok, msg = pcall(event.onMid, midIntensity)
            if ok and msg then
                notice = msg
                self:notifyEvent(self:noticeText(msg), event.category, "warn")
                self:dbg("Midpoint fired for: " .. s.activeEvent)
            end
        end
        -- EC-6: joined players see the midpoint too; an arcade event stays host-local.
        if not self:isArcadeEvent(event) then
            self:broadcastState(withNotice(self:sharedState(), "mid", notice))
        end
    end

    -- ── Ambient flavor messages ───────────────────────────────────────────
    -- Cycles through event.ambientMsgs on a timer.
    -- Interval: 15 % of duration (min 90 s, max 5 min) so messages feel
    -- proportional regardless of whether an event lasts 10 or 90 minutes.
    -- EC-6: an event with ambientVariants (the crisis) picks its list at each tick
    -- from the recorded parts, never saved: both, price-only or loan-only. Ambients
    -- stay host-local flavour and are never sent.
    local msgs = event.ambientMsgs
    if type(event.ambientVariants) == "table" then
        local d = type(s.eventData) == "table" and s.eventData or {}
        local variant = nil
        if d.crisisHasPrice == true and d.crisisHasLoan == true then variant = "both"
        elseif d.crisisHasPrice == true then variant = "price"
        elseif d.crisisHasLoan == true then variant = "loan" end
        msgs = variant ~= nil and event.ambientVariants[variant] or nil
    end
    if msgs and #msgs > 0 and now >= s.nextAmbientTime then
        local idx   = ((s.ambientMsgIndex - 1) % #msgs) + 1
        local msg   = msgs[idx]
        s.ambientMsgIndex = idx + 1

        -- Ambient messages use nil isPositive → INGAME_NOTIFICATION_INFO
        if msg then
            self:notifyEvent(self:noticeText(msg), event.category, nil)
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
    print("rweSettings  - Open settings screen (or the RWE_TOGGLE_SETTINGS key you assigned in Controls)")
    print("rweDebug on|off - Toggle debug mode")
    print("rweList [category] - List registered events")
    print("================================")
    return "Random World Events commands listed above"
end

function RandomWorldEvents:consoleCommandStatus()
    local status = string.format(
        "=== RWE Status ===\n" ..
        "Events enabled: %s\n" ..
        "Frequency: %d/10 (spine %d)\n" ..
        "Intensity: %d/5 (spine %d)\n" ..
        "Active event: %s\n" ..
        "Cooldown active: %s\n" ..
        "Arcade physics: %s\n" ..
        "Physics enabled: %s\n" ..
        "Market price events: %s (MarketDynamics %s)\n" ..
        "=========================",
        tostring(self.events.enabled),
        self.events.frequency or 5,
        self:getEffectiveFrequency(),
        self.events.intensity or 2,
        self:getBaseIntensity(),
        self.EVENT_STATE.activeEvent or "None",
        tostring(g_currentMission.time < self.EVENT_STATE.cooldownUntil),
        tostring(self:allowsArcadePhysics()),
        tostring(self.physics.enabled),
        tostring(RWEMarketBridge ~= nil and RWEMarketBridge.displayStatus() or "unknown"),
        tostring(RWEMarketBridge ~= nil and RWEMarketBridge.market or "unknown")
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
    if g_server == nil then
        return "Events end on the server only"
    end
    if not self.EVENT_STATE.activeEvent then
        return "No active event to end"
    end
    self:_endActiveEvent("console")
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

-- RSF-F201 input record and expected sets. `rweManager` is the owner; the
-- handlers are resolved on it by name at call time.
local function rweInputRecord()
    return RWEContextInput.record(RWE_InputHookRecord, "input")
end

local function rweOwnsHudKeys() return not __rfMhOwnsHudKeys() end
local function rweHideRow(binding, eventId) binding:setActionEventTextVisibility(eventId, false) end
local function rweLabel(key, fallback)
    return function(binding, eventId)
        binding:setActionEventText(eventId, g_i18n:getText(key) or fallback)
    end
end
local rweLabelHud  = rweLabel("input_RWE_TOGGLE_HUD", "Toggle RWE HUD")
local rweLabelDrag = rweLabel("input_RWE_HUD_DRAG", "RWE HUD Edit Mode")
local function rweSettingsPlayerAfter(binding, eventId, owner)
    binding:setActionEventText(eventId, g_i18n:getText("input_RWE_TOGGLE_SETTINGS") or "RWE Settings")
    -- Cache key hint for the settings panel close button (unchanged behaviour).
    local ok, ktext = pcall(function()
        return g_inputBinding:getActionDisplayName(InputAction.RWE_TOGGLE_SETTINGS)
    end)
    owner.settingsKeyHint = (ok and ktext and ktext ~= "") and ktext or "Shift+O"
end

local RWE_PLAYER_SPECS = {
    { action = "RWE_TOGGLE_HUD", handler = "onToggleHUDInput", idField = "hudPlayerEventId",
      present = rweOwnsHudKeys, after = rweLabelHud, up = false, down = true, always = false, startActive = true },
    { action = "RWE_TOGGLE_SETTINGS", handler = "onToggleSettingsInput", idField = "settingsPlayerEventId",
      after = rweSettingsPlayerAfter, up = false, down = true, always = false, startActive = true },
    { action = "RWE_HUD_DRAG", handler = "onHUDDragInput", idField = "hudDragPlayerEventId",
      present = rweOwnsHudKeys, after = rweLabelDrag, up = false, down = true, always = false, startActive = true },
}
local RWE_VEHICLE_SPECS = {
    { action = "RWE_TOGGLE_HUD", handler = "onToggleHUDInput", idField = "hudVehicleEventId",
      present = rweOwnsHudKeys, after = rweLabelHud, up = false, down = true, always = false, startActive = true },
    { action = "RWE_TOGGLE_SETTINGS", handler = "onToggleSettingsInput", idField = "settingsVehicleEventId",
      after = rweHideRow, up = false, down = true, always = false, startActive = true },
    { action = "RWE_HUD_DRAG", handler = "onHUDDragInput", idField = "hudDragVehicleEventId",
      present = rweOwnsHudKeys, after = rweHideRow, up = false, down = true, always = false, startActive = true },
}


local function update(mission, dt)
    -- RSF-F201: admission reset is the first input act of every update interval.
    RWEContextInput.resetAdmission(rweInputRecord())
    if rweManager and rweManager.isInitialized then
        rweManager:update(dt)
    end
end

local function delete(mission)
    if rweManager then
        -- RSF-F201: retire the input owner before teardown. Old forwarding targets
        -- go inert and the owner reference is released. The captured predecessors
        -- are NOT restored: restoring per mission can remove a later mod's wrapper.
        RWEContextInput.retire(rweInputRecord())

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
        -- EC-6 delete-path order: unregister the price modifier (when live), then the
        -- settlement accrual, the day subscription and the farm-deleted subscription,
        -- then clear the manager.
        if RWEMarketBridge then RWEMarketBridge.unbind() end
        if RWESettlement then RWESettlement.uninstall() end
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
    -- 2026-08-22 (Wizard): MasterHUD takeover. When MasterHUD is installed it owns the
    -- suite-wide hide/move binds, so this mod's own per-mod key is deliberately inert:
    -- one surface, one way to reach it. Standalone (no MasterHUD) this runs normally.
    -- Canonical presence check, the same expression the suite's MasterHUD bridges use.
    if ((g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD) ~= nil then
        return
    end
    if self.eventHUD then
        self.eventHUD:toggleVisibility()
    end
end

function RandomWorldEvents:onToggleSettingsInput()
    if self.settingsPanel then
        self.settingsPanel:toggle()
    end
end

function RandomWorldEvents:onHUDDragInput()
    -- 2026-08-22 (Wizard): MasterHUD takeover. When MasterHUD is installed it owns the
    -- suite-wide hide/move binds, so this mod's own per-mod key is deliberately inert:
    -- one surface, one way to reach it. Standalone (no MasterHUD) this runs normally.
    -- Canonical presence check, the same expression the suite's MasterHUD bridges use.
    if ((g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD) ~= nil then
        return
    end
    if not self.eventHUD then return end
    if not self.eventHUD.visible then return end
    if self.eventHUD.editMode then
        self.eventHUD:exitEditMode()
    else
        self.eventHUD:enterEditMode()
    end
end

-- =====================
-- INPUT REGISTRATION (RSF-F201 context-qualified)
--   PLAYER context  -> wrap PlayerInputComponent.registerActionEvents
--   VEHICLE context -> hook InputBinding.endActionEventsModification
-- FSBaseMission.registerActionEvents targets the base class and never fires in FS25.
--
-- Each context registers through its own private forwarding target. The engine
-- keys an event by action, target and trigger shape only, so the old shared
-- `mgr` target made PLAYER and VEHICLE one global slot; the old vehicle hook's
-- "skip when all three cab ids are set" early return then skipped registrations
-- the rebuilt context needed (ids stay non-nil after the engine destroys the
-- context). Membership is now asked of the wrap's own context by walking the
-- native lists, so nothing is inferred from a stored id and a complete set
-- costs no transaction. The old "never clear PLAYER ids" workaround is plain
-- scoping now: PLAYER and VEHICLE handles cannot alias.
--
-- The hook record lives on RWE_InputHookRecord (declared near the settings
-- literal above), not on this settings table and not on the mission-scoped
-- manager, and the captured predecessors are never restored per mission.
-- =====================

installInputHooks = function()
    if not rweManager then return end
    -- Client-only: a dedicated server has no local input. Install once per loaded
    -- script environment; the helper latches on its captured predecessors.
    local mission = rweManager.mission or g_currentMission
    if mission == nil or (mission.getIsClient ~= nil and not mission:getIsClient()) then return end
    local record = rweInputRecord()
    if record.playerOriginal == nil and RWEContextInput.installPlayerWrapper(record, RWE_PLAYER_SPECS) then
        Logging.info("[RWE] PlayerInputComponent hook installed")
    end
    if record.vehicleOriginal == nil and RWEContextInput.installVehicleWrapper(record, RWE_VEHICLE_SPECS) then
        Logging.info("[RWE] InputBinding.endActionEventsModification hooked for VEHICLE context")
    end
    if PlayerInputComponent == nil or Vehicle == nil then return end
    -- Bind the current manager as input owner of this mission and mint fresh
    -- per-context forwarding targets. A stacked reload copy adopts the binding.
    RWEContextInput.activate(record, rweManager, mission, {
        [PlayerInputComponent.INPUT_CONTEXT_NAME] = RWE_PLAYER_SPECS,
        [Vehicle.INPUT_CONTEXT_NAME]              = RWE_VEHICLE_SPECS,
    })
end

local function draw(mission)
    -- When MasterHUD is present it drives RWEMasterHUDBridge.drawStack in its own
    -- suspend-aware loop, so this fallback hook stands down to avoid a double draw.
    -- The draw body lives in drawStack so the two paths can never diverge.
    if RWEMasterHUDBridge and RWEMasterHUDBridge.active then return end
    if RWEMasterHUDBridge then
        RWEMasterHUDBridge.drawStack()
    elseif rweManager then
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

        -- RSF-F201 post-load catch-up. PlayerInputComponent.registerActionEvents may
        -- have fired during mission loading before installInputHooks() wrapped it.
        -- One complete PLAYER reconciliation (HUD toggle, settings, drag when
        -- locally owned) if the local owning player and the native PLAYER context
        -- already exist; no context and no timer are created. The old body here
        -- registered HUD and settings only and skipped drag.
        RWEContextInput.catchUpPlayer(rweInputRecord(), RWE_PLAYER_SPECS)

        -- ── Bedrock core-API bridges (delegate-when-present) ──────────────────
        -- Register with the shared ecosystem engines when they are installed.
        -- Each no-ops safely when its engine is absent, leaving RWE's own path
        -- (own XML, own draw hook) unchanged. StateLedger, when present, is the
        -- load source of truth for the active-event snapshot: applyState overwrites
        -- the _saved* fields imported from the own XML, and the restore block just
        -- below then reconstructs EVENT_STATE from them (single restore path).
        if RWESettingsHubBridge then RWESettingsHubBridge.register(rweManager) end
        if RWEMasterHUDBridge   then RWEMasterHUDBridge.register(rweManager)   end
        -- EC-6: bind MarketDynamics and install the settlement doors before the
        -- restore block, so restore reads the real market kind. MarketDynamics
        -- publishes its handle earlier, at its own Mission00.load.
        if g_server ~= nil then
            if RWEMarketBridge then RWEMarketBridge.bind() end
            if RWESettlement then RWESettlement.install() end
        end
        if RWEStateLedgerBridge then
            RWEStateLedgerBridge.register(rweManager)
            if RWEStateLedgerBridge.hasState() then
                RWEStateLedgerBridge.applyState(rweManager)
            end
        end

        -- Restore active event state saved before this session ended.
        if g_server ~= nil and g_RandomWorldEvents ~= nil then
            g_RandomWorldEvents:restoreFromSave()
        end
    end
end

--- EC-6 restore (brief 3.7.3-3.7.6). g_currentMission.time is valid here; the
--- saved snapshot uses remaining-time offsets. Pending settlement lines are
--- restored untouched (bound to farms at the first server update). The price
--- status is seeded whether or not an event is restored. An arcade event, an
--- unknown or retired event, a price event without an available market and an
--- event an older MarketDynamics would price are not resumed. A crisis follows
--- its saved parts, never current loans.
function RandomWorldEvents:restoreFromSave()
    local es = self.EVENT_STATE
    if RWESettlement ~= nil then
        RWESettlement.restore(self._savedSettlement)
    end
    self._savedSettlement = nil

    local status = RWEMarketBridge ~= nil and RWEMarketBridge.seed() or "no_market"
    local AVAILABLE = RWEMarketBridge ~= nil and RWEMarketBridge.STATUS_AVAILABLE or "available"
    local UPDATE_NEEDED = RWEMarketBridge ~= nil and RWEMarketBridge.STATUS_UPDATE_NEEDED or "market_update_needed"

    local savedName = self._savedActiveEvent
    if savedName ~= nil then
        local savedEvent = self.EVENTS[savedName]
        local restore, why = true, nil
        if savedEvent == nil then
            restore, why = false, "no such event (retired or from another mod)"
        elseif self:isArcadeEvent(savedEvent) then
            restore, why = false, "arcade events are host-local and never resume"
        elseif savedName == "economic_crisis" then
            local hasLoan, hasPrice = self._savedCrisisHasLoan == true, self._savedCrisisHasPrice == true
            if status == UPDATE_NEEDED then
                restore, why = false, "MarketDynamics needs an update"
            elseif not (hasLoan or (hasPrice and status == AVAILABLE)) then
                restore, why = false, "no crisis part it can still deliver"
            end
        elseif RWEMarketBridge ~= nil and RWEMarketBridge.isPriceEvent(savedName) and status ~= AVAILABLE then
            restore, why = false, "market price events are unavailable (" .. tostring(status) .. ")"
        elseif status == UPDATE_NEEDED and RWEMarketBridge ~= nil and RWEMarketBridge.OLD_READER_EXTRA[savedName] == true then
            restore, why = false, "MarketDynamics needs an update"
        end

        if restore then
            es.activeEvent          = savedName
            es.activeIntensity      = (self._savedActiveIntensity and self._savedActiveIntensity > 0) and self._savedActiveIntensity or nil
            es.activeCategory       = savedEvent.category
            es.eventStartTime       = g_currentMission.time
            es.eventDuration        = self._savedRemainingMs or 0
            es.midpointFired        = self._savedMidpointFired or false
            es.cooldownUntil        = g_currentMission.time + (self._savedCooldownRemainingMs or 0)
            es.customPriceModifiers = nil
            es.eventData            = {}
            if savedName == "economic_crisis" then
                es.eventData.crisisHasLoan  = self._savedCrisisHasLoan == true
                es.eventData.crisisHasPrice = self._savedCrisisHasPrice == true and status == AVAILABLE
                self:chooseSummary(savedEvent)
            elseif self._savedSummaryKey ~= nil then
                es.eventData.summaryKey  = self._savedSummaryKey
                es.eventData.summaryArgs = stringArgs(self._savedSummaryArgs)
            else
                self:chooseSummary(savedEvent)
            end
            if type(savedEvent.applyFlags) == "function" then
                local ok, err = pcall(savedEvent.applyFlags, es.activeIntensity or self.events.intensity or 1)
                if not ok then Logging.warning("[RWE] applyFlags failed on restore for %s: %s", tostring(savedName), tostring(err)) end
            end
            Logging.info("[RWE] Resumed active event from save: " .. tostring(savedName))
            self:broadcastState(self:sharedState())
        else
            Logging.info("[RWE] Not resuming saved event %s: %s", tostring(savedName), tostring(why))
        end
    end

    self._savedActiveEvent         = nil
    self._savedActiveIntensity     = nil
    self._savedRemainingMs         = nil
    self._savedCooldownRemainingMs = nil
    self._savedMidpointFired       = nil
    self._savedSummaryKey          = nil
    self._savedSummaryArgs         = nil
    self._savedCrisisHasPrice      = nil
    self._savedCrisisHasLoan       = nil
end

-- Hook into FS25
Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadFinished)

-- ---------------------------------------------------------
-- Realistic Farming Control Center: publish a runnable delegate.
--
-- MasterHUD owns the physical suite HUD keys, so the per-mod hide/move keys stay
-- gated (no native binding). RWE_TOGGLE_HUD is surfaced here instead as a Control
-- Center delegate: the # key hides the whole suite at once, this button hides or
-- shows only the RWE event HUD, so a player can disable just this mod. RWE_HUD_DRAG
-- stays a directory row only - moving the panel needs the in-world drag, not a
-- dialog button.
-- ---------------------------------------------------------
local function registerControlCenterActions()
    local registry = g_currentMission ~= nil and g_currentMission.rfActionRegistry or nil
    if registry == nil then return end

    registry.registerAction({
        action     = "RWE_TOGGLE_SETTINGS",
        button     = "Open",
        -- The settings panel draws on the HUD, so the dialog steps aside.
        closeFirst = true,
        run = function()
            local mgr = g_RandomWorldEvents
            if mgr ~= nil and mgr.onToggleSettingsInput ~= nil then
                mgr:onToggleSettingsInput()
            end
        end,
    })

    -- Per-mod HUD hide/show. Calls the HUD directly rather than onToggleHUDInput,
    -- which deliberately stands down while MasterHUD owns the physical key. The
    -- draw path honours self.visible under both MasterHUD and standalone, so the
    -- panel actually appears/disappears; it composes with the suite-wide # hide.
    registry.registerAction({
        action = "RWE_TOGGLE_HUD",
        -- Live caption: reflects the panel's current state so the row reads "Hide"
        -- when shown and "Show" when hidden, flipping in place on each click.
        button = function()
            local hud = g_RandomWorldEvents ~= nil and g_RandomWorldEvents.eventHUD or nil
            return (hud ~= nil and hud.visible) and "Hide" or "Show"
        end,
        run = function()
            local hud = g_RandomWorldEvents ~= nil and g_RandomWorldEvents.eventHUD or nil
            if hud ~= nil and hud.toggleVisibility ~= nil then
                hud:toggleVisibility()
                return hud.visible and "RWE HUD shown" or "RWE HUD hidden"
            end
        end,
    })
end

Mission00.loadMission00Finished = Utils.appendedFunction(
    Mission00.loadMission00Finished, registerControlCenterActions)
FSBaseMission.update     = Utils.appendedFunction(FSBaseMission.update,     update)
FSBaseMission.draw       = Utils.appendedFunction(FSBaseMission.draw,       draw)
FSBaseMission.mouseEvent = Utils.prependedFunction(FSBaseMission.mouseEvent, mouseEvent)
FSBaseMission.delete     = Utils.appendedFunction(FSBaseMission.delete,     delete)

-- Persist RWE state (settings + active-event snapshot) on the game's save cycle.
-- Without this, saveSettings only ran on settings changes and on shutdown, so an
-- in-game save (or a crash after one) could lose the active event. The server owns
-- the savegame, so this runs server-only.
if FSCareerMissionInfo and FSCareerMissionInfo.saveToXMLFile then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
        FSCareerMissionInfo.saveToXMLFile,
        function(missionInfo)
            if rweManager and g_currentMission and g_currentMission:getIsServer() then
                -- The only write of the current event and settlement state (EC-6).
                rweManager:saveSettings({ savegame = true })
            end
        end
    )
    Logging.info("[RandomWorldEvents] Save hook installed on FSCareerMissionInfo:saveToXMLFile")
end

-- EC-6: a joining connection receives the full shared state, summary included, so
-- its HUD shows the same event as everyone else without having seen the start notice.
if FSBaseMission ~= nil and FSBaseMission.sendInitialClientState ~= nil then
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(
        FSBaseMission.sendInitialClientState,
        function(mission, connection, user, farm)
            if rweManager ~= nil and g_server ~= nil and RWEEventStateEvent ~= nil and connection ~= nil then
                pcall(RWEEventStateEvent.sendTo, connection, rweManager:sharedState())
            end
        end
    )
end

Logging.info("========================================")
Logging.info("   FS25 Random World Events v" .. modVersion .. "   ")
Logging.info("           Successfully Loaded          ")
Logging.info("     Type 'rwe' in console for help     ")
Logging.info("========================================")

return RandomWorldEvents