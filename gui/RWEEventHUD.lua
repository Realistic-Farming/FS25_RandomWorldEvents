-- =========================================================
-- Random World Events - Event HUD Overlay
-- =========================================================
-- Shows active event info, cooldown status, category badge,
-- time-remaining progress bar, and flash notifications.
-- RMB on panel → drag/resize (IncomeMod/NPCFavor pattern).
-- Position/scale persisted to savegame XML.
-- Toggle: RWE_TOGGLE_HUD action (default F3).
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class RWEEventHUD
RWEEventHUD = {}
local RWEEventHUD_mt = Class(RWEEventHUD)

-- ── Category metadata ─────────────────────────────────────
RWEEventHUD.CATEGORY = {
    economic = { color = {0.90, 0.75, 0.20, 1.00}, label = "ECO" },
    vehicle  = { color = {0.30, 0.60, 1.00, 1.00}, label = "VEH" },
    field    = { color = {0.30, 0.85, 0.30, 1.00}, label = "FLD" },
    wildlife = { color = {0.90, 0.55, 0.15, 1.00}, label = "WLD" },
    special  = { color = {0.70, 0.40, 1.00, 1.00}, label = "SPL" },
}

RWEEventHUD.MIN_SCALE        = 0.60
RWEEventHUD.MAX_SCALE        = 1.80
RWEEventHUD.RESIZE_HANDLE_SIZE = 0.008
RWEEventHUD.FLASH_DURATION   = 5000  -- ms a flash notification stays visible

-- =========================================================
-- Constructor
-- =========================================================

function RWEEventHUD.new(rweInstance)
    local self = setmetatable({}, RWEEventHUD_mt)

    self.rwe = rweInstance

    -- Visibility (F3 toggle — not persisted)
    self.visible = true

    -- Panel anchor: top-left text origin
    self.posX       = 0.77
    self.posY       = 0.90
    self.panelWidth = 0.21

    -- Layout constants at scale 1.0
    self.LINE_H      = 0.018
    self.PAD         = 0.007
    self.TEXT_TITLE  = 0.013
    self.TEXT_NORMAL = 0.011
    self.TEXT_SMALL  = 0.0095
    self.BAR_H       = 0.006

    -- Scale & edit state (IncomeMod pattern)
    self.scale            = 1.0
    self.editMode         = false
    self.dragging         = false
    self.resizing         = false
    self.dragOffsetX      = 0
    self.dragOffsetY      = 0
    self.resizeStartX     = 0
    self.resizeStartY     = 0
    self.resizeStartScale = 1.0
    self.hoverCorner      = nil
    self.animTimer        = 0

    -- Camera freeze during edit mode
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil

    -- Cached panel bounds for hit-testing
    self.lastBgX = 0
    self.lastBgY = 0
    self.lastBgW = 0
    self.lastBgH = 0

    -- Deferred layout load flag (savegame directory may not be ready at construction time)
    self.layoutLoaded = false

    -- Flash notification queue
    -- Each entry: { text, categoryKey, isPositive, timer }
    self.flashQueue  = {}
    self.activeFlash = nil

    -- 1×1 pixel overlay for colored rectangles
    self.bgOverlay = nil
    if createImageOverlay then
        self.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    -- Color palette (neutral dark base, semantic colors for status)
    self.COLORS = {
        BG           = {0.05, 0.05, 0.05, 0.82},
        BORDER       = {0.20, 0.20, 0.20, 0.45},
        DIVIDER      = {0.25, 0.25, 0.25, 0.85},
        SHADOW       = {0.00, 0.00, 0.00, 0.35},
        HEADER       = {1.00, 1.00, 1.00, 1.00},
        ENABLED      = {0.30, 0.90, 0.30, 1.00},
        DISABLED     = {0.90, 0.30, 0.30, 1.00},
        LABEL        = {0.72, 0.72, 0.72, 1.00},
        VALUE        = {1.00, 1.00, 1.00, 1.00},
        DIM          = {0.55, 0.55, 0.55, 1.00},
        READY        = {0.30, 0.85, 0.30, 1.00},
        COOLDOWN     = {0.90, 0.75, 0.20, 1.00},
        BAR_BG       = {0.15, 0.15, 0.15, 1.00},
        BAR_FILL     = {0.30, 0.75, 1.00, 1.00},
        HINT         = {0.52, 0.52, 0.52, 0.75},
        EDIT_BORDER  = {1.00, 0.60, 0.10, 0.90},
        EDIT_HANDLE  = {1.00, 0.70, 0.20, 0.85},
        FLASH_BG     = {0.12, 0.12, 0.18, 0.92},
    }

    return self
