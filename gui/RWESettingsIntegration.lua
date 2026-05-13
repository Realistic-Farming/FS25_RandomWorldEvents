-- =========================================================
-- Random World Events - Settings Integration
-- =========================================================
-- Adds RWE settings to ESC > Settings > Game Settings page.
-- Pattern: FS25_NPCFavor NPCSettingsIntegration
--
-- Layout (grouped under "Random World Events" header):
--   Enable Events
--   — Event Timing —      Frequency, Intensity, Cooldown
--   — Notifications & HUD — Show Notifications, Show Warnings,
--                           Show HUD Panel, HUD Scale
--   — Event Categories — Economic, Vehicle, Field, Wildlife, Special
--   — Physics Override — Enable Physics, Wheel Grip, Suspension
--   — Debug —           Show Physics Info, Debug Mode
-- =========================================================
-- Author: TisonK
-- =========================================================

RWESettingsIntegration = {}
RWESettingsIntegration_mt = Class(RWESettingsIntegration)

-- Dropdown option tables
RWESettingsIntegration.frequencyOptions = {"1","2","3","4","5","6","7","8","9","10"}
RWESettingsIntegration.frequencyValues  = {1,2,3,4,5,6,7,8,9,10}

RWESettingsIntegration.intensityOptions = {"1","2","3","4","5"}
RWESettingsIntegration.intensityValues  = {1,2,3,4,5}

RWESettingsIntegration.cooldownOptions  = {"5 min","10 min","15 min","30 min","60 min","120 min","240 min"}
RWESettingsIntegration.cooldownValues   = {5,10,15,30,60,120,240}

RWESettingsIntegration.hudScaleOptions  = {"0.6x","0.8x","1.0x","1.2x","1.5x","1.8x"}
RWESettingsIntegration.hudScaleValues   = {0.6,0.8,1.0,1.2,1.5,1.8}

RWESettingsIntegration.physicsMultOptions = {"0.50x","0.75x","1.00x","1.25x","1.50x","2.00x"}
RWESettingsIntegration.physicsMultValues  = {0.50,0.75,1.00,1.25,1.50,2.00}

-- =========================================================
-- Hook: called when ESC > Settings frame opens
-- =========================================================

function RWESettingsIntegration:onFrameOpen()
    -- 'self' is the InGameMenuSettingsFrame instance.
    if not self.rwe_initDone then
        RWESettingsIntegration:addSettingsElements(self)

        self.gameSettingsLayout:invalidateLayout()

        if self.updateAlternatingElements then
            self:updateAlternatingElements(self.gameSettingsLayout)
        end
        if self.updateGeneralSettings then
            self:updateGeneralSettings(self.gameSettingsLayout)
        end

        self.rwe_initDone = true
        Logging.info("[RWE] Settings controls added to InGameMenuSettingsFrame")
    end

    RWESettingsIntegration:updateSettingsUI(self)
end

-- =========================================================
-- Add all settings elements
-- =========================================================

