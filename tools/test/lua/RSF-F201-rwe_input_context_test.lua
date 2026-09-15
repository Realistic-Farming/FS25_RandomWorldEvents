--!load: tools/test/lua/f201_model_binding.lua, utils/RWEContextInput.lua, RandomWorldEvents.lua
-- RSF-F201, RandomWorldEvents input through the REAL RandomWorldEvents.lua driven
-- by its own Mission00 / FSBaseMission hooks (the prelude chains appended and
-- prepended hooks). Witnesses: loadFinished catch-up registers all three actions
-- (drag included) when RWE owns the HUD keys; an existing complete VEHICLE set
-- opens no begin/end; RWE_InputHookRecord survives while the settings table is
-- rebuilt; delete retires without restoring. Model binding, not the native one.

local noop = function() end
local b = F201Model.installEngine({ "RWE_TOGGLE_HUD", "RWE_TOGGLE_SETTINGS", "RWE_HUD_DRAG" })
local nativeCalls = 0
PlayerInputComponent.registerActionEvents = function() nativeCalls = nativeCalls + 1 end
local nativePlayer = PlayerInputComponent.registerActionEvents
local nativeVehicle = b.endActionEventsModification

FSBaseMission.INGAME_NOTIFICATION_OK = FSBaseMission.INGAME_NOTIFICATION_OK or 1
RWEEventHUD = { new = function() return { visible = true, editMode = false, saveLayout = noop, delete = noop,
    toggleVisibility = noop, enterEditMode = noop, exitEditMode = noop, update = noop, draw = noop } end }
RWESettingsPanel = { new = function() return { delete = noop, toggle = noop, isOpen = false, update = noop, draw = noop } end }

local mission = {
    getIsClient = function() return true end,
    getIsServer = function() return true end,
    addIngameNotification = noop,
    missionInfo = {},
    environment = { currentDay = 1 },
}
g_currentMission = mission
g_masterHUD = nil

-- GROUP A: Mission00.load builds the manager and installs + activates
Mission00.load(mission)
local mgr = g_RandomWorldEvents
T.ok("F201 RWE A1 manager created", mgr ~= nil)
local wPlayer, wVehicle = PlayerInputComponent.registerActionEvents, InputBinding.endActionEventsModification
T.ok("F201 RWE A2 PLAYER wrapper installed", wPlayer ~= nativePlayer)
T.ok("F201 RWE A3 VEHICLE wrapper installed", wVehicle ~= nativeVehicle)
T.ok("F201 RWE A4 record lives on RWE_InputHookRecord", type(RWE_InputHookRecord) == "table" and RWE_InputHookRecord.input ~= nil)
local record = RWE_InputHookRecord.input
T.eq("F201 RWE A5 record active for this manager", record.owner, mgr)
T.eq("F201 RWE A6 settings table not used as the home", RandomWorldEvents._f201Input, nil)

-- GROUP B: loadFinished catch-up registers the complete PLAYER set including drag
b:context("PLAYER")
Mission00.loadMission00Finished(mission)
T.eq("F201 RWE B1 three PLAYER registrations", b:totalIn("PLAYER"), 3)
T.ok("F201 RWE B2 HUD toggle handle", mgr.hudPlayerEventId ~= nil)
T.ok("F201 RWE B3 settings handle", mgr.settingsPlayerEventId ~= nil)
T.ok("F201 RWE B4 drag handle (the old net skipped drag)", mgr.hudDragPlayerEventId ~= nil)
T.eq("F201 RWE B5 settings key hint falls back when the getter is absent", mgr.settingsKeyHint, "Shift+O")
T.eq("F201 RWE B6 drag label set", b.events[mgr.hudDragPlayerEventId].text, "input_RWE_HUD_DRAG")
local attemptsAfterPlayer = b.attempts
wPlayer({ player = { isOwner = true } })
T.eq("F201 RWE B7 the PLAYER wrapper finds a complete set", b.attempts, attemptsAfterPlayer)

-- GROUP C: VEHICLE set, then a complete set opens no bracket
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 RWE C1 three VEHICLE registrations", b:totalIn("VEHICLE"), 3)
T.ok("F201 RWE C2 vehicle identities differ from player ones", mgr.hudVehicleEventId ~= mgr.hudPlayerEventId)
T.eq("F201 RWE C3 cab settings row hidden as before", b.events[mgr.settingsVehicleEventId].displayIsVisible, false)
T.eq("F201 RWE C4 cab HUD row labelled as before", b.events[mgr.hudVehicleEventId].text, "input_RWE_TOGGLE_HUD")
local begun, attempts = b.begun, b.attempts
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 RWE C5 complete VEHICLE set: only the engine bracket", b.begun, begun + 1)
T.eq("F201 RWE C6 no registration spent", b.attempts, attempts)
T.ok("F201 RWE C7 PLAYER events untouched by the cab pass", b.events[mgr.hudPlayerEventId] ~= nil)

-- GROUP D: rebuilt cab (the old early return skipped this) registers again
b:deleteContext("VEHICLE")
FSBaseMission.update(mission, 16)
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 RWE D1 rebuilt cab registers the three again", b:totalIn("VEHICLE"), 3)
T.ok("F201 RWE D2 PLAYER still resident", b.events[mgr.settingsPlayerEventId] ~= nil)

-- GROUP E: the hook record survives while the settings table is rebuilt
local rec = RWE_InputHookRecord.input
local savedClass = RandomWorldEvents
RandomWorldEvents = { MOD_NAME = "FS25_RandomWorldEvents", events = {} }  -- bare literal, as on a reload
T.eq("F201 RWE E1 record identity survives", RWE_InputHookRecord.input, rec)
T.ok("F201 RWE E2 predecessors still held", rec.playerOriginal ~= nil and rec.vehicleOriginal ~= nil)
RandomWorldEvents = savedClass

-- GROUP F: delete retires without restoring
FSBaseMission.delete(mission)
T.eq("F201 RWE F1 record inactive", rec.active, false)
T.eq("F201 RWE F2 PLAYER wrapper not restored", PlayerInputComponent.registerActionEvents, wPlayer)
T.eq("F201 RWE F3 VEHICLE wrapper not restored", InputBinding.endActionEventsModification, wVehicle)
T.eq("F201 RWE F4 manager handle dropped", g_RandomWorldEvents, nil)
b:deleteContext("VEHICLE")
b:beginActionEventsModification("VEHICLE"); b:endActionEventsModification()
T.eq("F201 RWE F5 retired owner registers nothing", b:totalIn("VEHICLE"), 0)
