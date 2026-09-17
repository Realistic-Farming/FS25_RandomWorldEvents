-- =========================================================
-- Random World Events - statement-line settlement (EC-6)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Every money event is a statement line that settles once at the next in-game
-- day, for every eligible farm (EC-6 brief v1.7 section 3.3). Before EC-6 money
-- moved instantly to g_currentMission.player.farmId, which nothing assigns, so it
-- reached farm 0 in every mode and addMoney refused it: most money events never
-- paid anyone. Now they do, which players will feel as a balance change.
--
-- ONE OWNER FUNCTION, TWO DOORS. settle() is the only money writer. The native
-- door (MessageType.DAY_CHANGED) always runs, whatever the events-enabled setting
-- says; Time Guard's day accrual is a second door when present. Both may fire on
-- the same day change; the second finds nothing due.
--
-- EACH LINE PAID ONCE, AND ONLY TO THE FARM OBJECT IT WAS QUEUED FOR. The line is
-- removed before addMoney, so a failure between the two loses that one line
-- (logged) rather than paying it twice. addMoney returns nothing in every case, so
-- the notice and the TaxMod mirror run only when the farm id still resolves to the
-- same Farm object afterwards. A new farm that takes a deleted farm's id is a new
-- Farm object, so it never receives, and a late FARM_DELETED never removes, the old
-- farm's lines.
--
-- Server only. farmRef lives in memory; it is never saved or sent.
-- =========================================================

RWESettlement = RWESettlement or {}
local S = RWESettlement

S.ACCRUAL_ID  = "RandomWorldEvents_settlement"
S.MONEY_TYPES = { OTHER = true, LOAN_INTEREST = true, VEHICLE_REPAIR = true }

S.pending        = S.pending or {}   -- farmId -> ordered list of lines
S.unbound        = S.unbound         -- restored lines waiting for the farms to load
S.subscribed     = S.subscribed or false
S.accrualLive    = S.accrualLive or false

local function log(msg, ...)
    if select("#", ...) > 0 then msg = string.format(msg, ...) end
    Logging.info("[RWE] settlement: " .. msg)
end

local function isServer() return g_server ~= nil end

local function currentDay()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    return env ~= nil and env.currentMonotonicDay or nil
end

local function farmById(farmId)
    if g_farmManager == nil or type(g_farmManager.getFarmById) ~= "function" then return nil end
    local ok, farm = pcall(g_farmManager.getFarmById, g_farmManager, farmId)
    if ok then return farm end
    return nil
end

--- Ascending numeric keys of a table. settle and serialize walk farms in this order,
--- never in pairs order: the bench's fengari pairs is insertion ordered and cannot
--- catch a pairs regression, so the order is made explicit here instead.
local function sortedFarmIds(t)
    local ids = {}
    for id in pairs(t) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end
S.sortedFarmIds = sortedFarmIds

function S.reset()
    S.pending = {}
    S.unbound = nil
end

-- =========================================================
-- Candidates and eligibility
-- =========================================================

