--!load: tools/test/lua/ec6_harness.lua, integrations/RWEMarketBridge.lua
-- EC-6 RandomWorldEvents: the MarketDynamics price bridge (brief v1.7 sections
-- 3.1.2 to 3.1.5 and the refresh half of 3.7.7).
-- Groups: B bind, P price status, X exclusions, M modifier terms, C custom terms,
-- W status watch, R refresh.

local B = RWEMarketBridge

local function mgr(opts)
    opts = opts or {}
    local m = { EVENT_STATE = { activeEvent = opts.event, activeIntensity = opts.intensity, eventData = opts.eventData or {}, customPriceModifiers = opts.custom },
                events = { intensity = opts.configured or 2 }, statusCalls = {} }
    function m:onPriceStatusChanged(status) self.statusCalls[#self.statusCalls + 1] = status end
    g_RandomWorldEvents = m
    return m
end

local function bindWith(md)
    EC6.world({ farms = { {1} } })
    g_MarketDynamics = md
    B._refreshLogged = false
    return B.bind()
end

-- =====================================================================
-- B: bind
-- =====================================================================
do
    T.eq("B1 no handle: absent", bindWith(nil), "absent")
    T.eq("B1b absent registers nothing and is not live", B.live, false)
    T.eq("B2 handle without registerPriceModifier: absent", bindWith({}), "absent")

    local old = EC6.market({ version = nil })
    T.eq("B3a no capability: old", bindWith(old), "old")
    T.eq("B3b old: nothing registered", old.modifiers[B.MODIFIER_NAME], nil)
    local zero = EC6.market({ version = 0 })
    T.eq("B3c capability 0: old", bindWith(zero), "old")
    T.eq("B3d capability 0: nothing registered", zero.modifiers[B.MODIFIER_NAME], nil)
    T.eq("B3e capability as a string: old", bindWith(EC6.market({ version = "1" })), "old")

    local md = EC6.market({ version = 1 })
    T.eq("B4a capability 1: current", bindWith(md), "current")
    T.eq("B4b current: live", B.live, true)
    T.eq("B4c registered under the modifier name", md.modifiers["RandomWorldEvents"], B.modifier)

    T.eq("B5a registration throws: absent", bindWith(EC6.market({ version = 1, throwOnRegister = true })), "absent")
    T.ok("B5b registration failure logged", EC6.logged("registration failed"))
    T.eq("B5c not live after a throw", B.live, false)

    EC6.world({ farms = { {1} }, server = false })
    g_MarketDynamics = EC6.market({ version = 1 })
    T.eq("B6 a client binds nothing", B.bind(), "absent")

    local live = EC6.market({ version = 1 })
    bindWith(live)
    B.unbind()
    T.eq("B7a unbind unregisters when live", live.unregistered, "RandomWorldEvents")
    local notLive = EC6.market({ version = 0 })
    bindWith(notLive)
    B.unbind()
    T.eq("B7b unbind never unregisters beside an old market", notLive.unregistered, nil)
end

-- =====================================================================
-- P: price status
-- =====================================================================
do
    local md = EC6.market({ version = 1 })
    bindWith(md)
    T.eq("P1 live and prices on: available", B.priceStatus(), "available")
    md.settings.pricesEnabled = false
    T.eq("P2 live and prices off: market_prices_off", B.priceStatus(), "market_prices_off")
    bindWith(EC6.market({ version = 0 }))
    T.eq("P3 old: market_update_needed", B.priceStatus(), "market_update_needed")
    bindWith(nil)
    T.eq("P4 absent: no_market", B.priceStatus(), "no_market")

    g_server = nil
    B.clientPriceStatus = "market_prices_off"
    T.eq("P5 a client displays the synced copy", B.displayStatus(), "market_prices_off")
end

-- =====================================================================
-- X: price events and the old-market exclusion
-- =====================================================================
do
    local names = { "market_boom", "market_crash", "price_fixing", "export_opportunity", "economic_crisis",
        "harvest_bonus", "harvest_penalty", "field_sale_bonus", "field_sale_penalty", "bonus_trade_prices", "special_event_festival" }
    local all = true
    for _, n in ipairs(names) do all = all and B.isPriceEvent(n) end
    T.ok("X1 the eleven price events", all)
    T.eq("X2 a money event is not a price event", B.isPriceEvent("government_subsidy"), false)

    bindWith(EC6.market({ version = 0 }))
    T.eq("X3a old market excludes government_subsidy", B.isOldMarketExcluded("government_subsidy"), true)
    T.eq("X3b old market excludes crop_yield_bonus", B.isOldMarketExcluded("crop_yield_bonus"), true)
    T.eq("X3c old market excludes crop_yield_penalty", B.isOldMarketExcluded("crop_yield_penalty"), true)
    T.eq("X3d old market excludes the crisis", B.isOldMarketExcluded("economic_crisis"), true)
    T.eq("X3e old market does not exclude feed_shortage", B.isOldMarketExcluded("feed_shortage"), false)
    bindWith(EC6.market({ version = 1 }))
    T.eq("X4 a current market excludes nothing", B.isOldMarketExcluded("government_subsidy"), false)
    bindWith(nil)
    T.eq("X5 no market excludes nothing", B.isOldMarketExcluded("crop_yield_bonus"), false)
end

-- =====================================================================
-- M: modifier terms (brief 3.1.3 table, i = 1 and 5)
-- =====================================================================
do
    bindWith(EC6.market({ version = 1 }))
    local function term(name, i, data)
        mgr({ event = name, intensity = i, eventData = data })
        return B.modifier({ fillTypeIndex = 4 })
    end
    local rows = {
        { "market_boom", 1.15, 1.35 }, { "market_crash", 0.85, 0.65 },
        { "harvest_bonus", 1.15, 1.35 }, { "harvest_penalty", 0.85, 0.65 },
        { "field_sale_bonus", 1.05, 1.25 }, { "field_sale_penalty", 0.95, 0.75 },
        { "bonus_trade_prices", 1.15, 1.35 }, { "special_event_festival", 1.08, 1.20 },
    }
    for _, r in ipairs(rows) do
        T.near("M1 " .. r[1] .. " at i 1", term(r[1], 1), r[2], 1e-9)
        T.near("M1 " .. r[1] .. " at i 5", term(r[1], 5), r[3], 1e-9)
    end
    T.near("M2a price_fixing at i 2", term("price_fixing", 2), 1.25, 1e-9)
    T.near("M2b price_fixing at i 5", term("price_fixing", 5), 1.40, 1e-9)
    T.near("M2c export at i 3", term("export_opportunity", 3), 1.40, 1e-9)
    T.near("M2d export at i 5", term("export_opportunity", 5), 1.50, 1e-9)
    T.near("M3a crisis with its price part at i 4", term("economic_crisis", 4, { crisisHasPrice = true }), 0.40, 1e-9)
    T.near("M3b crisis with its price part at i 5", term("economic_crisis", 5, { crisisHasPrice = true }), 0.30, 1e-9)
    T.eq("M3c a loan-only crisis never moves prices", term("economic_crisis", 5, { crisisHasPrice = false, crisisHasLoan = true }), nil)
    T.eq("M4 a non-price event gives no term", term("government_subsidy", 5), nil)
    T.eq("M5 no active event gives no term", term(nil, 3), nil)
    mgr({ event = "market_boom", intensity = nil, configured = 5 })
    T.near("M6 no activation intensity falls back to the configured one", B.modifier({ fillTypeIndex = 1 }), 1.35, 1e-9)
    mgr({ event = "market_boom", intensity = 3, eventData = {} })
    g_RandomWorldEvents.EVENT_STATE.marketBonus = 9
    T.near("M7 the term never reads flag fields", B.modifier({ fillTypeIndex = 1 }), 1.25, 1e-9)
    g_server = nil
    T.eq("M8 a client modifier returns nil", B.modifier({ fillTypeIndex = 1 }), nil)
end

-- =====================================================================
-- C: custom per-fill-type terms
-- =====================================================================
do
    bindWith(EC6.market({ version = 1 }))
    local m = mgr({ event = "vehicle_accident", intensity = 2, custom = { [4] = { multiplier = 1.5 }, [5] = { multiplier = 0 }, [6] = { multiplier = 2, expiresAt = 500 } } })
    T.near("C1 custom term for its fill type", B.modifier({ fillTypeIndex = 4 }), 1.5, 1e-9)
    T.eq("C2 other fill types unaffected", B.modifier({ fillTypeIndex = 7 }), nil)
    T.eq("C3 a zero multiplier is ignored", B.modifier({ fillTypeIndex = 5 }), nil)
    T.eq("C4a an expired entry gives no term", B.modifier({ fillTypeIndex = 6 }), nil)
    T.eq("C4b an expired entry is pruned", m.EVENT_STATE.customPriceModifiers[6], nil)
    m.EVENT_STATE.activeEvent = "market_boom"
    m.EVENT_STATE.activeIntensity = 1
    T.near("C5 event term and custom term multiply", B.modifier({ fillTypeIndex = 4 }), 1.15 * 1.5, 1e-9)
    m.EVENT_STATE.activeEvent = nil
    m.EVENT_STATE.customPriceModifiers = { [4] = { multiplier = 1 } }
    T.eq("C6 a product of exactly 1 returns nil", B.modifier({ fillTypeIndex = 4 }), nil)
end

-- =====================================================================
-- W: status watch
-- =====================================================================
do
    local md = EC6.market({ version = 1 })
    bindWith(md)
    local m = mgr({})
    T.eq("W1 seed stores the current status", B.seed(), "available")
    T.eq("W2a an unchanged read does nothing", B.watch(m), false)
    T.eq("W2b no change call", #m.statusCalls, 0)
    md.settings.pricesEnabled = false
    T.eq("W3a a changed read takes the change path", B.watch(m), true)
    T.eq("W3b exactly one change call with the new status", table.concat(m.statusCalls, ","), "market_prices_off")
    T.eq("W3c the new status is stored", B.lastPriceStatus, "market_prices_off")
    T.eq("W3d the next unchanged read does nothing", B.watch(m), false)
    g_server = nil
    md.settings.pricesEnabled = true
    T.eq("W4 a client never watches", B.watch(m), false)
end

-- =====================================================================
-- R: refresh
-- =====================================================================
do
    local md = EC6.market({ version = 1 })
    bindWith(md)
    T.eq("R1a current market: refresh returns true", B.refresh(), true)
    T.eq("R1b MarketDynamics refreshConsumerPrices called once", md.refreshes, 1)

    local old = EC6.market({ version = 0 })
    bindWith(old)
    T.eq("R2a an old market is never asked to refresh", B.refresh(), false)
    T.eq("R2b no refresh call", old.refreshes, 0)

    local missing = EC6.market({ version = 1, refresh = false })
    bindWith(missing)
    T.eq("R3a a missing refresh returns false", B.refresh(), false)
    T.ok("R3b a missing refresh is logged", EC6.logged("did not recompose"))
    EC6.log = {}
    B.refresh()
    T.eq("R3c logged once per session", EC6.logged("did not recompose"), false)

    bindWith(EC6.market({ version = 1, refreshResult = false }))
    T.eq("R4 a false refresh returns false", B.refresh(), false)
    bindWith(EC6.market({ version = 1, refreshThrows = true }))
    T.eq("R5 a throwing refresh returns false without throwing", B.refresh(), false)
end
