-- =========================================================
-- Random World Events - Custom Settings Panel
-- =========================================================
-- Pure overlay renderer (no XML) for mod settings.
-- Opens with Shift+O.
-- Handles mouse input manually.
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class RWESettingsPanel
RWESettingsPanel = {}
local RWESettingsPanel_mt = Class(RWESettingsPanel)

-- =========================================================
-- Constructor
-- =========================================================

function RWESettingsPanel.new(rweInstance)
    local self = setmetatable({}, RWESettingsPanel_mt)

    self.rwe = rweInstance
    self.isOpen = false

    -- Panel Geometry (centered)
    self.width  = 0.50
    self.height = 0.65
    self.posX   = (1.0 - self.width) / 2
    self.posY   = (1.0 - self.height) / 2

    -- Layout
    self.tabHeight = 0.04
    self.rowHeight = 0.035
    self.padding   = 0.02
    self.sidebarW  = 0.12

    -- State
    self.currentTab = "events" -- "events", "categories", "physics", "debug"
    self.tabs = {
        { id = "events",     label = "General" },
        { id = "categories", label = "Categories" },
        { id = "physics",    label = "Physics" },
        { id = "debug",      label = "Debug" }
    }

    -- 1x1 pixel for backgrounds
    self.bgOverlay = nil
    if createImageOverlay then
        self.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    -- Mouse tracking
    self.mousePosX = 0.5
    self.mousePosY = 0.5

    -- Colors (Dark theme)
    self.COLORS = {
        BG          = {0.02, 0.02, 0.02, 0.94},
        SIDEBAR     = {0.05, 0.05, 0.05, 1.00},
        HEADER      = {0.10, 0.10, 0.10, 1.00},
        ACCENT      = {0.90, 0.75, 0.20, 1.00}, -- Gold
        TEXT_HI     = {1.00, 1.00, 1.00, 1.00},
        TEXT_LO     = {0.60, 0.60, 0.60, 1.00},
        BORDER      = {0.20, 0.20, 0.20, 1.00},
        ROW_HOVER   = {1.00, 1.00, 1.00, 0.05},
        BTN_BG      = {0.15, 0.15, 0.15, 1.00},
        BTN_HOVER   = {0.25, 0.25, 0.25, 1.00},
        TOGGLE_ON   = {0.30, 0.85, 0.30, 1.00},
        TOGGLE_OFF  = {0.85, 0.30, 0.30, 1.00}
    }

    -- Hitboxes for clicks
    self.hitboxes = {}

    return self
end

-- =========================================================
-- Toggle & Lifecycle
-- =========================================================

function RWESettingsPanel:toggle()
    self.isOpen = not self.isOpen
    
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(self.isOpen)
    end

    -- Prevent camera movement when panel is open
    if g_currentMission then
        if g_currentMission.controlledVehicle then
            g_currentMission.controlledVehicle:setForcedNoCameraRotation(self.isOpen)
        end
        if g_currentMission.player then
            g_currentMission.player:setForcedNoCameraRotation(self.isOpen)
        end
    end

    if self.isOpen then
        -- Optional: lock player movement too
        -- if g_currentMission.player then g_currentMission.player:setDisableInput(true) end
    else
        self.rwe:saveSettings()
    end
end

function RWESettingsPanel:delete()
    if self.bgOverlay then
        delete(self.bgOverlay)
        self.bgOverlay = nil
    end
end

-- =========================================================
-- Input Handling
-- =========================================================

function RWESettingsPanel:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.isOpen then return end

    self.mousePosX = posX
    self.mousePosY = posY

    if isDown and button == 1 then
        for _, box in ipairs(self.hitboxes) do
            if posX >= box.x and posX <= box.x + box.w and
               posY >= box.y and posY <= box.y + box.h then
                if box.action then
                    box.action()
                    return true
                end
            end
        end
    end
end

-- =========================================================
-- Drawing
-- =========================================================