end

-- =========================================================
-- Cleanup
-- =========================================================

function RWEEventHUD:delete()
    if self.editMode then self:exitEditMode() end
    if self.bgOverlay then
        delete(self.bgOverlay)
        self.bgOverlay = nil
    end
end

-- =========================================================
-- Visibility toggle (F3)
-- =========================================================

function RWEEventHUD:toggleVisibility()
    self.visible = not self.visible
    local msg = self.visible and g_i18n:getText("rwe_hud_shown") or g_i18n:getText("rwe_hud_hidden")
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(msg, 2000)
    end
end

-- =========================================================
-- Flash notification queue
-- =========================================================

--- Push an event notification to the flash queue.
-- @param text        Display text (event name / short description)
-- @param categoryKey Event category string (e.g. "economic")
-- @param isPositive  true = good event, false = bad event
function RWEEventHUD:pushFlash(text, categoryKey, isPositive)
    table.insert(self.flashQueue, {
        text        = text or "",
        categoryKey = categoryKey or "special",
        isPositive  = isPositive ~= false,
        timer       = RWEEventHUD.FLASH_DURATION,
    })
end

-- =========================================================
-- Edit mode (RMB toggle)
-- =========================================================

function RWEEventHUD:enterEditMode()
    self.editMode = true
    self.dragging = false
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true)
    end
end

function RWEEventHUD:exitEditMode()
    self.editMode    = false
    self.dragging    = false
    self.resizing    = false
    self.hoverCorner = nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    self:saveLayout()
end

-- =========================================================
-- Persistence
-- =========================================================

function RWEEventHUD:getLayoutPath()
    if g_currentMission and g_currentMission.missionInfo
    and g_currentMission.missionInfo.savegameDirectory then
        return g_currentMission.missionInfo.savegameDirectory .. "/FS25_RandomWorldEvents_hud.xml"
    end
end

function RWEEventHUD:saveLayout()
    local path = self:getLayoutPath()
    if not path then return end
    local xml = XMLFile.create("rwe_hud", path, "hudLayout")
    if xml then
        xml:setFloat("hudLayout.posX",   self.posX)
        xml:setFloat("hudLayout.posY",   self.posY)
        xml:setFloat("hudLayout.scale",  self.scale)
        xml:setBool("hudLayout.visible", self.visible)
        xml:save()
        xml:delete()
    end
end

function RWEEventHUD:loadLayout()
    local path = self:getLayoutPath()
    if not path or not fileExists(path) then return end
    local xml = XMLFile.load("rwe_hud", path)
    if xml then
        self.posX    = xml:getFloat("hudLayout.posX",   self.posX)
        self.posY    = xml:getFloat("hudLayout.posY",   self.posY)
        self.scale   = xml:getFloat("hudLayout.scale",  self.scale)
        self.visible = xml:getBool("hudLayout.visible", self.visible)
        xml:delete()
    end
end

-- =========================================================
-- Geometry helpers
-- =========================================================

function RWEEventHUD:isPointerOverHUD(posX, posY)
    return posX >= self.lastBgX and posX <= self.lastBgX + self.lastBgW
       and posY >= self.lastBgY and posY <= self.lastBgY + self.lastBgH
