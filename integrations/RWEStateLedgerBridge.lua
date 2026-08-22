-- =========================================================
-- Random World Events - StateLedger bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_StateLedger (bedrock). RWE ships standalone, so this
-- is strictly delegate-when-present, mirroring SoilFertilizer / TaxMod:
--   * StateLedger installed -> the shared master save file is the LOAD source of
--     truth for RWE's runtime STATE: the active-event snapshot (which event is
--     running, how much of it and the cooldown remain, whether the midpoint has
--     already fired). The mod's own FS25_RandomWorldEvents.xml is still written
--     every save as the standalone safety copy, so removing the ledger later
--     never loses data.
--   * StateLedger absent -> nothing changes; the own XML is primary as always.
--
-- ONE module: RandomWorldEvents_EventState. Settings are NOT a StateLedger module
-- here; settings live in SettingsHub's domain (RWESettingsHubBridge) and the own
-- XML keeps them as the standalone fallback. A second settings copy in a ledger
-- module would just be a conflicting duplicate. This matches TaxMod, whose ledger
-- module carries state, not settings.
--
-- Timing note (same as TaxMod): the mod imports the own-XML snapshot into the
-- _saved* temp fields in loadSettings (Mission00.load), a phase BEFORE this
-- bridge registers (loadMission00Finished, the same phase StateLedger parses its
-- file in). So register() force-triggers the idempotent parseFile after
-- registering, guaranteeing deserialize has delivered before the caller reads
-- hasState(), independent of mod load order. applyState() then overwrites the
-- _saved* fields, and loadFinished's existing restore block consumes them, so the
-- single restore path (with its vehicle-event skip + absolute-time math) is shared
-- by both the own-XML and the ledger loads and the two can never diverge.
--
-- Number keys / nested tables round-trip through StateLedgerXML fine, but this
-- block is deliberately flat scalars (string + numbers + bool) so it is trivially
-- safe.
--
-- The cross-mod handle is g_currentMission.stateLedger (published in Mission00.load).
-- =========================================================

RWEStateLedgerBridge = RWEStateLedgerBridge or {}

-- LOCKED persistence key. Never renamed after first persist (a later rename
-- orphans saved event state). Matches the <Mod>_<Thing> convention.
RWEStateLedgerBridge.MODULE_ID = "RandomWorldEvents_EventState"
RWEStateLedgerBridge.SCHEMA    = 1

RWEStateLedgerBridge.active       = false   -- ledger present and we registered
RWEStateLedgerBridge.delivered    = false   -- deserialize has fired (once)
RWEStateLedgerBridge.pendingState = nil     -- cached table (nil = new save / no block)

-- Compose the active-event snapshot as remaining-time offsets, exactly the way
-- saveSettings writes it into the own XML so timers survive a reload (absolute
-- g_currentMission.time is reset on load). serialize runs at the game's save
-- cycle, when g_currentMission.time is valid.
function RWEStateLedgerBridge.buildState(mgr)
    local out = {
        schema              = RWEStateLedgerBridge.SCHEMA,
        activeEvent         = "",
        remainingMs         = 0,
        cooldownRemainingMs = 0,
        midpointFired       = false,
    }

    local es = mgr ~= nil and mgr.EVENT_STATE or nil
    if es ~= nil and g_currentMission ~= nil then
        if es.activeEvent ~= nil then
            out.activeEvent   = es.activeEvent
            out.remainingMs   = math.max(0, (es.eventStartTime + (es.eventDuration or 0)) - g_currentMission.time)
            out.midpointFired = es.midpointFired or false
        end
        out.cooldownRemainingMs = math.max(0, (es.cooldownUntil or 0) - g_currentMission.time)
    end

    return out
end

-- True when the ledger is the state load source of truth this session (present,
-- registered, and it delivered an actual block).
function RWEStateLedgerBridge.hasState()
    return RWEStateLedgerBridge.active
        and RWEStateLedgerBridge.delivered
        and RWEStateLedgerBridge.pendingState ~= nil
end

-- Apply the cached ledger snapshot by overwriting the mod's _saved* temp fields.
-- loadFinished's existing restore block then reconstructs EVENT_STATE from these,
-- so the ledger overrides whatever loadSettings imported from the own XML.
-- Returns true when a real block was applied.
function RWEStateLedgerBridge.applyState(mgr)
    local data = RWEStateLedgerBridge.pendingState
    if type(data) ~= "table" or mgr == nil then return false end

    local active = data.activeEvent
    mgr._savedActiveEvent         = (type(active) == "string" and active ~= "") and active or nil
    mgr._savedRemainingMs         = tonumber(data.remainingMs) or 0
    mgr._savedCooldownRemainingMs = tonumber(data.cooldownRemainingMs) or 0
    mgr._savedMidpointFired       = data.midpointFired == true
    return true
end

-- Register with StateLedger if present. Called from loadFinished
-- (loadMission00Finished), after loadSettings() has imported the own-XML copy.
function RWEStateLedgerBridge.register(mgr)
    -- Reset per-load so a map swap / reload starts clean.
    RWEStateLedgerBridge.active       = false
    RWEStateLedgerBridge.delivered    = false
    RWEStateLedgerBridge.pendingState = nil

    local ledger = (g_currentMission ~= nil and g_currentMission.stateLedger) or g_stateLedger
    if ledger == nil then
        Logging.info("[RWE] StateLedger not detected; event state uses its own FS25_RandomWorldEvents.xml")
        return
    end
    if mgr == nil then return end

    local ok, err = pcall(function()
        ledger:registerModule(RWEStateLedgerBridge.MODULE_ID, {
            serialize = function()
                return RWEStateLedgerBridge.buildState(mgr)
            end,
            deserialize = function(data)
                RWEStateLedgerBridge.delivered    = true
                RWEStateLedgerBridge.pendingState = data   -- nil on a brand-new save
            end,
        })
    end)

    if not ok then
        Logging.warning("[RWE] StateLedger registration failed: %s (falling back to own XML)", tostring(err))
        return
    end

    RWEStateLedgerBridge.active = true

    -- Force the (idempotent) parse now so deserialize has delivered before the
    -- caller checks hasState() a few lines later, independent of which mod's
    -- loadMission00Finished handler ran first. A no-op if StateLedger already
    -- parsed (it loaded first).
    if ledger.parseFile ~= nil then
        pcall(function() ledger:parseFile() end)
    end

    Logging.info("[RWE] Registered with StateLedger as '%s' (FS25_RandomWorldEvents.xml kept as safety copy)",
        RWEStateLedgerBridge.MODULE_ID)
end