function RWESettingsIntegration:addSettingsElements(frame)
    -- ── Main header ───────────────────────────────────────
    RWESettingsIntegration:addSectionHeader(frame,
        g_i18n:getText("rwe_section") or "Random World Events"
    )

    frame.rwe_eventsEnabled = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEEventsEnabledChanged",
        g_i18n:getText("rwe_events_enabled_short") or "Enable Events",
        g_i18n:getText("rwe_events_enabled_long")  or "Enable or disable all random events"
    )

    -- ── Event Timing ──────────────────────────────────────
    RWESettingsIntegration:addSubHeader(frame,
        g_i18n:getText("rwe_subheader_timing") or "Event Timing"
    )

    frame.rwe_frequency = RWESettingsIntegration:addMultiTextOption(
        frame, "onRWEFrequencyChanged",
        RWESettingsIntegration.frequencyOptions,
        g_i18n:getText("rwe_frequency_short") or "Frequency",
        g_i18n:getText("rwe_frequency_long")  or "How often events fire (1 = rare, 10 = frequent)"
    )

    frame.rwe_intensity = RWESettingsIntegration:addMultiTextOption(
        frame, "onRWEIntensityChanged",
        RWESettingsIntegration.intensityOptions,
        g_i18n:getText("rwe_intensity_short") or "Intensity",
        g_i18n:getText("rwe_intensity_long")  or "Strength of event effects (1 = mild, 5 = extreme)"
    )

    frame.rwe_cooldown = RWESettingsIntegration:addMultiTextOption(
        frame, "onRWECooldownChanged",
        RWESettingsIntegration.cooldownOptions,
        g_i18n:getText("rwe_cooldown_short") or "Cooldown",
        g_i18n:getText("rwe_cooldown_long")  or "Minimum in-game time between events"
    )

    -- ── Notifications & HUD ───────────────────────────────
    RWESettingsIntegration:addSubHeader(frame,
        g_i18n:getText("rwe_subheader_hud") or "Notifications & HUD"
    )

    frame.rwe_notifications = RWESettingsIntegration:addBinaryOption(
        frame, "onRWENotificationsChanged",
        g_i18n:getText("rwe_notifications_short") or "Show Notifications",
        g_i18n:getText("rwe_notifications_long")  or "Display event notifications on screen"
    )

    frame.rwe_warnings = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEWarningsChanged",
        g_i18n:getText("rwe_warnings_short") or "Show Warnings",
        g_i18n:getText("rwe_warnings_long")  or "Show event warning messages"
    )

    frame.rwe_showHUD = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEShowHUDChanged",
        g_i18n:getText("rwe_show_hud_short") or "Show HUD Panel",
        g_i18n:getText("rwe_show_hud_long")  or "Show the World Events HUD overlay (F3 to toggle in-game)"
    )

    frame.rwe_hudScale = RWESettingsIntegration:addMultiTextOption(
        frame, "onRWEHudScaleChanged",
        RWESettingsIntegration.hudScaleOptions,
        g_i18n:getText("rwe_hud_scale_short") or "HUD Scale",
        g_i18n:getText("rwe_hud_scale_long")  or "Size of the World Events HUD panel"
    )

    -- ── Event Categories ──────────────────────────────────
    RWESettingsIntegration:addSubHeader(frame,
        g_i18n:getText("rwe_subheader_categories") or "Event Categories"
    )

    frame.rwe_economicEvents = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEEconomicChanged",
        g_i18n:getText("rwe_economic_short") or "Economic Events",
        g_i18n:getText("rwe_economic_long")  or "Enable market and economic events"
    )

    frame.rwe_vehicleEvents = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEVehicleChanged",
        g_i18n:getText("rwe_vehicle_short") or "Vehicle Events",
        g_i18n:getText("rwe_vehicle_long")  or "Enable vehicle events (speed, fuel, damage)"
    )

    frame.rwe_fieldEvents = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEFieldChanged",
        g_i18n:getText("rwe_field_short") or "Field Events",
        g_i18n:getText("rwe_field_long")  or "Enable crop and field events"
    )

    frame.rwe_wildlifeEvents = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEWildlifeChanged",
        g_i18n:getText("rwe_wildlife_short") or "Wildlife Events",
        g_i18n:getText("rwe_wildlife_long")  or "Enable wildlife and animal events"
    )

    frame.rwe_specialEvents = RWESettingsIntegration:addBinaryOption(
        frame, "onRWESpecialChanged",
        g_i18n:getText("rwe_special_short") or "Special Events",
        g_i18n:getText("rwe_special_long")  or "Enable time, XP, and special events"
    )

    -- ── Physics Override ──────────────────────────────────
    RWESettingsIntegration:addSubHeader(frame,
        g_i18n:getText("rwe_subheader_physics") or "Physics Override"
    )

    frame.rwe_physicsEnabled = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEPhysicsEnabledChanged",
        g_i18n:getText("rwe_physics_enabled_short") or "Enable Physics Override",
        g_i18n:getText("rwe_physics_enabled_long")  or "Apply terrain-aware wheel grip and suspension"
    )

    frame.rwe_wheelGrip = RWESettingsIntegration:addMultiTextOption(
        frame, "onRWEWheelGripChanged",
        RWESettingsIntegration.physicsMultOptions,
        g_i18n:getText("rwe_wheel_grip_short") or "Wheel Grip",
        g_i18n:getText("rwe_wheel_grip_long")  or "Scale terrain grip values (1.00 = default)"
    )

    frame.rwe_suspensionStiffness = RWESettingsIntegration:addMultiTextOption(
        frame, "onRWESuspensionChanged",
        RWESettingsIntegration.physicsMultOptions,
        g_i18n:getText("rwe_suspension_short") or "Suspension Stiffness",
        g_i18n:getText("rwe_suspension_long")  or "Scale suspension spring force (1.00 = default)"
    )

    -- ── Debug ─────────────────────────────────────────────
    RWESettingsIntegration:addSubHeader(frame,
        g_i18n:getText("rwe_subheader_debug") or "Debug"
    )

    frame.rwe_showPhysicsInfo = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEShowPhysicsInfoChanged",
        g_i18n:getText("rwe_physics_info_short") or "Show Physics Info",
        g_i18n:getText("rwe_physics_info_long")  or "Log per-vehicle speed and grip data each frame"
    )

    frame.rwe_debugMode = RWESettingsIntegration:addBinaryOption(
        frame, "onRWEDebugChanged",
        g_i18n:getText("rwe_debug_short") or "Debug Mode",
        g_i18n:getText("rwe_debug_long")  or "Show verbose Random World Events debug output"
    )