function RWESettingsPanel:draw()
    if not self.isOpen then return end

    -- Reset hitboxes each frame
    self.hitboxes = {}

    local sc = 1.0 -- Could be tied to self.rwe.hudScale

    -- Main Panel
    self:drawRect(self.posX, self.posY, self.width, self.height, self.COLORS.BG)
    self:drawRect(self.posX, self.posY, self.sidebarW, self.height, self.COLORS.SIDEBAR)
    
    -- Header
    local headerH = 0.05
    self:drawRect(self.posX, self.posY + self.height - headerH, self.width, headerH, self.COLORS.HEADER)
    
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(unpack(self.COLORS.TEXT_HI))
    renderText(self.posX + 0.015, self.posY + self.height - 0.035, 0.02, "RANDOM WORLD EVENTS SETTINGS")
    
    -- Version hint (dynamic)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextBold(false)
    setTextColor(unpack(self.COLORS.TEXT_LO))
    renderText(self.posX + self.width - 0.015, self.posY + self.height - 0.032, 0.012, "v" .. (self.rwe.VERSION or "?"))

    -- Tabs (Sidebar)
    local tabY = self.posY + self.height - headerH - 0.02
    for _, tab in ipairs(self.tabs) do
        self:drawTab(tab, self.posX, tabY, self.sidebarW, self.tabHeight)
        tabY = tabY - self.tabHeight - 0.005
    end

    -- Content Area
    local contentX = self.posX + self.sidebarW + self.padding
    local contentY = self.posY + self.height - headerH - self.padding
    local contentW = self.width - self.sidebarW - (self.padding * 2)

    if self.currentTab == "events" then
        self:drawEventsTab(contentX, contentY, contentW)
    elseif self.currentTab == "categories" then
        self:drawCategoriesTab(contentX, contentY, contentW)
    elseif self.currentTab == "physics" then
        self:drawPhysicsTab(contentX, contentY, contentW)
    elseif self.currentTab == "debug" then
        self:drawDebugTab(contentX, contentY, contentW)
    end

    -- Close Hint (dynamic key)
    local keyHint = (self.rwe.settingsKeyHint and self.rwe.settingsKeyHint ~= "") and self.rwe.settingsKeyHint or "Shift+O"
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(unpack(self.COLORS.TEXT_LO))
    renderText(self.posX + self.width / 2, self.posY + 0.015, 0.012, "Press " .. keyHint .. " to close and save")

    -- Mouse cursor (simple crosshair or dot since we manage it)
    self:drawRect(self.mousePosX - 0.002, self.mousePosY - 0.0005, 0.004, 0.001, {1,1,1,1})
    self:drawRect(self.mousePosX - 0.0005, self.mousePosY - 0.002, 0.001, 0.004, {1,1,1,1})
end

-- =====================
-- Sub-Drawing Helpers
-- =====================

function RWESettingsPanel:drawTab(tab, x, y, w, h)
    local isSelected = (self.currentTab == tab.id)
    local isHover = self.mousePosX >= x and self.mousePosX <= x + w and self.mousePosY >= y and self.mousePosY <= y + h

    if isSelected then
        self:drawRect(x, y, w, h, self.COLORS.ACCENT)
        setTextColor(0, 0, 0, 1)
    else
        if isHover then
            self:drawRect(x, y, w, h, self.COLORS.BTN_HOVER)
        end
        setTextColor(unpack(isSelected and {0,0,0,1} or (isHover and self.COLORS.TEXT_HI or self.COLORS.TEXT_LO)))
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(isSelected)
    renderText(x + 0.01, y + (h - 0.015) / 2, 0.015, tab.label:upper())

    table.insert(self.hitboxes, {
        x = x, y = y, w = w, h = h,
        action = function() self.currentTab = tab.id end
    })
end

function RWESettingsPanel:drawEventsTab(x, y, w)
    local cy = y
    local ev = self.rwe.events

    cy = self:drawHeader(x, cy, w, "GLOBAL SETTINGS")
    cy = self:drawToggle(x, cy, w, "Enable All Events", ev.enabled, function(v) ev.enabled = v end)
    cy = cy - 0.01
    
    cy = self:drawHeader(x, cy, w, "TIMING & CHANCE")
    cy = self:drawSlider(x, cy, w, "Frequency (1-10)", ev.frequency, 1, 10, 1, function(v) ev.frequency = v end)
    cy = self:drawSlider(x, cy, w, "Intensity (1-5)", ev.intensity, 1, 5, 1, function(v) ev.intensity = v end)
    cy = self:drawSlider(x, cy, w, "Cooldown (min)", ev.cooldown, 5, 240, 5, function(v) ev.cooldown = v end)
    cy = cy - 0.01

    cy = self:drawHeader(x, cy, w, "NOTIFICATIONS")
    cy = self:drawToggle(x, cy, w, "Show Notifications", ev.showNotifications, function(v) ev.showNotifications = v end)
    cy = self:drawToggle(x, cy, w, "Show Warnings", ev.showWarnings, function(v) ev.showWarnings = v end)
    cy = self:drawToggle(x, cy, w, "Show HUD Overlay", ev.showHUD, function(v) ev.showHUD = v end)
end

