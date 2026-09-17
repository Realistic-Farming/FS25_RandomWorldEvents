--!load: tools/test/lua/f201_model_binding.lua, tools/test/lua/ec6_harness.lua, utils/RWEContextInput.lua, RandomWorldEvents.lua, integrations/RWEStateLedgerBridge.lua, integrations/RWEMarketBridge.lua, utils/RWESettlement.lua, events/RWEEventStateEvent.lua, events/RWESettlementNoticeEvent.lua, utils/economicEvents.lua, utils/vehicleEvents.lua, utils/fieldEvents.lua, utils/animalEvents.lua, utils/specialEvents.lua, api/RWEBaseAPI.lua, api/EconomicAPI.lua
-- EC-6 RandomWorldEvents core, through the REAL RandomWorldEvents.lua and all five
-- event modules, booted by its own Mission00 hooks (brief v1.7 sections 3.3.3,
-- 3.4.3, 3.5, 3.7, 3.8, 3.9.7, 3.10).
-- Groups: G registration (stored tables), D doors at load, F forced and random
-- trigger gates, A activation, M money lines, E shared end path, C client gate,
-- S live price-status rule, R restore, L StateLedger schema, V save snapshot, J join state,
-- P RWEEconomicAPI:setPriceModifier.

local noop = function() end
F201Model.installEngine({ "RWE_TOGGLE_HUD", "RWE_TOGGLE_SETTINGS", "RWE_HUD_DRAG" })
local flashes = {}
RWEEventHUD = { new = function() return { visible = true, editMode = false, saveLayout = noop, delete = noop,
    toggleVisibility = noop, enterEditMode = noop, exitEditMode = noop, update = noop, draw = noop,
    pushFlash = function(_, text, cat, pos) flashes[#flashes + 1] = { text = text, cat = cat, pos = pos } end } end }
RWESettingsPanel = { new = function() return { delete = noop, toggle = noop, isOpen = false, update = noop, draw = noop } end }

FIELDS = { {} }
g_fieldManager = { getFields = function() return FIELDS end }

local w = EC6.world({ farms = { {1, 50000}, {2, 0} }, day = 10 })
local md = EC6.market({ version = 1, calls = w.calls })
g_MarketDynamics = md

local function clear(t) for k in pairs(t) do t[k] = nil end end

Mission00.load(w.mission)
local mgr = g_RandomWorldEvents
local ES = mgr.EVENT_STATE

-- =====================================================================
-- D: doors at load, with world events switched OFF
-- =====================================================================
mgr.events.enabled = false
Mission00.loadMission00Finished(w.mission)
T.eq("D1 DAY_CHANGED is subscribed with world events off", EC6.subCount(MessageType.DAY_CHANGED), 1)
T.eq("D2 FARM_DELETED is subscribed", EC6.subCount(MessageType.FARM_DELETED), 1)
T.eq("D3 the price modifier is registered at load", md.modifiers["RandomWorldEvents"], RWEMarketBridge.modifier)
T.eq("D4 the status watch is seeded at load", RWEMarketBridge.lastPriceStatus, "available")

local function reset()
    ES.activeEvent, ES.activeIntensity, ES.activeCategory = nil, nil, nil
    ES.eventData, ES.customPriceModifiers = {}, nil
    ES.midpointFired, ES.ambientMsgIndex, ES.nextAmbientTime = false, 1, 0
    for k in pairs(ES) do
        if k ~= "activeEvent" and k ~= "eventData" and k ~= "history" and type(ES[k]) ~= "table" and k:match("Bonus$") or (type(k) == "string" and k:match("Malus$")) then ES[k] = nil end
    end
    ES.economicCrisis, ES.durabilityBoost, ES.durabilityMalus = nil, nil, nil
    RWESettlement.reset()
    clear(w.money); clear(w.broadcasts); clear(w.calls); clear(flashes); clear(w.farmBroadcasts)
    w.husbandries[1], w.husbandries[2] = nil, nil
    clear(w.vehicles)
    md.settings.pricesEnabled = true
    g_MarketDynamics = md
    RWEMarketBridge.bind()
    RWEMarketBridge.lastPriceStatus = "available"
    mgr.events.arcadePhysics = false
    mgr.events.enabled = false
    g_localPlayer = nil
    g_server = { broadcastEvent = function(_, event) w.calls[#w.calls + 1] = "broadcastEvent"; w.broadcasts[#w.broadcasts + 1] = event end }
    w.mission.time = 1000
    EC6.setDay(w, 10)
    FIELDS = { {} }
    EC6.log = {}
end

local function lastBroadcast() return w.broadcasts[#w.broadcasts] end

-- =====================================================================
-- G: registration, read from the STORED tables
-- =====================================================================
do
    local byCat, total = {}, 0
    for _, e in pairs(mgr.EVENTS) do
        byCat[e.category] = (byCat[e.category] or 0) + 1
        total = total + 1
    end
    T.eq("G1a 36 events registered", total, 36)
    T.eq("G1b economic 10", byCat.economic, 10)
    T.eq("G1c field 10", byCat.field, 10)
    T.eq("G1d wildlife 8", byCat.wildlife, 8)
    T.eq("G1e vehicle 4", byCat.vehicle, 4)
    T.eq("G1f special 4", byCat.special, 4)

    local arcade = {}
    for name, e in pairs(mgr.EVENTS) do if e.gate == "arcadePhysics" then arcade[#arcade + 1] = name end end
    table.sort(arcade)
    T.eq("G2 the stored gate is on exactly the four arcade events", table.concat(arcade, ","),
        "equipment_durability_boost,equipment_durability_drop,vehicle_engine_trouble,vehicle_speed_boost")

    local withFlags = { "market_boom", "market_crash", "price_fixing", "export_opportunity", "economic_crisis",
        "crop_yield_bonus", "crop_yield_penalty", "fertilizer_bonus", "fertilizer_penalty", "seed_growth_bonus",
        "seed_growth_penalty", "harvest_bonus", "harvest_penalty", "field_sale_bonus", "field_sale_penalty",
        "animal_product_bonus", "animal_product_penalty", "wolf_sighting", "bumper_wool_season", "disease_scare",
        "feed_shortage", "wildlife_pest_invasion", "special_event_festival", "bonus_trade_prices",
        "equipment_durability_boost", "equipment_durability_drop" }
    local missing = {}
    for _, n in ipairs(withFlags) do if type(mgr.EVENTS[n].applyFlags) ~= "function" then missing[#missing + 1] = n end end
    T.eq("G3a every flag-setting event stores applyFlags", table.concat(missing, ","), "")
    local billOnly = { "government_subsidy", "sudden_expense", "farmer_donation", "insurance_bonus", "loan_interest",
        "veterinary_windfall", "vehicle_accident", "vehicle_repair_bill" }
    local extra = {}
    for _, n in ipairs(billOnly) do if mgr.EVENTS[n].applyFlags ~= nil then extra[#extra + 1] = n end end
    T.eq("G3b money-only events store no applyFlags", table.concat(extra, ","), "")

    T.eq("G4a seed_discount retired", mgr.EVENTS.seed_discount, nil)
    T.eq("G4b fertilizer_discount retired", mgr.EVENTS.fertilizer_discount, nil)
    T.eq("G4c equipment_discount retired", mgr.EVENTS.equipment_discount, nil)
    T.eq("G4d tax_refund retired", mgr.EVENTS.tax_refund, nil)

    reset()
    FIELDS = {}
    T.eq("G5a no fields on the map: fertilizer_bonus ineligible", mgr.EVENTS.fertilizer_bonus.canTrigger(), false)
    T.eq("G5b no fields on the map: harvest_bonus ineligible", mgr.EVENTS.harvest_bonus.canTrigger(), false)
    FIELDS = { {} }
    T.eq("G5c fields present: fertilizer_bonus eligible", mgr.EVENTS.fertilizer_bonus.canTrigger(), true)

    local mission = g_currentMission
    g_currentMission = nil
    local anyTrue = false
    for _, e in pairs(mgr.EVENTS) do if e.canTrigger() then anyTrue = true end end
    g_currentMission = mission
    T.eq("G6 no mission: every stored canTrigger is false", anyTrue, false)

    local stored = mgr.EVENTS.market_boom
    T.eq("G7a stored summary key", stored.summaryKey, "rwe_summary_price_rise")
    T.ok("G7b stored crisis chooseSummary", type(mgr.EVENTS.economic_crisis.chooseSummary) == "function")
    T.ok("G7c stored crisis ambient variants", type(mgr.EVENTS.economic_crisis.ambientVariants) == "table")
end

-- =====================================================================
-- F: forced and random trigger gates
-- =====================================================================
do
    reset()
    md.settings.pricesEnabled = false
    local r = mgr:triggerNamedEvent("market_boom", 3)
    T.ok("F1a prices off: a forced price event is refused", string.find(r, "market price events are unavailable", 1, true) ~= nil, r)
    T.eq("F1b nothing activated", ES.activeEvent, nil)

    reset()
    g_MarketDynamics = EC6.market({ version = 0 })
    RWEMarketBridge.bind()
    r = mgr:triggerNamedEvent("government_subsidy", 2)
    T.ok("F2a old market: government_subsidy refused", string.find(r, "update MarketDynamics", 1, true) ~= nil, r)
    T.eq("F2b nothing activated", ES.activeEvent, nil)

    reset()
    r = mgr:triggerNamedEvent("feed_shortage", 2)
    T.ok("F3a no animals: feed_shortage refused", string.find(r, "no eligible farm", 1, true) ~= nil, r)
    T.eq("F3b nothing queued", RWESettlement.pending[1], nil)

    reset()
    mgr.events.arcadePhysics = true
    r = mgr:triggerNamedEvent("vehicle_speed_boost", 2)
    T.ok("F4a dedicated server: an arcade event is refused", string.find(r, "arcade physics", 1, true) ~= nil, r)
    T.eq("F4b nothing activated", ES.activeEvent, nil)

    reset()
    g_server = nil
    r = mgr:triggerNamedEvent("insurance_bonus", 1)
    T.ok("F5 a client never triggers", string.find(r, "server only", 1, true) ~= nil, r)

    reset()
    FIELDS = {}
    RWEMarketBridge.bind()
    g_MarketDynamics = nil
    RWEMarketBridge.bind()
    clear(w.farms); w.byId[1], w.byId[2] = nil, nil
    mgr.events.enabled = true
    mgr.events.wildlifeEvents = false
    T.eq("F6a nothing eligible: the random scheduler triggers nothing", mgr:triggerRandomEvent(), false)
    mgr.events.wildlifeEvents = true
    T.eq("F6b [reached: one eligible event]", mgr:triggerRandomEvent(), true)
    T.eq("F6c the only eligible event is the one triggered", ES.activeEvent, "wildlife_pest_invasion")
    w.farms[1] = EC6.newFarm(1, 50000); w.farms[2] = EC6.newFarm(2, 0)
    w.byId[1], w.byId[2] = w.farms[1], w.farms[2]
end

-- =====================================================================
-- A: activation
-- =====================================================================
do
    reset()
    ES.eventData = { junk = true, summaryKey = "stale" }
    ES.customPriceModifiers = { [3] = { multiplier = 2 } }
    mgr:triggerNamedEvent("market_boom", 3)
    T.eq("A1a activation resets eventData", ES.eventData.junk, nil)
    T.eq("A1b activation clears custom price terms", ES.customPriceModifiers, nil)
    T.eq("A2 the price summary is chosen", ES.eventData.summaryKey, "rwe_summary_price_rise")
    T.eq("A3a one start broadcast", #w.broadcasts, 1)
    local p = lastBroadcast()
    T.eq("A3b start state names the event", p.activeEvent, "market_boom")
    T.eq("A3c start notice kind", p.noticeKind, "start")
    T.eq("A3d start notice key", p.noticeKey, "rwe_event_market_boom_start")
    T.eq("A3e summary travels", p.summaryKey, "rwe_summary_price_rise")
    T.eq("A3f intensity travels", p.activeIntensity, 3)
    T.near("A3g flags applied", ES.marketBonus, 0.25, 1e-9)

    reset()
    mgr.events.arcadePhysics = true
    local veh = {}
    g_localPlayer = { getCurrentVehicle = function() return veh end }
    local r = mgr:triggerNamedEvent("vehicle_speed_boost", 2)
    T.eq("A4a [reached: the arcade event started on a listen host in a vehicle]", ES.activeEvent, "vehicle_speed_boost")
    T.eq("A4b an arcade start is never broadcast", #w.broadcasts, 0)
    T.ok("A4c the host sees its own start notice", #flashes == 1 and flashes[1].text == "T(rwe_event_vehicle_speed_boost_start)")
    T.near("A4d the speed factor is stored once in eventData", ES.eventData.speedScale, 1.49, 1e-9)
    T.eq("A4e no summary for an arcade event", ES.eventData.summaryKey, nil)
    T.eq("A4f shared state shows no event", mgr:sharedState().activeEvent, "")

    reset()
    mgr:triggerNamedEvent("economic_crisis", 4)
    T.eq("A5a crisis with prices and a loan: price part", ES.eventData.crisisHasPrice, true)
    T.eq("A5b crisis with prices and a loan: loan part", ES.eventData.crisisHasLoan, true)
    T.eq("A5c crisis summary both", ES.eventData.summaryKey, "rwe_summary_crisis_both")
    T.eq("A5d crisis start notice both", lastBroadcast().noticeKey, "rwe_event_economic_crisis_start_both")
    T.eq("A5e crisis parts travel", tostring(lastBroadcast().crisisHasPrice) .. tostring(lastBroadcast().crisisHasLoan), "truetrue")

    reset()
    md.settings.pricesEnabled = false
    RWEMarketBridge.lastPriceStatus = "market_prices_off"
    mgr:triggerNamedEvent("economic_crisis", 4)
    T.eq("A6a prices off: loan-only crisis", tostring(ES.eventData.crisisHasPrice) .. tostring(ES.eventData.crisisHasLoan), "falsetrue")
    T.eq("A6b loan-only notice", lastBroadcast().noticeKey, "rwe_event_economic_crisis_start_loan")
    T.eq("A6c loan-only summary", ES.eventData.summaryKey, "rwe_summary_crisis_loan")

    reset()
    w.byId[1].loan = 0
    mgr:triggerNamedEvent("economic_crisis", 4)
    T.eq("A7a no loans: price-only crisis", tostring(ES.eventData.crisisHasPrice) .. tostring(ES.eventData.crisisHasLoan), "truefalse")
    T.eq("A7b price-only notice", lastBroadcast().noticeKey, "rwe_event_economic_crisis_start_price")
    T.eq("A7c no loan line queued", RWESettlement.pending[1], nil)
    w.byId[1].loan = 50000

    reset()
    w.byId[1].loan = 0
    md.settings.pricesEnabled = false
    RWEMarketBridge.lastPriceStatus = "market_prices_off"
    local refused = mgr:triggerNamedEvent("economic_crisis", 4)
    T.ok("A8 no loans and prices off: the crisis does not roll", string.find(refused, "Not triggered", 1, true) ~= nil, refused)
    w.byId[1].loan = 50000
end

-- =====================================================================
-- M: money lines at event start
-- =====================================================================
do
    local function line(farmId) local l = RWESettlement.pending[farmId]; return l and l[1] end

    reset()
    mgr:triggerNamedEvent("government_subsidy", 2)
    T.eq("M1a subsidy: farm 1 line", line(1) and line(1).amount, 10000)
    T.eq("M1b subsidy: farm 2 line", line(2) and line(2).amount, 10000)
    T.eq("M1c subsidy label is the title key", line(1) and line(1).labelKey, "rwe_event_government_subsidy_title")
    T.eq("M1d shared notice names no amount", lastBroadcast().noticeKey, "rwe_event_government_subsidy_start")
    T.eq("M1e nothing paid at announcement", #w.money, 0)

    reset()
    mgr:triggerNamedEvent("loan_interest", 3)
    T.eq("M2a loan interest: floor(loan x 0.02 x i)", line(1) and line(1).amount, -3000)
    T.eq("M2b a farm without a loan gets no line", line(2), nil)
    T.eq("M2c loan money type", line(1) and line(1).moneyTypeName, "LOAN_INTEREST")

    reset()
    EC6.addHusbandry(w, 2, 6)
    mgr:triggerNamedEvent("feed_shortage", 2)
    T.eq("M3a feed shortage: farm with animals charged", line(2) and line(2).amount, -4000)
    T.eq("M3b feed shortage: farm without animals not charged", line(1), nil)
    T.near("M3c feed shortage keeps its read signal", ES.animalProductMalus, 0.2, 1e-9)

    reset()
    EC6.addHusbandry(w, 1, 2)
    mgr:triggerNamedEvent("veterinary_windfall", 3)
    T.eq("M4 veterinary windfall: 1500 + 1000 i", line(1) and line(1).amount, 4500)

    reset()
    EC6.addVehicle(w, 2, true, 0)
    EC6.addVehicle(w, 1, false, 0)
    mgr:triggerNamedEvent("vehicle_accident", 3)
    local a = line(2) and line(2).amount or 0
    T.ok("M5a accident bill in range and a multiple of i", a <= -1500 and a >= -4500 and a % 3 == 0, tostring(a))
    T.eq("M5b a farm without a motorized vehicle gets no bill", line(1), nil)
    T.eq("M5c repair money type", line(2) and line(2).moneyTypeName, "VEHICLE_REPAIR")

    reset()
    local v1 = EC6.addVehicle(w, 1, true, 0.5)
    EC6.addVehicle(w, 1, false, 0.3)
    EC6.addVehicle(w, 1, true, 0.05)
    mgr:triggerNamedEvent("vehicle_repair_bill", 1)
    local rb = line(1) and line(1).amount or 0
    T.ok("M6a inspection bill sums two damaged vehicles", rb <= -1000 and rb >= -4000, tostring(rb))
    T.eq("M6b no vehicle is repaired", v1.damage, 0.5)
end

-- =====================================================================
-- E: shared end path
-- =====================================================================
do
    reset()
    mgr:triggerNamedEvent("market_boom", 2)
    ES.customPriceModifiers = { [2] = { multiplier = 1.3 } }
    ES.midpointFired = true   -- this frame crosses only the end, not the midpoint too
    w.mission.time = ES.eventStartTime + ES.eventDuration + 1
    clear(w.broadcasts)
    mgr:update(16)
    T.eq("E1a timer end clears the event", ES.activeEvent, nil)
    T.eq("E1b intensity cleared", ES.activeIntensity, nil)
    T.eq("E1c category cleared", ES.activeCategory, nil)
    T.eq("E1d eventData cleared", next(ES.eventData), nil)
    T.eq("E1e custom price terms cleared", ES.customPriceModifiers, nil)
    T.eq("E1f onEnd cleared the flags", ES.marketBonus, nil)
    T.eq("E1g one end broadcast", #w.broadcasts, 1)
    T.eq("E1h the end state is empty", lastBroadcast().activeEvent, "")

    reset()
    mgr:triggerNamedEvent("economic_crisis", 4)
    mgr:consoleCommandEnd()
    T.eq("E2a console end uses the shared path", ES.activeEvent, nil)
    T.eq("E2b the crisis end notice is sent", lastBroadcast().noticeKey, "rwe_event_economic_crisis_end")
    T.eq("E2c end notice kind", lastBroadcast().noticeKind, "end")
    T.eq("E2d crisis flag cleared", ES.economicCrisis, nil)

    reset()
    mgr.events.arcadePhysics = true
    g_localPlayer = { getCurrentVehicle = function() return {} end }
    mgr:triggerNamedEvent("vehicle_engine_trouble", 3)
    clear(flashes)
    mgr.events.arcadePhysics = false
    mgr:update(16)
    T.eq("E3a switching Arcade Physics off ends the arcade event", ES.activeEvent, nil)
    T.eq("E3b an arcade end is never broadcast", #w.broadcasts, 0)
    T.ok("E3c the host sees its own end notice", #flashes == 1 and flashes[1].text == "T(rwe_event_vehicle_engine_trouble_end)")
end

-- =====================================================================
-- C: client gate
-- =====================================================================
do
    local watchCalls = 0
    local realWatch = RWEMarketBridge.watch
    RWEMarketBridge.watch = function(m) watchCalls = watchCalls + 1; return realWatch(m) end
    local ticks = 0
    mgr:registerTickHandler("ec6probe", function() ticks = ticks + 1 end)

    for _, enabled in ipairs({ false, true }) do
        reset()
        ES.activeEvent, ES.activeCategory = "market_boom", "economic"
        ES.eventStartTime, ES.eventDuration = 0, 10
        ES.eventData = { summaryKey = "rwe_summary_price_rise" }
        w.mission.time = 5000
        mgr.events.enabled = enabled
        g_server = nil
        watchCalls, ticks = 0, 0
        mgr:update(16)
        local tag = enabled and "events on" or "events off"
        T.eq("C1a [reached: the client gate returned before the watch] " .. tag, watchCalls, 0)
        T.eq("C1b a client never ends a synced event " .. tag, ES.activeEvent, "market_boom")
        T.eq("C1c a client runs no tick handler " .. tag, ticks, 0)
        T.eq("C1d a client shows no notice of its own " .. tag, #flashes, 0)
    end

    reset()
    watchCalls = 0
    mgr:update(16)
    T.eq("C2 control: the server runs the watch", watchCalls, 1)
    mgr.tickHandlers.ec6probe = nil
    RWEMarketBridge.watch = realWatch
end

-- =====================================================================
-- S: live price-status rule
-- =====================================================================
do
    reset()
    mgr:triggerNamedEvent("market_boom", 2)
    ES.customPriceModifiers = { [1] = { multiplier = 1.2 } }
    clear(w.calls); clear(w.broadcasts)
    local stateAtSend = nil
    local send = g_server.broadcastEvent
    g_server.broadcastEvent = function(s, ev) stateAtSend = stateAtSend or ES.activeEvent or "cleared"; send(s, ev) end
    md.settings.pricesEnabled = false
    mgr:update(16)
    T.eq("S1a prices off ends a price event", ES.activeEvent, nil)
    T.eq("S1b the rule ran before the send", stateAtSend, "cleared")
    T.eq("S1c send then refresh, in that order", table.concat(w.calls, ","), "broadcastEvent,refresh")
    T.eq("S1d custom terms cleared before the refresh", ES.customPriceModifiers, nil)
    T.eq("S1e one end state sent", #w.broadcasts, 1)

    reset()
    mgr:triggerNamedEvent("economic_crisis", 4)
    ES.ambientMsgIndex = 3
    clear(w.calls); clear(w.broadcasts)
    md.settings.pricesEnabled = false
    mgr:update(16)
    T.eq("S2a prices off narrows a crisis with a loan part", ES.activeEvent, "economic_crisis")
    T.eq("S2b the price part is dropped", ES.eventData.crisisHasPrice, false)
    T.eq("S2c the summary follows the loan-only row", ES.eventData.summaryKey, "rwe_summary_crisis_loan")
    T.eq("S2d ambient index reset", ES.ambientMsgIndex, 1)
    T.eq("S2e the narrowed state is sent", lastBroadcast() and tostring(lastBroadcast().crisisHasPrice), "false")
    T.eq("S2f the modifier gives no crisis term", RWEMarketBridge.modifier({ fillTypeIndex = 1 }), nil)
    T.eq("S2g refresh after the send", table.concat(w.calls, ","), "broadcastEvent,refresh")
    clear(flashes)
    ES.nextAmbientTime, ES.midpointFired = 0, true
    mgr:_tickImmersion()
    T.eq("S2h the ambient line follows the loan-only part", flashes[1] and flashes[1].text, "T(rwe_event_economic_crisis_ambient_loan1)")
    md.settings.pricesEnabled = true
    mgr:update(16)
    T.eq("S3 a dropped price part is never revived", ES.eventData.crisisHasPrice, false)

    reset()
    w.byId[1].loan = 0
    mgr:triggerNamedEvent("economic_crisis", 4)
    md.settings.pricesEnabled = false
    mgr:update(16)
    T.eq("S4 a price-only crisis ends when prices go off", ES.activeEvent, nil)
    w.byId[1].loan = 50000

    reset()
    md.settings.pricesEnabled = false
    RWEMarketBridge.lastPriceStatus = "market_prices_off"
    md.settings.pricesEnabled = true
    clear(w.calls)
    mgr:update(16)
    T.eq("S5 no active event: the change still sends and refreshes", table.concat(w.calls, ","), "broadcastEvent,refresh")

    reset()
    EC6.addHusbandry(w, 1, 3)
    mgr:triggerNamedEvent("feed_shortage", 2)
    md.settings.pricesEnabled = false
    mgr:update(16)
    T.eq("S6 a money event is unchanged by a status change", ES.activeEvent, "feed_shortage")

    reset()
    mgr:triggerNamedEvent("government_subsidy", 1)
    local old = EC6.market({ version = 0, calls = w.calls })
    g_MarketDynamics = old
    RWEMarketBridge.bind()
    clear(w.calls)
    mgr:onPriceStatusChanged("market_update_needed")
    T.eq("S7a an old market ends government_subsidy", ES.activeEvent, nil)
    T.eq("S7b an old market is never asked to refresh", old.refreshes, 0)
    T.eq("S7c the queued line still settles", RWESettlement.pending[1] ~= nil, true)
    g_server.broadcastEvent = send
end

-- =====================================================================
-- R: restore
-- =====================================================================
local function saved(fields)
    mgr._savedActiveEvent = fields.event
    mgr._savedActiveIntensity = fields.intensity or 0
    mgr._savedRemainingMs = fields.remaining or 600000
    mgr._savedCooldownRemainingMs = 0
    mgr._savedMidpointFired = false
    mgr._savedSummaryKey = fields.summary
    mgr._savedSummaryArgs = {}
    mgr._savedCrisisHasPrice = fields.price == true
    mgr._savedCrisisHasLoan = fields.loan == true
    mgr._savedSettlement = fields.settlement or {}
end

do
    reset()
    saved({ event = "vehicle_speed_boost", intensity = 2 })
    mgr:restoreFromSave()
    T.eq("R1 an arcade event never resumes", ES.activeEvent, nil)

    reset()
    saved({ event = "seed_discount", intensity = 2 })
    mgr:restoreFromSave()
    T.eq("R2 a retired event never resumes", ES.activeEvent, nil)

    reset()
    md.settings.pricesEnabled = false
    saved({ event = "harvest_bonus", intensity = 2, summary = "rwe_summary_price_rise" })
    mgr:restoreFromSave()
    T.eq("R3a prices off: a price event does not resume", ES.activeEvent, nil)
    md.settings.pricesEnabled = true
    saved({ event = "harvest_bonus", intensity = 4, summary = "rwe_summary_price_rise" })
    mgr:restoreFromSave()
    T.eq("R3b available: the price event resumes", ES.activeEvent, "harvest_bonus")
    T.eq("R3c restored intensity", ES.activeIntensity, 4)
    T.near("R3d applyFlags re-applied with the restored intensity", ES.harvestBonus, 0.30, 1e-9)
    T.eq("R3e restore state sent without a notice", lastBroadcast() and lastBroadcast().noticeKey, "")
    T.eq("R3f saved summary restored", ES.eventData.summaryKey, "rwe_summary_price_rise")

    reset()
    g_MarketDynamics = EC6.market({ version = 0 })
    RWEMarketBridge.bind()
    saved({ event = "economic_crisis", intensity = 4, loan = true, price = true })
    mgr:restoreFromSave()
    T.eq("R4a old market: a crisis never resumes", ES.activeEvent, nil)
    saved({ event = "government_subsidy", intensity = 2 })
    mgr:restoreFromSave()
    T.eq("R4b old market: government_subsidy never resumes", ES.activeEvent, nil)

    reset()
    md.settings.pricesEnabled = false
    saved({ event = "economic_crisis", intensity = 4, loan = true, price = true, summary = "rwe_summary_crisis_both" })
    mgr:restoreFromSave()
    T.eq("R5a prices off, saved loan part: the crisis resumes", ES.activeEvent, "economic_crisis")
    T.eq("R5b the price part is not kept", ES.eventData.crisisHasPrice, false)
    T.eq("R5c the summary is re-chosen loan-only, never the saved row", ES.eventData.summaryKey, "rwe_summary_crisis_loan")

    reset()
    saved({ event = "economic_crisis", intensity = 5, price = true, loan = false })
    mgr:restoreFromSave()
    T.eq("R6a available, saved price part: resumes", ES.activeEvent, "economic_crisis")
    T.eq("R6b the price part is kept", ES.eventData.crisisHasPrice, true)
    reset()
    saved({ event = "economic_crisis", intensity = 5 })
    mgr:restoreFromSave()
    T.eq("R6c no saved parts: the crisis is refused", ES.activeEvent, nil)

    reset()
    saved({ event = "vehicle_accident", intensity = 2, summary = "rwe_summary_bill_accident",
        settlement = { { farmId = 1, lines = { { event = "vehicle_accident", amount = -900, type = "VEHICLE_REPAIR", label = "rwe_event_vehicle_accident_title", day = 10 } } } } })
    mgr:restoreFromSave()
    T.eq("R7a a bill event resumes its HUD", ES.activeEvent, "vehicle_accident")
    T.eq("R7b restore queues no new line", RWESettlement.pending[1], nil)
    T.eq("R7c the saved line waits to be bound", RWESettlement.unbound ~= nil and #RWESettlement.unbound, 1)
    mgr:update(16)
    T.eq("R7d the first server update binds it, unchanged", RWESettlement.pending[1] and RWESettlement.pending[1][1].amount, -900)
    T.eq("R7e the saved temp fields are cleared", mgr._savedActiveEvent, nil)
end

-- =====================================================================
-- L: StateLedger schema
-- =====================================================================
do
    reset()
    mgr._savedSettlement = { { farmId = 1, lines = { { event = "x", amount = 5, type = "OTHER", label = "l", day = 1 } } } }
    mgr._savedCrisisHasLoan = true
    RWEStateLedgerBridge.pendingState = { schema = 1, activeEvent = "economic_crisis", remainingMs = 60000, cooldownRemainingMs = 0, midpointFired = false }
    RWEStateLedgerBridge.applyState(mgr)
    T.eq("L1a a schema 1 block overrides the own-XML settlement with none", #mgr._savedSettlement, 0)
    T.eq("L1b a schema 1 block carries no crisis parts", mgr._savedCrisisHasLoan, false)
    mgr:restoreFromSave()
    T.eq("L1c a schema 1 crisis is refused", ES.activeEvent, nil)

    reset()
    RWEStateLedgerBridge.pendingState = { schema = 1, activeEvent = "market_boom", remainingMs = 60000, cooldownRemainingMs = 0, midpointFired = false }
    RWEStateLedgerBridge.applyState(mgr)
    mgr:restoreFromSave()
    T.eq("L2a a schema 1 block still restores an ordinary event", ES.activeEvent, "market_boom")
    T.eq("L2b with no saved intensity", ES.activeIntensity, nil)
    T.eq("L2c and its default summary", ES.eventData.summaryKey, "rwe_summary_price_rise")

    reset()
    mgr:triggerNamedEvent("economic_crisis", 4)
    local state = RWEStateLedgerBridge.buildState(mgr)
    T.eq("L3a schema 2 written", state.schema, 2)
    T.eq("L3b intensity written", state.activeIntensity, 4)
    T.eq("L3c crisis parts written", tostring(state.crisisHasPrice) .. tostring(state.crisisHasLoan), "truetrue")
    T.eq("L3d summary written", state.summaryKey, "rwe_summary_crisis_both")
    T.eq("L3e settlement written", state.settlement[1] and state.settlement[1].farmId, 1)
    reset()
    RWEStateLedgerBridge.pendingState = state
    RWEStateLedgerBridge.applyState(mgr)
    md.settings.pricesEnabled = false
    mgr:restoreFromSave()
    T.eq("L4a a schema 2 crisis resumes from its loan part", ES.activeEvent, "economic_crisis")
    T.eq("L4b and its line waits to be bound", RWESettlement.unbound ~= nil and #RWESettlement.unbound, 1)
end

-- =====================================================================
-- V: only a real game save writes event and settlement state
-- =====================================================================
do
    reset()
    local function xmlData()
        for _, d in pairs(EC6.xmlStore) do return d end
        return {}
    end
    mgr._savedStateSnapshot = {}   -- as loaded from a save with no event and no lines
    RWESettlement.queue("v", 1, 777, "OTHER", "l")
    mgr:saveSettings()
    T.eq("V1 a settings write does not persist new lines", xmlData()["RandomWorldEvents.eventState.settlement.farm(0)#id"], nil)
    FSCareerMissionInfo.saveToXMLFile(w.mission.missionInfo)
    T.eq("V2a a real save writes the line", xmlData()["RandomWorldEvents.eventState.settlement.farm(0)#id"], 1)
    T.eq("V2b with its amount", xmlData()["RandomWorldEvents.eventState.settlement.farm(0).line(0)#amount"], 777)
    EC6.setDay(w, 11)
    RWESettlement.settle()
    mgr:saveSettings()
    T.eq("V3 a later settings write re-writes the last real save", xmlData()["RandomWorldEvents.eventState.settlement.farm(0)#id"], 1)
end

-- =====================================================================
-- J: join state
-- =====================================================================
do
    reset()
    mgr:triggerNamedEvent("market_crash", 3)
    local sent = {}
    FSBaseMission.sendInitialClientState(w.mission, { sendEvent = function(_, ev) sent[#sent + 1] = ev end })
    T.eq("J1a a joining connection receives one state", #sent, 1)
    T.eq("J1b with the event", sent[1] and sent[1].activeEvent, "market_crash")
    T.eq("J1c and its summary", sent[1] and sent[1].summaryKey, "rwe_summary_price_fall")
    T.eq("J1d and no notice", sent[1] and sent[1].noticeKey, "")
end

-- =====================================================================
-- P: RWEEconomicAPI:setPriceModifier (brief 3.1.4)
-- =====================================================================
do
    reset()
    g_fillTypeManager = {
        getFillTypeIndexByName = function(_, name) if name == "MAIZE" then return 7 end return nil end,
        getFillTypeByIndex = function(_, index) if index == 7 or index == 8 then return {} end return nil end,
    }
    T.eq("P1a no active event: refused", RWEEconomicAPI:setPriceModifier("MAIZE", 1.1), false)
    T.eq("P1b no table created", ES.customPriceModifiers, nil)
    EC6.addVehicle(w, 1, true, 0)
    mgr:triggerNamedEvent("vehicle_accident", 1)
    g_server = nil
    T.eq("P2 a client is refused", RWEEconomicAPI:setPriceModifier("MAIZE", 1.1), false)
    reset()
    EC6.addVehicle(w, 1, true, 0)
    mgr:triggerNamedEvent("vehicle_accident", 1)
    T.eq("P3a a name is accepted", RWEEconomicAPI:setPriceModifier("MAIZE", 1.1), true)
    T.eq("P3b stored under the fill type index", ES.customPriceModifiers[7] and ES.customPriceModifiers[7].multiplier, 1.1)
    T.eq("P3c never under the raw name", ES.customPriceModifiers.MAIZE, nil)
    T.eq("P4 an unknown name is refused", RWEEconomicAPI:setPriceModifier("NOPE", 1.1), false)
    T.eq("P5a zero refused", RWEEconomicAPI:setPriceModifier(8, 0), false)
    T.eq("P5b NaN refused", RWEEconomicAPI:setPriceModifier(8, 0/0), false)
    T.eq("P6 an unknown index is refused", RWEEconomicAPI:setPriceModifier(99, 1.2), false)
    T.eq("P7 read back by name", RWEEconomicAPI:getPriceModifier("MAIZE"), 1.1)
    T.near("P8 the registered modifier applies it", RWEMarketBridge.modifier({ fillTypeIndex = 7 }), 1.1, 1e-9)
    mgr:consoleCommandEnd()
    T.eq("P9 the shared end path clears it", ES.customPriceModifiers, nil)
    g_fillTypeManager = nil
end