end

-- =========================================================
-- GUI Element Builders (FS25 profile-based)
-- =========================================================

function RWESettingsIntegration:addSectionHeader(frame, text)
    local textElement = TextElement.new()
    textElement.name  = "sectionHeader"
    textElement:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    textElement:setText(text)
    -- InGameMenuSettingsFrame hover code calls setImageColor() on all layout
    -- children; TextElement doesn't have this method, so stub it out.
    textElement.setImageColor = function() end
    frame.gameSettingsLayout:addElement(textElement)
    textElement:onGuiSetupFinished()
end

--- Sub-header: plain TextElement with setImageColor stubbed to prevent the
--- InGameMenuSettingsFrame hover crash. No BitmapElement wrapper needed —
--- the wrapper was causing a gray box artifact and double-height layout overlap.
function RWESettingsIntegration:addSubHeader(frame, text)
    local textElement = TextElement.new()
    textElement.name  = "subHeader"
    textElement:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    textElement:setText(text)
    textElement.setImageColor = function() end
    frame.gameSettingsLayout:addElement(textElement)
    textElement:onGuiSetupFinished()
end

function RWESettingsIntegration:addBinaryOption(frame, callbackName, title, tooltip)
    local bitMap = BitmapElement.new()
    bitMap:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)

    local binaryOption = BinaryOptionElement.new()
    binaryOption.useYesNoTexts = true
    binaryOption:loadProfile(g_gui:getProfile("fs25_settingsBinaryOption"), true)
    binaryOption.target = RWESettingsIntegration
    binaryOption:setCallback("onClickCallback", callbackName)

    local titleEl = TextElement.new()
    titleEl:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
    titleEl:setText(title)

    local tooltipEl = TextElement.new()
    tooltipEl.name = "ignore"
    tooltipEl:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
    tooltipEl:setText(tooltip)

    binaryOption:addElement(tooltipEl)
    bitMap:addElement(binaryOption)
    bitMap:addElement(titleEl)

    binaryOption:onGuiSetupFinished()
    titleEl:onGuiSetupFinished()
    tooltipEl:onGuiSetupFinished()

    frame.gameSettingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()

    return binaryOption
end

function RWESettingsIntegration:addMultiTextOption(frame, callbackName, texts, title, tooltip)
    local bitMap = BitmapElement.new()
    bitMap:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)

    local multiText = MultiTextOptionElement.new()
    multiText:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOption"), true)
    multiText.target = RWESettingsIntegration
    multiText:setCallback("onClickCallback", callbackName)
    multiText:setTexts(texts)

    local titleEl = TextElement.new()
    titleEl:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
    titleEl:setText(title)

    local tooltipEl = TextElement.new()
    tooltipEl.name = "ignore"
    tooltipEl:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
    tooltipEl:setText(tooltip)

    multiText:addElement(tooltipEl)
    bitMap:addElement(multiText)
    bitMap:addElement(titleEl)

    multiText:onGuiSetupFinished()
    titleEl:onGuiSetupFinished()
    tooltipEl:onGuiSetupFinished()

    frame.gameSettingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()

    return multiText
