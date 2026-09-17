--!load: tools/test/lua/ec6_harness.lua, utils/RWESettlement.lua, events/RWESettlementNoticeEvent.lua
-- EC-6 RandomWorldEvents: statement-line settlement (brief v1.7 section 3.3).
-- Groups: Q queue and candidates, E eligibility helpers, S settle, D farm deletion,
-- I doors (DAY_CHANGED, Time Guard), P persistence, N private notice.
--
-- ITERATION ORDER: the bench runs fengari, whose pairs() walks keys in insertion
-- order, so it cannot reproduce the shipped runtime's hash order. S5 and P1 insert
-- farms OUT of ascending order so a pairs() regression pays or saves in insertion
-- order and fails here; a green run is not proof of hash-order safety beyond that.

local S = RWESettlement

local notices = {}
g_RandomWorldEvents = { notifyEvent = function(_, text, category, positive) notices[#notices + 1] = { text = text, category = category, positive = positive } end }

local mirror = {}
local function taxMod(result)
    g_TaxManager = { recordExpense = function(farmId, amount, label) mirror[#mirror + 1] = { farmId = farmId, amount = amount, label = label }; return result end }
end

local function fresh(opts)
    S.uninstall()
    S.reset()
    notices, mirror = {}, {}
    g_TaxManager = nil
    g_timeGuard = nil
    return EC6.world(opts)
end

local function pendingCount(farmId)
    local list = S.pending[farmId]
    return list ~= nil and #list or 0
end

-- =====================================================================
-- Q: queue and candidates
-- =====================================================================
do
    local w = fresh({ farms = { {3}, {0}, {1}, {16}, {2} } })
    local c = S.candidateFarms()
    T.eq("Q1a spectator and guided-tour farms excluded", #c, 3)
    T.eq("Q1b candidates ascending (manager order 3,0,1,16,2)", table.concat({ c[1].farmId, c[2].farmId, c[3].farmId }, ","), "1,2,3")

    g_server = nil
    T.eq("Q2 a client queues nothing", S.queue("x", 1, 100, "OTHER", "k"), false)
    w = fresh({ farms = { {1} } })
    T.eq("Q3a zero refused", S.queue("x", 1, 0, "OTHER", "k"), false)
    T.eq("Q3b fraction refused", S.queue("x", 1, 10.5, "OTHER", "k"), false)
    T.eq("Q3c NaN refused", S.queue("x", 1, 0/0, "OTHER", "k"), false)
    T.eq("Q3d unknown money type refused", S.queue("x", 1, 10, "WAGES", "k"), false)
    T.eq("Q3e unknown farm refused", S.queue("x", 9, 10, "OTHER", "k"), false)
    T.eq("Q3f nothing pending after refusals", pendingCount(1), 0)

    T.eq("Q4a first line", S.queue("a", 1, 100, "OTHER", "ka"), true)
    T.eq("Q4b second line same day", S.queue("b", 1, -50, "OTHER", "kb"), true)
    T.eq("Q4c both kept, never merged", pendingCount(1), 2)
    T.eq("Q5a farmRef is the Farm object at queue time", S.pending[1] and S.pending[1][1] and S.pending[1][1].farmRef, w.byId[1])
    T.eq("Q5b queuedDay is the monotonic day", S.pending[1] and S.pending[1][1] and S.pending[1][1].queuedDay, 10)

    w = fresh({ farms = { {1}, {2}, {3} } })
    local n = S.queueForFarms("ev", "OTHER", "label", function(farm)
        if farm.farmId == 2 then return nil end
        if farm.farmId == 3 then error("boom") end
        return 500
    end)
    T.eq("Q6a ineligible and throwing farms skipped", n, 1)
    T.eq("Q6b only farm 1 queued", pendingCount(1) + pendingCount(2) + pendingCount(3), 1)
end

-- =====================================================================
-- E: eligibility helpers
-- =====================================================================
do
    local w = fresh({ farms = { {1}, {2} } })
    EC6.addHusbandry(w, 7, 3)
    T.eq("E1 any owner's animals count for the map", S.mapHasAnimals(), true)
    w = fresh({ farms = { {1} } })
    EC6.addHusbandry(w, 1, 0)
    T.eq("E2 empty husbandries: no animals", S.mapHasAnimals(), false)
    EC6.addHusbandry(w, 1, 5, true)
    T.eq("E3 a throwing husbandry counts as zero", S.mapHasAnimals(), false)
    EC6.addHusbandry(w, 2, 4)
    T.eq("E4a owner farm has animals", S.farmHasAnimals(2), true)
    T.eq("E4b other farm does not", S.farmHasAnimals(1), false)

    EC6.addVehicle(w, 1, false, 0.5)
    T.eq("E5a a trailer is not motorized", S.farmHasMotorized(1), false)
    EC6.addVehicle(w, 1, true, 0.1)
    T.eq("E5b motorized vehicle found", S.farmHasMotorized(1), true)
    T.eq("E6a damage 0.5 counts, 0.1 does not", #S.farmDamagedVehicles(1), 1)
    EC6.addVehicle(w, 1, true, 0.11)
    T.eq("E6b damage 0.11 counts", #S.farmDamagedVehicles(1), 2)
    T.eq("E6c another farm's vehicles never count", #S.farmDamagedVehicles(2), 0)

    local farm = EC6.newFarm(4, 1234)
    T.eq("E7a loan line floors loan x rate x intensity", S.loanLine(farm, 0.02, 3), 74)
    T.eq("E7b below 1 gives no line", S.loanLine(EC6.newFarm(5, 10), 0.02, 1), nil)
    T.eq("E7c no loan gives no line", S.loanLine(EC6.newFarm(6, 0), 0.05, 5), nil)
    T.eq("E8 loan read through getLoan", S.loanOf(farm), 1234)
    T.eq("E9a anyFarm true when one passes", S.anyFarm(function(f) return f.farmId == 1 end), true)
    T.eq("E9b anyFarm false when none passes", S.anyFarm(function() return false end), false)
end

-- =====================================================================
-- S: settle
-- =====================================================================
do
    local w = fresh({ farms = { {1}, {2}, {3} }, day = 10 })
    taxMod(true)
    S.queue("ev3", 3, 300, "OTHER", "label3")
    S.queue("ev1", 1, -100, "LOAN_INTEREST", "label1")
    S.queue("ev2", 2, 200, "VEHICLE_REPAIR", "label2")
    T.eq("S1a lines queued today do not settle", S.settle(), 0)
    T.eq("S1b nothing paid today", #w.money, 0)
    T.eq("S1c lines still pending", pendingCount(1) + pendingCount(2) + pendingCount(3), 3)

    local pendingAtWrite = nil
    w.onAddMoney = function(_, farmId) pendingAtWrite = pendingAtWrite or pendingCount(farmId) end
    EC6.setDay(w, 11)
    T.eq("S2a three lines settle the next day", S.settle(), 3)
    T.eq("S2b three money writes", #w.money, 3)
    T.eq("S2c amount", w.money[1] and w.money[1].amount, -100)
    T.eq("S2d money type from the line", w.money[1] and w.money[1].moneyType, MoneyType.LOAN_INTEREST)
    T.eq("S2e addChange true", w.money[1] and w.money[1].addChange, true)
    T.eq("S2f showChange true", w.money[1] and w.money[1].showChange, true)
    T.eq("S3 the line was removed before addMoney ran", pendingAtWrite, 0)
    T.eq("S4 the second door the same day pays nothing", S.settle(), 0)
    T.eq("S5 farms paid ascending although queued 3,1,2", #w.money == 3 and (w.money[1].farmId .. "," .. w.money[2].farmId .. "," .. w.money[3].farmId) or ("count " .. #w.money), "1,2,3")
    T.eq("S11a one farm-scoped notice per paid line", #w.farmBroadcasts, 3)
    T.eq("S11b notice sent to the paid farm", w.farmBroadcasts[1] and w.farmBroadcasts[1].farmId, 1)
    T.eq("S11c notice carries the label key", w.farmBroadcasts[1] and w.farmBroadcasts[1].event.labelKey, "label1")
    T.eq("S11d notice carries the amount", w.farmBroadcasts[1] and w.farmBroadcasts[1].event.amount, -100)
    T.eq("S11e not sent to the local connection", w.farmBroadcasts[1] and w.farmBroadcasts[1].sendLocal, false)
    T.eq("S12a dedicated server (no local farm) shows nothing locally", #notices, 0)
    T.eq("S13a mirror per paid line", #mirror, 3)
    T.eq("S13b mirror gets the translated label, never the key", mirror[1] and mirror[1].label, "T(label1)")
    T.eq("S13c mirror amount", mirror[1] and mirror[1].amount, -100)
end

do
    local w = fresh({ farms = { {1}, {2} }, day = 10, localFarmId = 2 })
    S.queue("a", 1, 10, "OTHER", "la")
    S.queue("b", 2, 20, "OTHER", "lb")
    EC6.setDay(w, 11)
    S.settle()
    T.eq("S12b a listen host sees only its own farm's notice", #notices, 1)
    T.eq("S12c the notice shown is the host farm's", notices[1] and notices[1].positive, true)
end

do
    local w = fresh({ farms = { {1}, {2} }, day = 10 })
    taxMod(true)
    S.queue("gone", 1, 10, "OTHER", "l")
    S.queue("gone2", 1, 11, "OTHER", "l")
    EC6.removeFarm(w, 1)
    EC6.setDay(w, 11)
    S.settle()
    T.eq("S6a deleted farm: no money", #w.money, 0)
    T.eq("S6b deleted farm: every line dropped", S.pending[1], nil)
    T.ok("S6c deleted farm: logged", EC6.logged("farm 1 no longer exists"))

    w = fresh({ farms = { {1} }, day = 10 })
    taxMod(true)
    S.queue("old", 1, 50, "OTHER", "l")
    EC6.replaceFarm(w, 1)
    EC6.setDay(w, 11)
    S.settle()
    T.ok("S7a [reached: the identity check ran for the reused id]", EC6.logged("now belongs to another farm"))
    T.eq("S7b reused id: no money", #w.money, 0)
    T.eq("S7c reused id: no notice", #w.farmBroadcasts, 0)
    T.eq("S7d reused id: no mirror", #mirror, 0)
    T.eq("S7e reused id: line gone", pendingCount(1), 0)

    w = fresh({ farms = { {1} }, day = 10 })
    S.pending[1] = { { eventName = "bad", amount = 0.5, moneyTypeName = "OTHER", labelKey = "l", queuedDay = 9, farmRef = w.byId[1] } }
    S.settle()
    T.eq("S8a invalid amount: no money", #w.money, 0)
    T.ok("S8b invalid amount: logged", EC6.logged("invalid amount"))
    T.eq("S8c invalid amount: dropped", pendingCount(1), 0)

    w = fresh({ farms = { {1} }, day = 10 })
    taxMod(true)
    S.queue("t", 1, 70, "OTHER", "l")
    w.throwOnAddMoney = true
    EC6.setDay(w, 11)
    T.eq("S9a a throwing addMoney does not throw out of settle", S.settle(), 0)
    T.eq("S9b line lost, not retried", pendingCount(1), 0)
    T.eq("S9c no notice", #w.farmBroadcasts, 0)
    T.eq("S9d no mirror", #mirror, 0)
    T.ok("S9e the lost line is logged", EC6.logged("the line is lost"))

    w = fresh({ farms = { {1} }, day = 10 })
    taxMod(true)
    S.queue("swap", 1, 80, "OTHER", "l")
    w.onAddMoney = function() EC6.replaceFarm(w, 1) end
    EC6.setDay(w, 11)
    S.settle()
    T.eq("S10a [reached: addMoney was called]", #w.money, 1)
    T.eq("S10b farm changed during the write: no notice", #w.farmBroadcasts, 0)
    T.eq("S10c farm changed during the write: no mirror", #mirror, 0)

    w = fresh({ farms = { {1} }, day = 10 })
    taxMod(false)
    S.queue("m", 1, 90, "OTHER", "l")
    EC6.setDay(w, 11)
    S.settle()
    T.eq("S14a mirror refusal does not undo the money", #w.money, 1)
    T.ok("S14b mirror refusal logged", EC6.logged("not recorded"))

    w = fresh({ farms = { {1} }, day = 10 })
    S.queue("sleep", 1, 5, "OTHER", "l")
    EC6.setDay(w, 13)
    S.settle()
    EC6.setDay(w, 14)
    S.settle()
    T.eq("S15 a sleep across days pays the line once", #w.money, 1)

    w = fresh({ farms = { {1} }, day = 10 })
    S.queue("c", 1, 5, "OTHER", "l")
    g_server = nil
    EC6.setDay(w, 11)
    T.eq("S16a a client settles nothing", S.settle(), 0)
    T.eq("S16b a client writes no money", #w.money, 0)

    w = fresh({ farms = { {1} }, day = 10 })
    S.queue("x", 1, 5, "OTHER", "l")
    g_farmManager.getFarmById = function() error("manager threw") end
    EC6.setDay(w, 11)
    T.eq("S17 a throwing farm manager never throws out of settle", type(S.settle()), "number")
end

-- =====================================================================
-- D: farm deletion
-- =====================================================================
do
    local w = fresh({ farms = { {1}, {2} }, day = 10 })
    S.queue("a", 1, 10, "OTHER", "l")
    S.queue("b", 1, 11, "OTHER", "l")
    EC6.removeFarm(w, 1)
    S.onFarmDeleted(1)
    T.eq("D1 farm gone: every line dropped", S.pending[1], nil)

    w = fresh({ farms = { {1} }, day = 10 })
    S.queue("old", 1, 10, "OTHER", "l")
    local newFarm = EC6.replaceFarm(w, 1)
    S.queue("new", 1, 20, "OTHER", "l")
    S.onFarmDeleted(1)
    T.eq("D2a reused id: only the new farm's line kept", pendingCount(1), 1)
    T.eq("D2b the kept line is the new farm's", S.pending[1] and S.pending[1][1] and S.pending[1][1].farmRef, newFarm)

    S.onFarmDeleted(1)
    T.eq("D3 a late message never removes the new farm's lines", pendingCount(1), 1)

    w = fresh({ farms = { {1} }, day = 10 })
    S.install()
    S.queue("z", 1, 10, "OTHER", "l")
    EC6.removeFarm(w, 1)
    g_messageCenter:publish(MessageType.FARM_DELETED, 1)
    T.eq("D4 FARM_DELETED reaches the settlement through the message center", S.pending[1], nil)
end

-- =====================================================================
-- I: doors
-- =====================================================================
do
    local w = fresh({ farms = { {1} }, day = 10 })
    local tg = EC6.timeGuard()
    g_timeGuard = tg
    S.install()
    S.install()
    T.eq("I1a one DAY_CHANGED subscription", EC6.subCount(MessageType.DAY_CHANGED), 1)
    T.eq("I1b one FARM_DELETED subscription", EC6.subCount(MessageType.FARM_DELETED), 1)
    local acc = tg.accruals[S.ACCRUAL_ID]
    T.ok("I4a Time Guard accrual registered", acc ~= nil)
    T.eq("I4b cadence day", acc and acc.cadence, "day")
    T.eq("I4c flowClass event", acc and acc.flowClass, "event")
    T.eq("I4d firstPeriodPolicy full", acc and acc.firstPeriodPolicy, "full")
    T.eq("I4e priority 150", acc and acc.priority, 150)
    T.eq("I4f id", S.ACCRUAL_ID, "RandomWorldEvents_settlement")

    S.queue("d", 1, 10, "OTHER", "l")
    EC6.setDay(w, 11)
    g_messageCenter:publish(MessageType.DAY_CHANGED)
    T.eq("I3 the native door settles", #w.money, 1)

    S.queue("tg", 1, 12, "OTHER", "l")
    EC6.setDay(w, 12)
    acc.onSettle({ boundariesCrossed = 5 })
    g_messageCenter:publish(MessageType.DAY_CHANGED)
    T.eq("I5 both doors on one day pay the line once", #w.money, 2)

    S.uninstall()
    T.eq("I6a DAY_CHANGED unsubscribed", EC6.subCount(MessageType.DAY_CHANGED), 0)
    T.eq("I6b FARM_DELETED unsubscribed", EC6.subCount(MessageType.FARM_DELETED), 0)
    T.eq("I6c accrual unregistered", tg.unregistered[1], S.ACCRUAL_ID)

    w = fresh({ farms = { {1} }, day = 10, server = false })
    S.install()
    T.eq("I7 a client installs no door", EC6.subCount(MessageType.DAY_CHANGED), 0)
end

-- =====================================================================
-- P: persistence
-- =====================================================================
do
    local w = fresh({ farms = { {2}, {1} }, day = 10 })
    S.queue("b", 2, 20, "OTHER", "lb")
    S.queue("a", 1, 10, "LOAN_INTEREST", "la")
    S.queue("stale", 1, 11, "OTHER", "ls")
    S.pending[1][2].farmRef = EC6.newFarm(1)
    local saved = S.serialize()
    T.eq("P1a farms saved ascending although queued 2,1", #saved == 2 and (saved[1].farmId .. "," .. saved[2].farmId) or ("count " .. #saved), "1,2")
    T.eq("P1b stale line not saved", saved[1] and #saved[1].lines, 1)
    T.ok("P1c stale line logged", EC6.logged("not saved"))
    T.eq("P1d line fields", saved[1] and saved[1].lines[1] and saved[1].lines[1].event .. "|" .. saved[1].lines[1].amount .. "|" .. saved[1].lines[1].type .. "|" .. saved[1].lines[1].label .. "|" .. saved[1].lines[1].day, "a|10|LOAN_INTEREST|la|10")

    local bad = S.validateSaved({
        { farmId = 1, lines = {
            { event = "ok", amount = 5, type = "OTHER", label = "l", day = 3 },
            { event = "zero", amount = 0, type = "OTHER", label = "l", day = 3 },
            { event = "frac", amount = 1.5, type = "OTHER", label = "l", day = 3 },
            { event = "type", amount = 5, type = "WAGES", label = "l", day = 3 },
            { event = "label", amount = 5, type = "OTHER", day = 3 },
            { event = "day", amount = 5, type = "OTHER", label = "l" },
        } },
        { farmId = "x", lines = { { event = "e", amount = 5, type = "OTHER", label = "l", day = 1 } } },
    })
    T.eq("P3a malformed farms dropped", #bad, 1)
    T.eq("P3b malformed lines dropped", bad[1] and #bad[1].lines, 1)

    w = fresh({ farms = { {1}, {2} }, day = 10 })
    S.restore({ { farmId = 1, lines = { { event = "r", amount = 40, type = "OTHER", label = "lr", day = 10 } } },
                { farmId = 9, lines = { { event = "orphan", amount = 41, type = "OTHER", label = "lo", day = 9 } } } })
    T.eq("P2a restored lines wait unbound", S.pending[1], nil)
    local again = S.serialize()
    T.eq("P2b unbound lines are saved back unchanged", #again, 2)
    S.settle()
    T.eq("P4a bound at the first settle, queued today: stays", pendingCount(1), 1)
    T.eq("P4b bound to the current Farm object", S.pending[1] and S.pending[1][1] and S.pending[1][1].farmRef, w.byId[1])
    T.ok("P5 a line whose farm is gone is dropped at bind", EC6.logged("no such farm after load"))
    EC6.setDay(w, 11)
    S.settle()
    T.eq("P4c restored line pays at the next real day change", #w.money, 1)

    w = fresh({ farms = { {1} }, day = 10, server = false })
    S.restore({ { farmId = 1, lines = { { event = "r", amount = 40, type = "OTHER", label = "lr", day = 9 } } } })
    S.bindRestored()
    T.eq("P6 a client binds nothing", S.pending[1], nil)

    w = fresh({ farms = { {1} }, day = 10 })
    local list = { { farmId = 3, lines = { { event = "e1", amount = -7, type = "VEHICLE_REPAIR", label = "l1", day = 4 }, { event = "e2", amount = 8, type = "OTHER", label = "l2", day = 5 } } } }
    local x = XMLFile.create("t", "p7", "root")
    S.saveListToXML(x, "root.eventState", list)
    local back = S.loadFromXML(x, "root.eventState")
    T.eq("P7a XML round trip farm", back[1] and back[1].farmId, 3)
    T.eq("P7b XML round trip second line", back[1] and back[1].lines[2].event .. "|" .. back[1].lines[2].amount .. "|" .. back[1].lines[2].type .. "|" .. back[1].lines[2].label .. "|" .. back[1].lines[2].day, "e2|8|OTHER|l2|5")
end

-- =====================================================================
-- N: private notice event
-- =====================================================================
do
    fresh({ farms = { {1} } })
    local getText = g_i18n.getText
    g_i18n.getText = function(_, key)
        if key == "rwe_settlement_notice" then return "%s: %s posted." end
        return "T(" .. key .. ")"
    end
    T.eq("N1 translated label and formatted amount", RWESettlementNoticeEvent.text("rwe_event_feed_shortage_title", -4000), "T(rwe_event_feed_shortage_title): M(-4000) posted.")
    g_i18n.getText = getText
    RWESettlementNoticeEvent.show("l", 10)
    RWESettlementNoticeEvent.show("l", -10)
    T.eq("N2a a credit shows as positive", notices[1].positive, true)
    T.eq("N2b a charge shows as a warning", notices[2].positive, "warn")
    T.eq("N2c economic category", notices[1].category, "economic")
    notices = {}
    local e = RWESettlementNoticeEvent.new("l", 5)
    e:run(nil)
    T.eq("N3 a server never shows a received notice", #notices, 0)
    g_server = nil
    e:run({ getIsServer = function() return false end })
    T.eq("N4 a notice from a non-server connection is ignored", #notices, 0)
    e:run({ getIsServer = function() return true end })
    T.eq("N5 a client shows the server's notice", #notices, 1)
end
