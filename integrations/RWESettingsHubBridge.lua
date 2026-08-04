-- =========================================================
-- Random World Events - SettingsHub bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_SettingsHub (bedrock). Safe if SettingsHub is not
-- installed (register() just no-ops). Purpose: let the FarmTablet System Settings
-- app list Random World Events' settings, mirroring SoilFertilizer / TaxMod.
--
-- g_RandomWorldEvents keeps its own settings (the nested events / physics / debug
-- tables + top-level hudScale, persisted by the mod's own FS25_RandomWorldEvents.xml
-- save path) as the source of truth. This bridge mirrors current values into
-- SettingsHub for display and, when the hub reports an edit, applies it back onto
-- those same tables the same minimal way the ESC > Settings integration does:
-- set the field, save. It does not invent any new persistence or network path;
-- the tablet app is read-only for now.
--
-- selfPersisted = true: we own persistence and load it before this registration
-- runs, so the hub must mirror-for-display only and never restore its own stale
-- copy and replay it through onChange on load (the SoilFertilizer enabled=false
-- reset-on-load bug class).
--
-- Labels reuse the mod's existing "<x>_short" l10n keys, resolved verbatim here
-- because FarmTablet's System Settings app renders the label string as-is (no
-- l10n lookup on its end). No new user-facing strings are added.
--
-- The cross-mod handle is g_currentMission.settingsHub (the same one FarmTablet
-- reads); the bare g_settingsHub global is only visible inside SettingsHub's own
-- mod environment.
-- =========================================================

RWESettingsHubBridge = {}

-- id -> descriptor. section/key locate the live value in the nested settings
-- tables (section "top" = the manager itself for hudScale). type maps onto the
-- SettingsHub value types. admin=true -> server-shared, admin=false -> per-player,
-- matching the gameplay-vs-display split the ESC settings already use.
local SETTINGS = {
    { id = "enabled",             section = "events",  key = "enabled",             type = "bool",  admin = true,  l10n = "rwe_events_enabled_short" },
    { id = "frequency",           section = "events",  key = "frequency",           type = "int",   admin = true,  min = 1,   max = 10,  l10n = "rwe_frequency_short" },
    { id = "intensity",           section = "events",  key = "intensity",           type = "int",   admin = true,  min = 1,   max = 5,   l10n = "rwe_intensity_short" },
    { id = "cooldown",            section = "events",  key = "cooldown",            type = "int",   admin = true,  min = 5,   max = 240, l10n = "rwe_cooldown_short" },
    { id = "showNotifications",   section = "events",  key = "showNotifications",   type = "bool",  admin = false, l10n = "rwe_notifications_short" },
    { id = "showWarnings",        section = "events",  key = "showWarnings",        type = "bool",  admin = false, l10n = "rwe_warnings_short" },
    { id = "showHUD",             section = "events",  key = "showHUD",             type = "bool",  admin = false, l10n = "rwe_show_hud_short" },
    { id = "hudScale",            section = "top",     key = "hudScale",            type = "float", admin = false, min = 0.6, max = 1.8, l10n = "rwe_hud_scale_short" },
    { id = "economicEvents",      section = "events",  key = "economicEvents",      type = "bool",  admin = true,  l10n = "rwe_economic_short" },
    { id = "vehicleEvents",       section = "events",  key = "vehicleEvents",       type = "bool",  admin = true,  l10n = "rwe_vehicle_short" },
    { id = "fieldEvents",         section = "events",  key = "fieldEvents",         type = "bool",  admin = true,  l10n = "rwe_field_short" },
    { id = "wildlifeEvents",      section = "events",  key = "wildlifeEvents",      type = "bool",  admin = true,  l10n = "rwe_wildlife_short" },
    { id = "specialEvents",       section = "events",  key = "specialEvents",       type = "bool",  admin = true,  l10n = "rwe_special_short" },
    { id = "physicsEnabled",      section = "physics", key = "enabled",             type = "bool",  admin = true,  l10n = "rwe_physics_enabled_short" },
    { id = "wheelGripMultiplier", section = "physics", key = "wheelGripMultiplier", type = "float", admin = true,  min = 0.5, max = 2.0, l10n = "rwe_wheel_grip_short" },
    { id = "suspensionStiffness", section = "physics", key = "suspensionStiffness", type = "float", admin = true,  min = 0.5, max = 2.0, l10n = "rwe_suspension_short" },
    { id = "showPhysicsInfo",     section = "physics", key = "showPhysicsInfo",     type = "bool",  admin = false, l10n = "rwe_physics_info_short" },
    { id = "debugMode",           section = "debug",   key = "enabled",             type = "bool",  admin = false, l10n = "rwe_debug_short" },
    { id = "experimentalSystems", section = "top",     key = "experimentalSystems", type = "bool",  admin = true,  l10n = "rwe_experimental_short" },
}

local BY_ID = {}
for _, d in ipairs(SETTINGS) do BY_ID[d.id] = d end

local function resolveLabel(desc)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(desc.l10n) then
        return g_i18n:getText(desc.l10n)
    end
    return desc.id
end

-- Read the live value for a descriptor from the nested settings tables.
local function getValue(mgr, desc)
    if desc.section == "top" then
        return mgr[desc.key]
    end
    local t = mgr[desc.section]
    return t and t[desc.key]
end

-- Apply an edit made through SettingsHub back onto the mod's own settings.
local function applyChange(id, value)
    local mgr = g_RandomWorldEvents
    if mgr == nil then return end
    local desc = BY_ID[id]
    if desc == nil then return end

    if desc.section == "top" then
        mgr[desc.key] = value
        -- Push HUD scale to the live overlay immediately, like the ESC handler.
        if id == "hudScale" and mgr.eventHUD then
            mgr.eventHUD.scale = value
        end
    elseif desc.section == "debug" then
        -- debug.enabled drives showDebugInfo in lockstep (same as the ESC handler).
        mgr.debug.enabled       = value
        mgr.debug.showDebugInfo = value
    else
        local t = mgr[desc.section]
        if t ~= nil then t[desc.key] = value end
    end

    if type(mgr.saveSettings) == "function" then mgr:saveSettings() end
end

function RWESettingsHubBridge.register(mgr)
    local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
    if hub == nil then
        Logging.info("[RWE] SettingsHub not detected; skipping tablet registration")
        return
    end
    if mgr == nil then return end

    local defs = {}
    for _, desc in ipairs(SETTINGS) do
        defs[#defs + 1] = {
            id        = desc.id,
            type      = desc.type,
            default   = getValue(mgr, desc),
            adminOnly = desc.admin,
            min       = desc.min,
            max       = desc.max,
            label     = resolveLabel(desc),
        }
    end

    local ok, err = pcall(function()
        hub:registerModule("RandomWorldEvents", {
            adminSettings = defs,
            onChange      = function(key, value, playerId) applyChange(key, value) end,
            selfPersisted = true,
        })
    end)

    if ok then
        Logging.info("[RWE] Registered with SettingsHub (%d setting(s))", #defs)
    else
        Logging.warning("[RWE] SettingsHub registration failed: %s", tostring(err))
    end
end