end

-- =========================================================
-- Update UI from current settings
-- =========================================================

function RWESettingsIntegration:findValueIndex(values, target)
    local bestIdx  = 1
    local bestDiff = math.huge
    for i, v in ipairs(values) do
        local diff = math.abs(v - target)
        if diff < bestDiff then
            bestDiff = diff
            bestIdx  = i
        end
    end
    return bestIdx
end

function RWESettingsIntegration:updateSettingsUI(frame)
    if not frame.rwe_initDone then return end

    local rwe = g_RandomWorldEvents
    if not rwe then return end

    local ev = rwe.events
    local ph = rwe.physics
    local db = rwe.debug

    -- Enable
    if frame.rwe_eventsEnabled then
        frame.rwe_eventsEnabled:setIsChecked(ev.enabled == true, false, false)
    end

    -- Timing
    if frame.rwe_frequency then
        frame.rwe_frequency:setState(RWESettingsIntegration:findValueIndex(
            RWESettingsIntegration.frequencyValues, ev.frequency or 5))
    end
    if frame.rwe_intensity then
        frame.rwe_intensity:setState(RWESettingsIntegration:findValueIndex(
            RWESettingsIntegration.intensityValues, ev.intensity or 2))
    end
    if frame.rwe_cooldown then
        frame.rwe_cooldown:setState(RWESettingsIntegration:findValueIndex(
            RWESettingsIntegration.cooldownValues, ev.cooldown or 30))
    end

    -- HUD & Notifications
    if frame.rwe_notifications then
        frame.rwe_notifications:setIsChecked(ev.showNotifications == true, false, false)
    end
    if frame.rwe_warnings then
        frame.rwe_warnings:setIsChecked(ev.showWarnings == true, false, false)
    end
    if frame.rwe_showHUD then
        frame.rwe_showHUD:setIsChecked(ev.showHUD ~= false, false, false)
    end
    if frame.rwe_hudScale then
        local scale = rwe.hudScale or 1.0
        frame.rwe_hudScale:setState(RWESettingsIntegration:findValueIndex(
            RWESettingsIntegration.hudScaleValues, scale))
    end

    -- Categories
    if frame.rwe_economicEvents then
        frame.rwe_economicEvents:setIsChecked(ev.economicEvents == true, false, false)
    end
    if frame.rwe_vehicleEvents then
        frame.rwe_vehicleEvents:setIsChecked(ev.vehicleEvents == true, false, false)
    end
    if frame.rwe_fieldEvents then
        frame.rwe_fieldEvents:setIsChecked(ev.fieldEvents == true, false, false)
    end
    if frame.rwe_wildlifeEvents then
        frame.rwe_wildlifeEvents:setIsChecked(ev.wildlifeEvents == true, false, false)
    end
    if frame.rwe_specialEvents then
        frame.rwe_specialEvents:setIsChecked(ev.specialEvents == true, false, false)
    end

    -- Physics
    if frame.rwe_physicsEnabled then
        frame.rwe_physicsEnabled:setIsChecked(ph.enabled == true, false, false)
    end
    if frame.rwe_wheelGrip then
        frame.rwe_wheelGrip:setState(RWESettingsIntegration:findValueIndex(
            RWESettingsIntegration.physicsMultValues, ph.wheelGripMultiplier or 1.0))
    end
    if frame.rwe_suspensionStiffness then
        frame.rwe_suspensionStiffness:setState(RWESettingsIntegration:findValueIndex(
            RWESettingsIntegration.physicsMultValues, ph.suspensionStiffness or 1.0))
    end

    -- Debug
    if frame.rwe_showPhysicsInfo then
        frame.rwe_showPhysicsInfo:setIsChecked(ph.showPhysicsInfo == true, false, false)
    end
    if frame.rwe_debugMode then
        frame.rwe_debugMode:setIsChecked(db and db.enabled == true, false, false)
    end
end

function RWESettingsIntegration:updateGameSettings()
    RWESettingsIntegration:updateSettingsUI(self)