end

function RWEEventHUD:getResizeHandleRects()
    local hs = RWEEventHUD.RESIZE_HANDLE_SIZE
    local bx, by, bw, bh = self.lastBgX, self.lastBgY, self.lastBgW, self.lastBgH
    return {
        bl = {x = bx,           y = by,           w = hs, h = hs},
        br = {x = bx + bw - hs, y = by,           w = hs, h = hs},
        tl = {x = bx,           y = by + bh - hs, w = hs, h = hs},
        tr = {x = bx + bw - hs, y = by + bh - hs, w = hs, h = hs},
    }
end

function RWEEventHUD:hitTestCorner(posX, posY)
    for key, r in pairs(self:getResizeHandleRects()) do
        if posX >= r.x and posX <= r.x + r.w
        and posY >= r.y and posY <= r.y + r.h then
            return key
        end
    end
    return nil
end

function RWEEventHUD:clampPosition()
    local bw  = self.lastBgW
    local bh  = self.lastBgH
    local pad = self.PAD * self.scale
    self.posX = math.max(pad + 0.01,      math.min(1.0 - bw + pad - 0.01, self.posX))
    self.posY = math.max(bh - pad + 0.01, math.min(0.98,                  self.posY))
end

-- =========================================================
-- Mouse event
-- =========================================================

function RWEEventHUD:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.visible then return end

    -- RMB: exit edit mode only. Edit mode is entered exclusively via the
    -- RWE_HUD_DRAG key binding — never via right-click — so RMB is never
    -- consumed during normal play, preserving CoursePlay, AutoDrive, etc.
    if isDown and button == 3 then
        if self.editMode then
            self:exitEditMode()
            return true
        end
        return false
    end

    if not self.editMode then return false end

    if isDown and button == 1 then
        local corner = self:hitTestCorner(posX, posY)
        if corner then
            self.resizing         = true
            self.dragging         = false
            self.resizeStartX     = posX
            self.resizeStartY     = posY
            self.resizeStartScale = self.scale
            return
        end
        if self:isPointerOverHUD(posX, posY) then
            self.dragging    = true
            self.resizing    = false
            self.dragOffsetX = posX - self.posX
            self.dragOffsetY = posY - self.posY
        end
        return
    end

    if isUp and button == 1 then
        if self.dragging or self.resizing then
            self.dragging = false
            self.resizing = false
            self:clampPosition()
        end
        return
    end

    -- Mouse movement
    if self.dragging then
        local bw = self.lastBgW
        self.posX = math.max(0.0, math.min(1.0 - bw, posX - self.dragOffsetX))
        self.posY = math.max(0.05, math.min(0.98, posY - self.dragOffsetY))
    end

    if self.resizing then
        local cx = self.lastBgX + self.lastBgW * 0.5
        local cy = self.lastBgY + self.lastBgH * 0.5
        local startDist = math.sqrt((self.resizeStartX - cx)^2 + (self.resizeStartY - cy)^2)
        local currDist  = math.sqrt((posX - cx)^2            + (posY - cy)^2)
        local delta     = (currDist - startDist) * 2.5
        self.scale = math.max(RWEEventHUD.MIN_SCALE,
            math.min(RWEEventHUD.MAX_SCALE, self.resizeStartScale + delta))
        self:clampPosition()
    end

    if not self.dragging and not self.resizing then
        self.hoverCorner = self:hitTestCorner(posX, posY)
    end
end

-- =========================================================
-- Update (called every frame)
-- =========================================================