function RWESettingsPanel:drawCategoriesTab(x, y, w)
    local cy = y
    local ev = self.rwe.events

    cy = self:drawHeader(x, cy, w, "EVENT CATEGORIES")
    cy = self:drawToggle(x, cy, w, "Economic Events", ev.economicEvents, function(v) ev.economicEvents = v end)
    cy = self:drawToggle(x, cy, w, "Vehicle Events", ev.vehicleEvents, function(v) ev.vehicleEvents = v end)
    cy = self:drawToggle(x, cy, w, "Field Events", ev.fieldEvents, function(v) ev.fieldEvents = v end)
    cy = self:drawToggle(x, cy, w, "Wildlife Events", ev.wildlifeEvents, function(v) ev.wildlifeEvents = v end)
    cy = self:drawToggle(x, cy, w, "Special Events", ev.specialEvents, function(v) ev.specialEvents = v end)
    cy = self:drawToggle(x, cy, w, "Weather Events (WIP)", ev.weatherEvents, function(v) ev.weatherEvents = v end)
end

function RWESettingsPanel:drawPhysicsTab(x, y, w)
    local cy = y
    local ph = self.rwe.physics

    cy = self:drawHeader(x, cy, w, "PHYSICS OVERRIDE")
    cy = self:drawToggle(x, cy, w, "Enable Physics", ph.enabled, function(v) ph.enabled = v end)
    cy = cy - 0.01

    cy = self:drawHeader(x, cy, w, "HANDLING")
    cy = self:drawSlider(x, cy, w, "Wheel Grip", ph.wheelGripMultiplier, 0.5, 2.0, 0.05, function(v) ph.wheelGripMultiplier = v end, "%.2fx")
    cy = self:drawSlider(x, cy, w, "Suspension Stiffness", ph.suspensionStiffness, 0.5, 2.0, 0.05, function(v) ph.suspensionStiffness = v end, "%.2fx")
    cy = self:drawSlider(x, cy, w, "COM Strength", ph.comStrength, 0.5, 2.0, 0.05, function(v) ph.comStrength = v end, "%.2fx")
end

function RWESettingsPanel:drawDebugTab(x, y, w)
    local cy = y
    local db = self.rwe.debug
    local ph = self.rwe.physics

    cy = self:drawHeader(x, cy, w, "DEBUG LOGGING")
    cy = self:drawToggle(x, cy, w, "Enable Debug Logging", db.enabled, function(v) db.enabled = v end)
    cy = self:drawSlider(x, cy, w, "Debug Level (1-3)", db.debugLevel, 1, 3, 1, function(v) db.debugLevel = v end)
    cy = self:drawToggle(x, cy, w, "Show Debug Info HUD", db.showDebugInfo, function(v) db.showDebugInfo = v end)
    cy = cy - 0.01

    cy = self:drawHeader(x, cy, w, "PHYSICS DEBUG")
    cy = self:drawToggle(x, cy, w, "Show Physics Info", ph.showPhysicsInfo, function(v) ph.showPhysicsInfo = v end)
    cy = self:drawToggle(x, cy, w, "Physics Debug Mode", ph.debugMode, function(v) ph.debugMode = v end)
    cy = cy - 0.02

    -- Active event info
    local activeEvent = self.rwe.EVENT_STATE and self.rwe.EVENT_STATE.activeEvent
    cy = self:drawHeader(x, cy, w, "EVENT STATE")
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(unpack(self.COLORS.TEXT_LO))
    local stateText = activeEvent and ("Active: " .. tostring(activeEvent)) or "No active event"
    renderText(x, cy - 0.022, 0.013, stateText)
    cy = cy - 0.035
    cy = cy - 0.01

    -- Action buttons
    self:drawButton(x, cy, w * 0.45, 0.03, "FORCE RANDOM EVENT", function()
        self.rwe:triggerRandomEvent()
    end)

    self:drawButton(x + w * 0.55, cy, w * 0.45, 0.03, "END ACTIVE EVENT", function()
        self.rwe:consoleCommandEnd()
    end)
end

-- =====================
-- UI Element Components
-- =====================

function RWESettingsPanel:drawHeader(x, y, w, text)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(unpack(self.COLORS.ACCENT))
    renderText(x, y - 0.015, 0.012, text)
    self:drawRect(x, y - 0.02, w, 0.001, self.COLORS.BORDER)
    return y - 0.035
end

