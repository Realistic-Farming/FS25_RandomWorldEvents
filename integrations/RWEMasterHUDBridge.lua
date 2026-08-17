-- =========================================================
-- Random World Events - MasterHUD bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_MasterHUD (bedrock). RWE ships standalone, so this is
-- strictly delegate-when-present, mirroring SoilFertilizer / TaxMod:
--   * MasterHUD installed -> RWE registers its self-drawn HUD stack (the event
--     notification HUD overlay and the custom in-world settings panel) as a
--     subscribe() element. MasterHUD then owns the single suspend-aware draw loop
--     and cross-mod ordering, so RWE's HUD stacks cleanly with the rest of the
--     ecosystem instead of every mod hooking FSBaseMission.draw independently.
--   * MasterHUD absent -> RWE's own FSBaseMission.draw hook runs the exact same
--     stack, exactly as before.
--
-- drawStack() is the single source of the draw body, shared with the fallback
-- hook so the two paths can never diverge. It reproduces the own hook's guards
-- byte-for-byte: the event HUD only draws while no GUI/menu is open, the settings
-- panel draws whenever open (it has its own isOpen guard and rebuilds hitboxes
-- each frame).
--
-- Mouse routing stays on the mod's own FSBaseMission.mouseEvent hook (MasterHUD
-- owns draw ordering + suspend, not input). The ESC > Settings injection
-- (RWESettingsIntegration) is g_gui-managed and stays there; it is not a HUD.
--
-- The cross-mod handle is g_currentMission.masterHUD (published in Mission00.load).
-- =========================================================

RWEMasterHUDBridge = {}

RWEMasterHUDBridge.HUD_ID = "RandomWorldEvents_HUD"
RWEMasterHUDBridge.active = false   -- MasterHUD present and we registered

--- Does RWE currently own the whole screen?
---
--- Passed to MasterHUD as the subscribe spec's isFullscreen so that while our
--- settings panel is open, EVERY other companion's HUD stands down too. Without
--- it, their text renders before our panel and reads straight through it,
--- because an overlay does not cover text already drawn underneath.
---
--- This is the cross-mod half only, and it has an effect only when MasterHUD is
--- present, since MasterHUD owns cross-mod ordering. RWE's own event HUD is
--- handled inside drawStack.
---
--- isOpen is a FIELD on this panel, not a method (RWESettingsPanel.lua:23,
--- flipped by toggle() at :83), so it is read rather than called.
---
--- Called every frame from MasterHUD's draw loop, so it stays a plain read.
---@return boolean
function RWEMasterHUDBridge.isFullscreen()
    local mgr = g_RandomWorldEvents
    if mgr == nil then return false end
    local panel = mgr.settingsPanel
    return panel ~= nil and panel.isOpen == true
end

-- The full RWE HUD draw body. Byte-for-byte the same as the standalone
-- FSBaseMission.draw hook. Resolves the manager from the canonical global so it
-- can be driven either by MasterHUD's loop or by RWE's own hook.
function RWEMasterHUDBridge.drawStack()
    -- Suite hide: MasterHUD # key. No-op when MasterHUD absent.
    local mh = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if mh ~= nil and mh.areHudsHidden ~= nil and mh:areHudsHidden() then return end
    local mgr = g_RandomWorldEvents
    if mgr == nil then return end

    -- THE SETTINGS PANEL OWNS THE SCREEN WHILE IT IS OPEN, so the event HUD
    -- stands down for it exactly as it already stands down for a GUI menu.
    --
    -- A panel background is an OVERLAY, and an overlay does not cover text that
    -- was already rendered underneath it. The event HUD draws first, so its text
    -- read straight THROUGH the panel. A HUD cannot be hidden by drawing the
    -- panel on top of it; it has to not draw.
    --
    -- isOpen is a FIELD on this panel, not a method (RWESettingsPanel.lua:23,
    -- flipped by toggle() at :83), so it is read rather than called.
    local panel = mgr.settingsPanel
    local panelOpen = panel ~= nil and panel.isOpen == true

    -- Event HUD only draws when no GUI/menu and no panel is open.
    if not panelOpen and g_gui and not g_gui:getIsGuiVisible() then
        if mgr.eventHUD then mgr.eventHUD:draw() end
    end

    -- The panel still draws every frame while open, unchanged: it rebuilds its
    -- own hitboxes during draw, so skipping it would break its clicks.
    if panel then panel:draw() end
end

-- Register with MasterHUD if present. Called from loadFinished
-- (loadMission00Finished), after the HUD has published its g_currentMission handle.
function RWEMasterHUDBridge.register(mgr)
    RWEMasterHUDBridge.active = false

    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if hud == nil then
        Logging.info("[RWE] MasterHUD not detected; RWE HUD uses its own draw hook")
        return
    end

    local ok, err = pcall(function()
        hud:subscribe(RWEMasterHUDBridge.HUD_ID, {
            draw = RWEMasterHUDBridge.drawStack,
            -- Stand every OTHER companion's HUD down while our panel owns the
            -- screen. Optional on MasterHUD's side, so an older MasterHUD ignores
            -- it and behaves exactly as before.
            isFullscreen = RWEMasterHUDBridge.isFullscreen,
        })
    end)

    if ok then
        RWEMasterHUDBridge.active = true
        Logging.info("[RWE] Registered RWE HUD with MasterHUD (single draw loop + menu-suspend)")
        if hud.registerEditListener ~= nil then
            hud:registerEditListener(RWEMasterHUDBridge.HUD_ID, {
                enter = function()
                    if mgr ~= nil and mgr.eventHUD ~= nil and mgr.eventHUD.enterEditMode ~= nil then
                        mgr.eventHUD:enterEditMode()
                    end
                end,
                exit = function()
                    if mgr ~= nil and mgr.eventHUD ~= nil and mgr.eventHUD.editMode
                        and mgr.eventHUD.exitEditMode ~= nil then
                        mgr.eventHUD:exitEditMode()
                    end
                end,
            })
        end
    else
        Logging.warning("[RWE] MasterHUD registration failed: %s (using own draw hook)", tostring(err))
    end
end