function RWEEventHUD:update(dt)
    self.animTimer = self.animTimer + dt

    -- Tick active flash
    if self.activeFlash then
        self.activeFlash.timer = self.activeFlash.timer - dt
        if self.activeFlash.timer <= 0 then
            self.activeFlash = nil
        end
    end

    -- Promote next flash from queue
    if not self.activeFlash and #self.flashQueue > 0 then
        self.activeFlash = table.remove(self.flashQueue, 1)
    end

    -- Edit mode upkeep
    if self.editMode then
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true)
        end
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            self:exitEditMode()
        end
        if not self.dragging and not self.resizing then
            if g_inputBinding and g_inputBinding.mousePosXLast then
                self.hoverCorner = self:hitTestCorner(
                    g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast)
            end
        end
    else
        self.hoverCorner = nil
    end
end

-- =========================================================
-- Draw (called every frame from FSBaseMission.draw hook)
-- =========================================================

function RWEEventHUD:draw()
    if not g_currentMission or not g_currentMission:getIsClient() then return end

    -- Deferred layout load: savegame directory is not available during loadMission00Finished,
    -- so we wait until the first draw call when missionInfo.savegameDirectory is ready.
    if not self.layoutLoaded then
        self.layoutLoaded = true
        if self:getLayoutPath() then
            self:loadLayout()
        end
    end

    if not self.editMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then return end
        if g_currentMission.hud and g_currentMission.hud.ingameMap then
            if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then return end
        end
    end

    local rwe = self.rwe
    if not rwe then return end

    if not self.visible then return end
    if not rwe.events.showHUD then return end
    if not self.bgOverlay then return end

    self:drawPanel()
end

-- =========================================================
-- Panel rendering
-- =========================================================