function RWESettingsPanel:drawToggle(x, y, w, label, value, callback)
    local isHover = self.mousePosX >= x and self.mousePosX <= x + w and self.mousePosY >= y - self.rowHeight and self.mousePosY <= y
    if isHover then
        self:drawRect(x - 0.005, y - self.rowHeight, w + 0.01, self.rowHeight, self.COLORS.ROW_HOVER)
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(unpack(isHover and self.COLORS.TEXT_HI or self.COLORS.TEXT_LO))
    renderText(x, y - 0.025, 0.015, label)

    local btnW = 0.06
    local btnX = x + w - btnW
    local btnY = y - 0.03
    local btnH = 0.025

    local btnColor = value and self.COLORS.TOGGLE_ON or self.COLORS.TOGGLE_OFF
    self:drawRect(btnX, btnY, btnW, btnH, {btnColor[1], btnColor[2], btnColor[3], 0.2})
    self:drawRect(btnX, btnY, btnW, 0.001, btnColor)
    
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(unpack(btnColor))
    renderText(btnX + btnW/2, btnY + 0.006, 0.014, value and "ON" or "OFF")

    table.insert(self.hitboxes, {
        x = x, y = y - self.rowHeight, w = w, h = self.rowHeight,
        action = function() callback(not value) end
    })

    return y - self.rowHeight
end

function RWESettingsPanel:drawSlider(x, y, w, label, value, minV, maxV, step, callback, fmt)
    local isHover = self.mousePosX >= x and self.mousePosX <= x + w and self.mousePosY >= y - self.rowHeight and self.mousePosY <= y
    if isHover then
        self:drawRect(x - 0.005, y - self.rowHeight, w + 0.01, self.rowHeight, self.COLORS.ROW_HOVER)
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(unpack(isHover and self.COLORS.TEXT_HI or self.COLORS.TEXT_LO))
    renderText(x, y - 0.025, 0.015, label)

    local btnW = 0.025
    local valW = 0.06
    local btnH = 0.025
    local totalW = btnW * 2 + valW
    local startX = x + w - totalW
    local btnY = y - 0.03

    -- Dec Button
    local hovDec = self.mousePosX >= startX and self.mousePosX <= startX + btnW and self.mousePosY >= btnY and self.mousePosY <= btnY + btnH
    self:drawRect(startX, btnY, btnW, btnH, hovDec and self.COLORS.BTN_HOVER or self.COLORS.BTN_BG)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(unpack(self.COLORS.TEXT_HI))
    renderText(startX + btnW/2, btnY + 0.006, 0.015, "<")
    table.insert(self.hitboxes, {
        x = startX, y = btnY, w = btnW, h = btnH,
        action = function() callback(math.max(minV, value - step)) end
    })

    -- Value
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(unpack(self.COLORS.TEXT_HI))
    local displayVal = fmt and string.format(fmt, value) or tostring(value)
    renderText(startX + btnW + valW/2, btnY + 0.006, 0.015, displayVal)

    -- Inc Button
    local incX = startX + btnW + valW
    local hovInc = self.mousePosX >= incX and self.mousePosX <= incX + btnW and self.mousePosY >= btnY and self.mousePosY <= btnY + btnH
    self:drawRect(incX, btnY, btnW, btnH, hovInc and self.COLORS.BTN_HOVER or self.COLORS.BTN_BG)
    renderText(incX + btnW/2, btnY + 0.006, 0.015, ">")
    table.insert(self.hitboxes, {
        x = incX, y = btnY, w = btnW, h = btnH,
        action = function() callback(math.min(maxV, value + step)) end
    })

    return y - self.rowHeight
end

function RWESettingsPanel:drawButton(x, y, w, h, text, callback)
    local isHover = self.mousePosX >= x and self.mousePosX <= x + w and self.mousePosY >= y and self.mousePosY <= y + h
    self:drawRect(x, y, w, h, isHover and self.COLORS.BTN_HOVER or self.COLORS.BTN_BG)
    self:drawRect(x, y, w, 0.001, self.COLORS.ACCENT)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(unpack(isHover and self.COLORS.TEXT_HI or self.COLORS.TEXT_LO))
    renderText(x + w/2, y + (h - 0.012)/2, 0.012, text)

    table.insert(self.hitboxes, {
        x = x, y = y, w = w, h = h,
        action = callback
    })
end

-- =====================
-- Low-Level Drawing
-- =====================

function RWESettingsPanel:drawRect(x, y, w, h, color)
    if not self.bgOverlay then return end
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], color[4] or 1)
    renderOverlay(self.bgOverlay, x, y, w, h)
end

function RWESettingsPanel:drawRectA(x, y, w, h, color, alpha)
    if not self.bgOverlay then return end
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], alpha)
    renderOverlay(self.bgOverlay, x, y, w, h)
end