end

-- =========================================================
-- Callback helpers
-- =========================================================

local function applyEventSetting(key, value)
    if not g_RandomWorldEvents then return end
    g_RandomWorldEvents.events[key] = value
    g_RandomWorldEvents:saveSettings()
    Logging.info("[RWE] events." .. key .. " = " .. tostring(value))
end

local function applyPhysicsSetting(key, value)
    if not g_RandomWorldEvents then return end
    g_RandomWorldEvents.physics[key] = value
    g_RandomWorldEvents:saveSettings()
    Logging.info("[RWE] physics." .. key .. " = " .. tostring(value))
end

-- =========================================================
-- Callback Handlers
-- =========================================================

function RWESettingsIntegration:onRWEEventsEnabledChanged(state)
    applyEventSetting("enabled", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEFrequencyChanged(state)
    applyEventSetting("frequency", RWESettingsIntegration.frequencyValues[state] or 5)
end

function RWESettingsIntegration:onRWEIntensityChanged(state)
    applyEventSetting("intensity", RWESettingsIntegration.intensityValues[state] or 2)
end

function RWESettingsIntegration:onRWECooldownChanged(state)
    applyEventSetting("cooldown", RWESettingsIntegration.cooldownValues[state] or 30)
end

function RWESettingsIntegration:onRWENotificationsChanged(state)
    applyEventSetting("showNotifications", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEWarningsChanged(state)
    applyEventSetting("showWarnings", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEShowHUDChanged(state)
    applyEventSetting("showHUD", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEHudScaleChanged(state)
    local scale = RWESettingsIntegration.hudScaleValues[state] or 1.0
    if g_RandomWorldEvents then
        g_RandomWorldEvents.hudScale = scale
        -- Apply to live HUD immediately
        if g_RandomWorldEvents.eventHUD then
            g_RandomWorldEvents.eventHUD.scale = scale
        end
        g_RandomWorldEvents:saveSettings()
        Logging.info("[RWE] hudScale = " .. tostring(scale))
    end
end

function RWESettingsIntegration:onRWEEconomicChanged(state)
    applyEventSetting("economicEvents", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEVehicleChanged(state)
    applyEventSetting("vehicleEvents", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEFieldChanged(state)
    applyEventSetting("fieldEvents", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEWildlifeChanged(state)
    applyEventSetting("wildlifeEvents", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWESpecialChanged(state)
    applyEventSetting("specialEvents", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEPhysicsEnabledChanged(state)
    applyPhysicsSetting("enabled", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEWheelGripChanged(state)
    applyPhysicsSetting("wheelGripMultiplier",
        RWESettingsIntegration.physicsMultValues[state] or 1.0)
end

function RWESettingsIntegration:onRWESuspensionChanged(state)
    applyPhysicsSetting("suspensionStiffness",
        RWESettingsIntegration.physicsMultValues[state] or 1.0)
end

function RWESettingsIntegration:onRWEShowPhysicsInfoChanged(state)
    applyPhysicsSetting("showPhysicsInfo", state == BinaryOptionElement.STATE_RIGHT)
end

function RWESettingsIntegration:onRWEDebugChanged(state)
    local isEnabled = state == BinaryOptionElement.STATE_RIGHT
    if not g_RandomWorldEvents then return end
    g_RandomWorldEvents.debug.enabled = isEnabled
    g_RandomWorldEvents.debug.showDebugInfo = isEnabled
    g_RandomWorldEvents:saveSettings()
    Logging.info("[RWE] debug.enabled = " .. tostring(isEnabled))
end

-- =========================================================
-- Initialize hooks (runs at file load time)
-- =========================================================

local function initHooks()
    if not InGameMenuSettingsFrame then return end

    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
        InGameMenuSettingsFrame.onFrameOpen,
        RWESettingsIntegration.onFrameOpen
    )

    if InGameMenuSettingsFrame.updateGameSettings then
        InGameMenuSettingsFrame.updateGameSettings = Utils.appendedFunction(
            InGameMenuSettingsFrame.updateGameSettings,
            RWESettingsIntegration.updateGameSettings
        )
    end
end

initHooks()