function RWEEventHUD:drawPanel()
    local sc  = self.scale
    local rwe = self.rwe

    local x   = self.posX
    local w   = self.panelWidth * sc
    local pad = self.PAD  * sc
    local lh  = self.LINE_H * sc

    -- Determine content rows
    local state      = rwe.EVENT_STATE
    local hasEvent   = state.activeEvent ~= nil
    local hasFlash   = self.activeFlash ~= nil
    local nRows      = 5  -- title + divider-row + status + divider-row + hint
    if hasEvent then nRows = nRows + 3 end  -- category badge + name + progress bar row
    if hasFlash then nRows = nRows + 1 end

    local nDividers = 2
    local bgH = pad * 2 + nRows * lh + nDividers * (0.004 * sc)
        + (hasEvent and self.BAR_H * sc or 0)
        + (hasFlash and (self.LINE_H * sc * 0.6) or 0)

    local bgX = x - pad
    local bgY = self.posY - bgH + pad
    local bgW = w + pad * 2

    self.lastBgX = bgX
    self.lastBgY = bgY
    self.lastBgW = bgW
    self.lastBgH = bgH

    -- ── Drop shadow ────────────────────────────────────────
    self:rect(bgX + 0.002, bgY - 0.002, bgW, bgH, self.COLORS.SHADOW)

    -- ── Background ────────────────────────────────────────
    self:rect(bgX, bgY, bgW, bgH, self.COLORS.BG)

    -- ── Permanent border ──────────────────────────────────
    local bw = 0.0012
    self:rect(bgX,            bgY + bgH - bw, bgW, bw, self.COLORS.BORDER)
    self:rect(bgX,            bgY,            bgW, bw, self.COLORS.BORDER)
    self:rect(bgX,            bgY,            bw, bgH, self.COLORS.BORDER)
    self:rect(bgX + bgW - bw, bgY,            bw, bgH, self.COLORS.BORDER)

    -- ── Edit mode chrome ──────────────────────────────────
    if self.editMode then
        local pulse = 0.55 + 0.45 * math.sin(self.animTimer * 0.004)
        local ebw   = 0.002
        local ec    = self.COLORS.EDIT_BORDER
        self:rectA(bgX,             bgY,              bgW, ebw, ec, pulse)
        self:rectA(bgX,             bgY + bgH - ebw,  bgW, ebw, ec, pulse)
        self:rectA(bgX,             bgY,              ebw, bgH, ec, pulse)
        self:rectA(bgX + bgW - ebw, bgY,              ebw, bgH, ec, pulse)
        for key, r in pairs(self:getResizeHandleRects()) do
            local isHover = (self.hoverCorner == key)
            self:rectA(r.x, r.y, r.w, r.h, self.COLORS.EDIT_HANDLE, isHover and 1.0 or 0.65)
        end
    end

    -- ── Content ───────────────────────────────────────────
    local tsTitle  = self.TEXT_TITLE  * sc
    local tsNormal = self.TEXT_NORMAL * sc
    local tsSmall  = self.TEXT_SMALL  * sc

    local cy = self.posY - pad

    -- Flash notification strip (top)
    if hasFlash then
        local flash  = self.activeFlash
        local frac   = flash.timer / RWEEventHUD.FLASH_DURATION
        local alpha  = math.min(1.0, frac * 4.0)  -- fade in fast, fade out slow
        local fh     = lh * 0.75
        local cat    = RWEEventHUD.CATEGORY[flash.categoryKey] or RWEEventHUD.CATEGORY.special
        local fc     = cat.color
        -- Flash background strip
        self:rectA(bgX, cy - fh, bgW, fh, self.COLORS.FLASH_BG, alpha * 0.92)
        -- Left accent bar (category color)
        self:rectA(bgX, cy - fh, 0.003, fh, fc, alpha)
        -- Badge text
        setTextBold(true)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(fc[1], fc[2], fc[3], alpha)
        renderText(x, cy - fh + (fh - tsSmall) * 0.5, tsSmall, "[" .. cat.label .. "]")
        -- Flash text
        local signColor = flash.isPositive and self.COLORS.READY or self.COLORS.DISABLED
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(signColor[1], signColor[2], signColor[3], alpha)
        renderText(x + 0.035 * sc, cy - fh + (fh - tsSmall) * 0.5, tsSmall, flash.text)
        setTextBold(false)
        cy = cy - fh
    end

    -- Title row: "WORLD EVENTS" + [ON/OFF]
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.HEADER[1], self.COLORS.HEADER[2], self.COLORS.HEADER[3], 1)
    renderText(x, cy - tsTitle, tsTitle, g_i18n:getText("rwe_hud_title"))

    local evEnabled  = rwe.events.enabled
    local statusColor = evEnabled and self.COLORS.ENABLED or self.COLORS.DISABLED
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(statusColor[1], statusColor[2], statusColor[3], 1)
    renderText(x + w, cy - tsTitle, tsTitle, evEnabled and g_i18n:getText("rwe_hud_status_on") or g_i18n:getText("rwe_hud_status_off"))
    setTextBold(false)
    cy = cy - lh

    -- Divider
    self:divider(bgX, cy + lh * 0.35, bgW, sc)
    cy = cy - 0.004 * sc

    -- ── Active event section ──────────────────────────────
    if hasEvent then
        local eventId  = state.activeEvent
        local event    = rwe.EVENTS[eventId]
        local catKey   = event and event.category or "special"
        local cat      = RWEEventHUD.CATEGORY[catKey] or RWEEventHUD.CATEGORY.special
        local catColor = cat.color

        -- Category badge + event name row
        setTextBold(true)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(catColor[1], catColor[2], catColor[3], 1)
        renderText(x, cy - tsNormal, tsNormal, "[" .. cat.label .. "]")

        local displayName = eventId:gsub("_", " ")
        displayName = displayName:sub(1,1):upper() .. displayName:sub(2)
        setTextBold(false)
        setTextColor(self.COLORS.VALUE[1], self.COLORS.VALUE[2], self.COLORS.VALUE[3], 1)
        renderText(x + 0.038 * sc, cy - tsNormal, tsNormal, displayName)
        cy = cy - lh

        -- Time remaining row
        local elapsed   = g_currentMission.time - (state.eventStartTime or 0)
        local duration  = state.eventDuration or 1
        local remaining = math.max(0, duration - elapsed)
        local remMin    = math.ceil(remaining / 60000)
        local progress  = duration > 0 and math.max(0, math.min(1, elapsed / duration)) or 0

        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(self.COLORS.LABEL[1], self.COLORS.LABEL[2], self.COLORS.LABEL[3], 1)
        renderText(x, cy - tsSmall, tsSmall, g_i18n:getText("rwe_hud_ends_in"))
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(self.COLORS.COOLDOWN[1], self.COLORS.COOLDOWN[2], self.COLORS.COOLDOWN[3], 1)
        renderText(x + w, cy - tsSmall, tsSmall, remMin .. "m")
        cy = cy - lh

        -- Progress bar
        local barW  = w
        local barH  = self.BAR_H * sc
        local barX  = x
        local barY  = cy - barH
        -- Background track
        self:rect(barX, barY, barW, barH, self.COLORS.BAR_BG)
        -- Fill (category color, fades as time runs out)
        local fillAlpha = 0.5 + 0.5 * (1.0 - progress)
        self:rectA(barX, barY, barW * progress, barH, catColor, fillAlpha)
        cy = cy - barH - (lh * 0.25)

    else
        -- No active event — show cooldown or ready status
        local now         = g_currentMission and g_currentMission.time or 0
        local coolUntil   = state.cooldownUntil or 0
        local isReady     = now >= coolUntil or coolUntil == 0

        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(self.COLORS.LABEL[1], self.COLORS.LABEL[2], self.COLORS.LABEL[3], 1)
        renderText(x, cy - tsNormal, tsNormal, g_i18n:getText("rwe_hud_no_active_event"))
        cy = cy - lh

        if isReady then
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(self.COLORS.READY[1], self.COLORS.READY[2], self.COLORS.READY[3], 1)
            renderText(x, cy - tsSmall, tsSmall, g_i18n:getText("rwe_hud_ready_to_trigger"))
        else
            local waitMs  = math.max(0, coolUntil - now)
            local waitMin = math.ceil(waitMs / 60000)
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(self.COLORS.COOLDOWN[1], self.COLORS.COOLDOWN[2], self.COLORS.COOLDOWN[3], 1)
            renderText(x, cy - tsSmall, tsSmall, string.format(g_i18n:getText("rwe_hud_next_in"), waitMin))
        end
        cy = cy - lh
    end

    -- Stats row: frequency / intensity
    local freq = rwe.events.frequency or 5
    local inten = rwe.events.intensity or 2
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.DIM[1], self.COLORS.DIM[2], self.COLORS.DIM[3], 1)
    renderText(x, cy - tsSmall, tsSmall,
        string.format(g_i18n:getText("rwe_hud_freq_intensity"), freq, inten))
    cy = cy - lh

    -- Divider
    self:divider(bgX, cy + lh * 0.35, bgW, sc)
    cy = cy - 0.004 * sc

    -- Hint row
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(self.COLORS.HINT[1], self.COLORS.HINT[2], self.COLORS.HINT[3], 1)
    if self.editMode then
        renderText(x + w * 0.5, cy - tsSmall, tsSmall, g_i18n:getText("rwe_hud_hint_edit"))
    else
        renderText(x + w * 0.5, cy - tsSmall, tsSmall, g_i18n:getText("rwe_hud_hint_normal"))
    end

    -- Reset text state
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- =========================================================
-- Rendering helpers
-- =========================================================

function RWEEventHUD:rect(rx, ry, rw, rh, color)
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], color[4])
    renderOverlay(self.bgOverlay, rx, ry, rw, rh)
end

function RWEEventHUD:rectA(rx, ry, rw, rh, color, alpha)
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], alpha)
    renderOverlay(self.bgOverlay, rx, ry, rw, rh)
end

function RWEEventHUD:divider(dx, dy, dw, sc)
    self:rect(dx, dy, dw, 0.001 * (sc or 1.0), self.COLORS.DIVIDER)
end
