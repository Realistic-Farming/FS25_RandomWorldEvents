--!load: tools/test/lua/ec6_harness.lua, utils/RWESettlement.lua, events/RWESettlementNoticeEvent.lua
-- MAINT-246-taxmanager_handle_spec_test.lua - MAINTENANCE row 246 (Bob's fleet sweep row 5): an event
-- settlement reaches TaxMod's companion ledger in a game.
--
-- THE DEFECT THIS PINS (development 4087d6e): RWESettlement's mirrorToTaxMod read TaxMod through the
-- bare global g_TaxManager. TaxMod writes that global into its own mod environment (getfenv(0),
-- TaxMod main.lua:1158 at 32fed17), so the read was nil in a game and no settlement was ever
-- mirrored. TaxMod also publishes the same table on the mission (:1159, mission.taxManager).
--
-- THE FIX: mirrorToTaxMod reads g_currentMission.taxManager first, the bare global as the fallback.
--
-- THE ENTRY-POINT BAR IS GROUP E. TaxMod is modelled in its own mod environment, built as dataS
-- mods.lua:482-520 builds one (__index = _G, _G the env itself, getfenv(0) mapped to it), and its
-- onLoad publish (main.lua:1158-1159) runs inside it. Its recordExpense is verbatim from
-- main.lua:957-1008 at 32fed17, with the file-level locals it closes over (modName, ledger,
-- LEDGER_MAX_ENTRIES, log) as main.lua declares them (:18, :84-85, :98). RandomWorldEvents enters
-- through its own door: S.install registers the settlement with the Time Guard on the mission, an
-- event queues a line, and the Time Guard's registered onSettle runs the next day. Nothing writes a
-- ledger entry by hand.
--
--   E0  the world: RWE's environment has no g_TaxManager; TaxMod's has it, and the mission carries it
--   E1  S.install registered the settlement with the Time Guard
--   E2  the next day's settle pays the line and TaxMod's own ledger records it (farm, amount, label)
--   E3  a second farm's line is recorded on its own farm, credits and debits on their sides

local S = RWESettlement

-- TaxMod, in its own mod environment (mods.lua:482-520).
local taxEnv = setmetatable({}, { __index = _G })
taxEnv._G = taxEnv
taxEnv.getfenv = function() return taxEnv end

local TAXMOD_LOAD = [==[
local mission = ...
local modName = "FS25_TaxMod"
local LEDGER_MAX_ENTRIES = 10
local ledger = { farms = {} }
local function log(msg, level) end
FS25TaxMod = FS25TaxMod or {}

-- TaxMod main.lua:957-1008 at 32fed17, verbatim.
function FS25TaxMod.recordExpense(a, b, c, d)
    -- Tolerate colon-style calls (g_TaxManager:recordExpense(...))
    local farmId, amount, label = a, b, c
    if a == FS25TaxMod then
        farmId, amount, label = b, c, d
    end

    if g_currentMission == nil or not g_currentMission:getIsServer() then
        Logging.warning("[%s] recordExpense: server-only API called on a non-server peer, ignoring", modName)
        return false
    end
    if type(farmId) ~= "number" or farmId <= 0 then
        Logging.warning("[%s] recordExpense: invalid farmId '%s' (positive number expected)", modName, tostring(farmId))
        return false
    end
    if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge or amount == 0 then
        Logging.warning("[%s] recordExpense: invalid amount '%s' (finite non-zero number expected)", modName, tostring(amount))
        return false
    end
    if label ~= nil and type(label) ~= "string" then
        Logging.warning("[%s] recordExpense: invalid label '%s' (string expected)", modName, tostring(label))
        return false
    end
    label = label or "Companion expense"

    local farmLedger = ledger.farms[farmId]
    if farmLedger == nil then
        farmLedger = { creditTotal = 0, debitTotal = 0, entries = {} }
        ledger.farms[farmId] = farmLedger
    end

    if amount > 0 then
        farmLedger.creditTotal = farmLedger.creditTotal + amount
    else
        farmLedger.debitTotal = farmLedger.debitTotal - amount
    end

    local env = g_currentMission.environment
    table.insert(farmLedger.entries, 1, {
        amount = amount,
        label  = label,
        day    = env and env.currentDay   or 0,
        month  = env and env.currentMonth or 0,
    })
    while #farmLedger.entries > LEDGER_MAX_ENTRIES do
        table.remove(farmLedger.entries)
    end

    log(string.format("recordExpense: farm %d %s%s (%s)", farmId,
        amount > 0 and "+" or "", tostring(amount), label), 2)
    return true
end

-- main.lua:1158-1159 at 32fed17 (onLoad's publish).
getfenv(0)["g_TaxManager"] = FS25TaxMod
mission.taxManager = FS25TaxMod
return ledger
]==]

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

S.uninstall()
S.reset()
g_TaxManager = nil
local w = EC6.world({ farms = { {1}, {2} }, day = 10 })
local tg = EC6.timeGuard()
g_currentMission.timeGuard = tg
local ledger = assert(load(TAXMOD_LOAD, "=FS25_TaxMod main.lua (model)", "t", taxEnv))(g_currentMission)

group("E0", function()
    T.eq("E0: RWE's environment has no g_TaxManager", g_TaxManager, nil)
    T.ok("E0: TaxMod's own environment has it", taxEnv.g_TaxManager ~= nil and taxEnv.g_TaxManager == taxEnv.FS25TaxMod)
    T.ok("E0: the mission carries TaxMod's manager", g_currentMission.taxManager == taxEnv.FS25TaxMod)
end)

group("E1", function()
    S.install()
    local def = tg.accruals[S.ACCRUAL_ID]
    T.ok("E1: S.install registered the settlement with the Time Guard", def ~= nil and type(def.onSettle) == "function")
end)

group("E2", function()
    T.eq("E2: a storm line is queued for farm 1", S.queue("storm", 1, -500, "OTHER", "rwe_label_storm"), true)
    EC6.setDay(w, 11)
    tg.accruals[S.ACCRUAL_ID].onSettle({})
    T.eq("E2: the next day's settle paid the line", #w.money, 1)
    local farm = ledger.farms[1]
    T.ok("E2: TaxMod's own ledger has farm 1", farm ~= nil)
    local entry = farm and farm.entries[1]
    T.eq("E2: the entry carries the amount", entry and entry.amount, -500)
    -- RWE translates the label key (mirrorToTaxMod); the prelude's g_i18n returns T(key).
    T.eq("E2: and the translated label", entry and entry.label, "T(rwe_label_storm)")
    T.eq("E2: the debit lands on the debit side", farm and farm.debitTotal, 500)
    T.eq("E2: no 'not recorded' line was logged", EC6.logged("not recorded"), false)
end)

group("E3", function()
    S.queue("windfall", 2, 300, "OTHER", "rwe_label_windfall")
    EC6.setDay(w, 12)
    tg.accruals[S.ACCRUAL_ID].onSettle({})
    local farm = ledger.farms[2]
    T.eq("E3: farm 2's credit is on farm 2", farm and farm.creditTotal, 300)
    T.eq("E3: farm 1's ledger is unchanged", ledger.farms[1] and #ledger.farms[1].entries, 1)
end)

S.uninstall()