--- Every farm except the spectator and guided-tour farms, ascending by id.
function S.candidateFarms()
    local out = {}
    if g_farmManager == nil or type(g_farmManager.getFarms) ~= "function" then return out end
    local ok, farms = pcall(g_farmManager.getFarms, g_farmManager)
    if not ok or type(farms) ~= "table" then return out end
    local spectator = FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID or 0
    local tour = FarmManager ~= nil and FarmManager.GUIDED_TOUR_FARM_ID or nil
    for _, farm in pairs(farms) do
        local id = type(farm) == "table" and farm.farmId or nil
        if type(id) == "number" and id ~= spectator and id ~= tour then
            out[#out + 1] = farm
        end
    end
    table.sort(out, function(a, b) return a.farmId < b.farmId end)
    return out
end

--- Husbandries on the map, each call pcall-guarded; a throw counts as zero animals.
local function animalsIn(placeable)
    if type(placeable) ~= "table" or type(placeable.getNumOfAnimals) ~= "function" then return 0 end
    local ok, n = pcall(placeable.getNumOfAnimals, placeable)
    if ok and type(n) == "number" then return n end
    return 0
end

local function ownerOf(object)
    if type(object) ~= "table" or type(object.getOwnerFarmId) ~= "function" then return nil end
    local ok, id = pcall(object.getOwnerFarmId, object)
    if ok then return id end
    return nil
end

local function husbandries()
    local sys = g_currentMission ~= nil and g_currentMission.husbandrySystem or nil
    return sys ~= nil and type(sys.placeables) == "table" and sys.placeables or {}
end

local function vehicles()
    local sys = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    return sys ~= nil and type(sys.vehicles) == "table" and sys.vehicles or {}
end

--- Any husbandry on the map, whatever its owner, has at least one animal. Reads no
--- local player and no farm list, so it answers the same on every kind of server.
function S.mapHasAnimals()
    for _, p in pairs(husbandries()) do
        if animalsIn(p) > 0 then return true end
    end
    return false
end

--- A husbandry owned by this farm has at least one animal.
function S.farmHasAnimals(farmId)
    for _, p in pairs(husbandries()) do
        if ownerOf(p) == farmId and animalsIn(p) > 0 then return true end
    end
    return false
end

--- The farm's vehicles, as the vehicle system holds them. A vehicle an NPC or helper
--- is driving still belongs to the farm.
function S.farmVehicles(farmId)
    local out = {}
    for _, v in pairs(vehicles()) do
        if ownerOf(v) == farmId then out[#out + 1] = v end
    end
    return out
end

function S.farmHasMotorized(farmId)
    for _, v in ipairs(S.farmVehicles(farmId)) do
        if v.spec_motorized ~= nil then return true end
    end
    return false
end

local function damageOf(v)
    if type(v.getDamageAmount) ~= "function" then return 0 end
    local ok, d = pcall(v.getDamageAmount, v)
    if ok and type(d) == "number" then return d end
    return 0
end

--- The farm's vehicles with damage above 0.1.
function S.farmDamagedVehicles(farmId)
    local out = {}
    for _, v in ipairs(S.farmVehicles(farmId)) do
        if damageOf(v) > 0.1 then out[#out + 1] = v end
    end
    return out
end

--- The farm's native loan (Farm:getLoan), or 0.
function S.loanOf(farm)
    if type(farm) ~= "table" then return 0 end
    if type(farm.getLoan) == "function" then
        local ok, loan = pcall(farm.getLoan, farm)
        if ok and type(loan) == "number" then return loan end
        return 0
    end
    return type(farm.loan) == "number" and farm.loan or 0
end

--- A loan line amount: floor(loan x rate x intensity), or nil when below 1.
function S.loanLine(farm, rate, intensity)
    local amount = math.floor(S.loanOf(farm) * rate * intensity)
    if amount >= 1 then return amount end
    return nil
end

--- True when at least one candidate farm passes the predicate.
function S.anyFarm(predicate)
    for _, farm in ipairs(S.candidateFarms()) do
        local ok, yes = pcall(predicate, farm)
        if ok and yes then return true end
    end
    return false
end

-- =========================================================
-- Queue
-- =========================================================

--- Append one line for a farm. Lines are never merged or overwritten.
---@return boolean queued
function S.queue(eventName, farmId, amount, moneyTypeName, labelKey)
    if not isServer() then return false end
    if type(amount) ~= "number" or amount ~= amount or amount == 0 or math.floor(amount) ~= amount then return false end
    if not S.MONEY_TYPES[moneyTypeName] then return false end
    local farm = farmById(farmId)
    local day = currentDay()
    if farm == nil or day == nil then return false end
    S.pending[farmId] = S.pending[farmId] or {}
    local list = S.pending[farmId]
    list[#list + 1] = {
        eventName = eventName, amount = amount, moneyTypeName = moneyTypeName,
        labelKey = labelKey, queuedDay = day, farmRef = farm,
    }
    return true
end

--- Queue one line per candidate farm; amountFor(farm) returns a signed whole amount
--- or nil for an ineligible farm. The amount is rolled and fixed here; settlement
--- never re-rolls or re-reads. Returns the number of lines queued.
function S.queueForFarms(eventName, moneyTypeName, labelKey, amountFor)
    local n = 0
    for _, farm in ipairs(S.candidateFarms()) do
        local ok, amount = pcall(amountFor, farm)
        if ok and amount ~= nil and S.queue(eventName, farm.farmId, amount, moneyTypeName, labelKey) then
            n = n + 1
        end
    end
    return n
end

-- =========================================================
-- Settle
-- =========================================================

local function sendNotice(farmId, labelKey, amount)
    if RWESettlementNoticeEvent == nil or g_currentMission == nil then return end
    if type(g_currentMission.broadcastEventToFarm) == "function" then
        pcall(g_currentMission.broadcastEventToFarm, g_currentMission, RWESettlementNoticeEvent.new(labelKey, amount), farmId, false)
    end
    -- The host connection is skipped by the broadcast; a listen host on that farm
    -- sees its own notice here, the way the native money notice does. getFarmId()
    -- is nil on a dedicated server, so this never runs there.
    if type(g_currentMission.getFarmId) == "function" then
        local ok, localFarm = pcall(g_currentMission.getFarmId, g_currentMission)
        if ok and localFarm ~= nil and localFarm == farmId then
            RWESettlementNoticeEvent.show(labelKey, amount)
        end
    end
end

local function mirrorToTaxMod(farmId, amount, labelKey)
    local tax = g_TaxManager
    if tax == nil or type(tax.recordExpense) ~= "function" then return end
    local label = labelKey
    if g_i18n ~= nil and type(g_i18n.getText) == "function" and labelKey ~= nil then
        local okT, text = pcall(g_i18n.getText, g_i18n, labelKey)
        if okT and type(text) == "string" then label = text end
    end
    local ok, result = pcall(tax.recordExpense, farmId, amount, label)
    if not ok or result ~= true then
        log("TaxMod mirror for farm %d (%s) not recorded (%s); money already posted", farmId, tostring(labelKey), tostring(ok and result or "error"))
    end
end

--- Settle every line queued before today. Server only; never throws.
--- ctx (Time Guard's settle context) is ignored.
function S.settle(ctx)
    if not isServer() then return 0 end
    local okAll, paid = pcall(function()
        S.bindRestored()
        local day = currentDay()
        if day == nil then return 0 end
        local count = 0
        for _, farmId in ipairs(sortedFarmIds(S.pending)) do
            local list = S.pending[farmId]
            local farm = farmById(farmId)
            if farm == nil then
                log("farm %d no longer exists; %d pending line(s) dropped", farmId, #list)
                S.pending[farmId] = nil
            else
                local i = 1
                while i <= #list do
                    local line = list[i]
                    if line.queuedDay >= day then
                        i = i + 1   -- queued today: stays
                    else
                        -- Removed from the live table BEFORE any money write, so a
                        -- failure (or a re-entrant settle) can lose it but never pay it twice.
                        table.remove(list, i)
                        if farm ~= line.farmRef then
                            log("farm id %d now belongs to another farm; line '%s' (%s) dropped", farmId, tostring(line.eventName), tostring(line.amount))
                        elseif type(line.amount) ~= "number" or line.amount ~= line.amount or line.amount == 0 or math.floor(line.amount) ~= line.amount then
                            log("line '%s' for farm %d has an invalid amount and was dropped", tostring(line.eventName), farmId)
                        else
                            local okMoney = pcall(g_currentMission.addMoney, g_currentMission, line.amount, farmId,
                                MoneyType ~= nil and MoneyType[line.moneyTypeName] or nil, true, true)
                            if not okMoney then
                                log("addMoney threw for '%s', farm %d, amount %d; the line is lost, not retried", tostring(line.eventName), farmId, line.amount)
                            elseif farmById(farmId) == line.farmRef then
                                count = count + 1
                                sendNotice(farmId, line.labelKey, line.amount)
                                mirrorToTaxMod(farmId, line.amount, line.labelKey)
                            end
                        end
                    end
                end
                if #list == 0 and S.pending[farmId] == list then S.pending[farmId] = nil end
            end
        end
        return count
    end)
    if not okAll then
        log("settle failed (%s)", tostring(paid))
        return 0
    end
    return paid
end

--- MessageType.FARM_DELETED(farmId). A nil farm drops every line for the id; a
--- reused id keeps only the new farm's own lines.
function S.onFarmDeleted(farmId)
    if not isServer() or type(farmId) ~= "number" then return end
    local list = S.pending[farmId]
    if list == nil then return end
    local current = farmById(farmId)
    if current == nil then
        log("farm %d deleted; %d pending line(s) dropped", farmId, #list)
        S.pending[farmId] = nil
        return
    end
    local keep = {}
    for _, line in ipairs(list) do
        if line.farmRef == current then
            keep[#keep + 1] = line
        else
            log("farm %d deleted and its id reused; line '%s' (%d) of the deleted farm dropped", farmId, tostring(line.eventName), line.amount)
        end
    end
    if #keep > 0 then S.pending[farmId] = keep else S.pending[farmId] = nil end
end

-- =========================================================
-- Doors
-- =========================================================

S._dayListener = S._dayListener or {}
function S._dayListener:onDayChanged() S.settle() end
function S._dayListener:onFarmDeleted(farmId) S.onFarmDeleted(farmId) end

--- Subscribe the native door and the farm-deleted watch, and register the Time
--- Guard door when present. Called at loadMission00Finished on the server; the
--- day subscription does not depend on the events-enabled setting.
function S.install()
    if not isServer() then return end
    if not S.subscribed and g_messageCenter ~= nil and MessageType ~= nil then
        if MessageType.DAY_CHANGED ~= nil then
            g_messageCenter:subscribe(MessageType.DAY_CHANGED, S._dayListener.onDayChanged, S._dayListener)
        end
        if MessageType.FARM_DELETED ~= nil then
            g_messageCenter:subscribe(MessageType.FARM_DELETED, S._dayListener.onFarmDeleted, S._dayListener)
        end
        S.subscribed = true
    end
    local tg = (g_currentMission ~= nil and g_currentMission.timeGuard) or g_timeGuard
    if tg ~= nil and type(tg.registerAccrual) == "function" and not S.accrualLive then
        local ok, registered = pcall(tg.registerAccrual, tg, S.ACCRUAL_ID, {
            cadence = "day", flowClass = "event", firstPeriodPolicy = "full", priority = 150,
            onSettle = function(ctx) S.settle(ctx) end,
        })
        S.accrualLive = ok and registered ~= false
    end
end

--- Delete path: the accrual, the day subscription and the farm-deleted subscription.
function S.uninstall()
    if S.accrualLive then
        local tg = (g_currentMission ~= nil and g_currentMission.timeGuard) or g_timeGuard
        if tg ~= nil and type(tg.unregisterAccrual) == "function" then
            pcall(tg.unregisterAccrual, tg, S.ACCRUAL_ID)
        end
        S.accrualLive = false
    end
    if S.subscribed and g_messageCenter ~= nil and MessageType ~= nil then
        if type(g_messageCenter.unsubscribe) == "function" then
            if MessageType.DAY_CHANGED ~= nil then pcall(g_messageCenter.unsubscribe, g_messageCenter, MessageType.DAY_CHANGED, S._dayListener) end
            if MessageType.FARM_DELETED ~= nil then pcall(g_messageCenter.unsubscribe, g_messageCenter, MessageType.FARM_DELETED, S._dayListener) end
        end
        S.subscribed = false
    end
    S.reset()
end

-- =========================================================
-- Persistence
-- =========================================================

--- Detached saved form: { { farmId, lines = { { event, amount, type, label, day } } } },
--- farms ascending, lines in queue order. A line whose farmRef no longer matches is
--- dropped with a log line instead of being saved. Restored lines still waiting
--- for their farms are written back unchanged.
function S.serialize()
    local out = {}
    local byFarm = {}
    for _, farmId in ipairs(sortedFarmIds(S.pending)) do
        local farm = farmById(farmId)
        local lines = {}
        for _, line in ipairs(S.pending[farmId]) do
            if farm ~= nil and farm == line.farmRef then
                lines[#lines + 1] = { event = line.eventName, amount = line.amount, type = line.moneyTypeName, label = line.labelKey, day = line.queuedDay }
            else
                log("stale line '%s' for farm %d not saved", tostring(line.eventName), farmId)
            end
        end
        if #lines > 0 then
            byFarm[farmId] = lines
        end
    end
    for _, entry in ipairs(S.unbound or {}) do
        local lines = byFarm[entry.farmId] or {}
        for _, l in ipairs(entry.lines) do lines[#lines + 1] = l end
        byFarm[entry.farmId] = lines
    end
    for _, farmId in ipairs(sortedFarmIds(byFarm)) do
        out[#out + 1] = { farmId = farmId, lines = byFarm[farmId] }
    end
    return out
end

--- Validate a saved list, dropping malformed entries. Pure.
function S.validateSaved(saved)
    local out = {}
    if type(saved) ~= "table" then return out end
    for _, entry in ipairs(saved) do
        local farmId = type(entry) == "table" and tonumber(entry.farmId) or nil
        if farmId ~= nil and type(entry.lines) == "table" then
            local lines = {}
            for _, l in ipairs(entry.lines) do
                local amount = type(l) == "table" and tonumber(l.amount) or nil
                local day = type(l) == "table" and tonumber(l.day) or nil
                if amount ~= nil and amount ~= 0 and math.floor(amount) == amount and day ~= nil
                   and S.MONEY_TYPES[l.type] and type(l.event) == "string" and type(l.label) == "string" then
                    lines[#lines + 1] = { event = l.event, amount = amount, type = l.type, label = l.label, day = day }
                end
            end
            if #lines > 0 then out[#out + 1] = { farmId = farmId, lines = lines } end
        end
    end
    return out
end

--- Restore saved lines untouched. They are bound to their Farm objects on the
--- first server update: at loadMission00Finished the farms are still an async task
--- queued inside that function (mission00.lua:408-411), so every getFarmById would
--- be nil and every line would be dropped.
function S.restore(saved)
    S.unbound = S.validateSaved(saved)
    if #S.unbound == 0 then S.unbound = nil end
end

--- Bind restored lines to the current Farm objects. A farm id with no farm drops
--- its lines with a log line. Load publishes no day change, so they settle at the
--- next real day change.
function S.bindRestored()
    if S.unbound == nil or not isServer() then return end
    local unbound = S.unbound
    S.unbound = nil
    for _, entry in ipairs(unbound) do
        local farm = farmById(entry.farmId)
        if farm == nil then
            log("saved lines for farm %d dropped: no such farm after load", entry.farmId)
        else
            S.pending[entry.farmId] = S.pending[entry.farmId] or {}
            local list = S.pending[entry.farmId]
            for _, l in ipairs(entry.lines) do
                list[#list + 1] = { eventName = l.event, amount = l.amount, moneyTypeName = l.type, labelKey = l.label, queuedDay = l.day, farmRef = farm }
            end
        end
    end
end

--- Own XML: eventState.settlement.farm(?)#id with line(?)#event, #amount, #type, #label, #day.
function S.saveToXML(xml, baseKey)
    S.saveListToXML(xml, baseKey, S.serialize())
end

--- Write a detached saved list (from serialize, or a saved snapshot).
function S.saveListToXML(xml, baseKey, saved)
    for i, entry in ipairs(saved or {}) do
        local farmKey = string.format("%s.settlement.farm(%d)", baseKey, i - 1)
        xml:setInt(farmKey .. "#id", entry.farmId)
        for j, l in ipairs(entry.lines) do
            local lineKey = string.format("%s.line(%d)", farmKey, j - 1)
            xml:setString(lineKey .. "#event", l.event)
            xml:setInt(lineKey .. "#amount", l.amount)
            xml:setString(lineKey .. "#type", l.type)
            xml:setString(lineKey .. "#label", l.label)
            xml:setInt(lineKey .. "#day", l.day)
        end
    end
end

function S.loadFromXML(xml, baseKey)
    local saved = {}
    local i = 0
    while true do
        local farmKey = string.format("%s.settlement.farm(%d)", baseKey, i)
        local farmId = xml:getInt(farmKey .. "#id")
        if farmId == nil then break end
        local lines = {}
        local j = 0
        while true do
            local lineKey = string.format("%s.line(%d)", farmKey, j)
            local event = xml:getString(lineKey .. "#event")
            if event == nil then break end
            lines[#lines + 1] = {
                event = event, amount = xml:getInt(lineKey .. "#amount"), type = xml:getString(lineKey .. "#type"),
                label = xml:getString(lineKey .. "#label"), day = xml:getInt(lineKey .. "#day"),
            }
            j = j + 1
        end
        saved[#saved + 1] = { farmId = farmId, lines = lines }
        i = i + 1
    end
    return saved
end
