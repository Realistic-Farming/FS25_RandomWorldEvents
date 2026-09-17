-- =========================================================
-- Random World Events - MarketDynamics price bridge (EC-6)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- RandomWorldEvents' one price path (EC-6 brief v1.7 section 3.1). World-event
-- price swings reach selling points only through MarketDynamics' registered
-- consumer modifier; MarketDynamics owns composition, the 0.5-3.0 clamp and the
-- quote. The old EconomyManager.getPricePerLiter patch is gone: selling stations
-- never read it, while fill-trigger purchases, bale value and production payouts
-- did.
--
-- ONE PRICE PATH PER INSTALL. RandomWorldEvents registers only beside a
-- MarketDynamics that declares rweConsumerContractVersion >= 1, which means that
-- MarketDynamics carries no RandomWorldEvents reader of its own and offers
-- refreshConsumerPrices(). An older MarketDynamics still prices events by name
-- itself; registering beside it would apply two price paths to one event, so
-- nothing is registered and the events it would price stay ineligible.
--
-- The market kind (absent, old, current) is fixed once at bind. The price status
-- is re-read every server update: a MarketDynamics prices switch reaches
-- RandomWorldEvents only through that watch, because MarketDynamics publishes no
-- change message. Server only; a client shows the synced status.
-- =========================================================

RWEMarketBridge = RWEMarketBridge or {}
local B = RWEMarketBridge

B.MODIFIER_NAME    = "RandomWorldEvents"
B.CONTRACT_VERSION = 1

B.STATUS_AVAILABLE      = "available"
B.STATUS_PRICES_OFF     = "market_prices_off"
B.STATUS_UPDATE_NEEDED  = "market_update_needed"
B.STATUS_NO_MARKET      = "no_market"

B.market            = B.market or "absent"   -- absent | old | current
B.live              = B.live or false
B.handle            = B.handle
B.lastPriceStatus   = B.lastPriceStatus
B.clientPriceStatus = B.clientPriceStatus    -- display copy on a client, from the state event
B._refreshLogged    = B._refreshLogged or false

-- Price terms while the event is active; i = the activation intensity (1-5).
-- Magnitudes are the pre-EC-6 ones. MarketDynamics clamps the product of every
-- registered modifier; the clamp is the authority's promise, not ours.
B.PRICE_TERMS = {
    market_boom            = function(i) return 1 + (0.10 + 0.05 * i) end,
    market_crash           = function(i) return 1 - (0.10 + 0.05 * i) end,
    price_fixing           = function(i) return 1 + (0.15 + 0.05 * i) end,
    export_opportunity     = function(i) return 1 + (0.25 + 0.05 * i) end,
    economic_crisis        = function(i) return 1 - (0.20 + 0.10 * i) end,
    harvest_bonus          = function(i) return 1 + (0.10 + 0.05 * i) end,
    harvest_penalty        = function(i) return 1 - (0.10 + 0.05 * i) end,
    field_sale_bonus       = function(i) return 1 + 0.05 * i end,
    field_sale_penalty     = function(i) return 1 - 0.05 * i end,
    bonus_trade_prices     = function(i) return 1 + (0.10 + 0.05 * i) end,
    special_event_festival = function(i) return 1 + (0.05 + 0.03 * i) end,
}

-- Names an older MarketDynamics reader prices even though they are not price
-- events here (plus the whole crisis). While the status is "market_update_needed"
-- they are ineligible, because RandomWorldEvents cannot stop that reader.
B.OLD_READER_EXTRA = {
    government_subsidy = true,
    crop_yield_bonus   = true,
    crop_yield_penalty = true,
    economic_crisis    = true,
}

local function log(msg) Logging.info("[RWE] " .. tostring(msg)) end

function B.isPriceEvent(name)
    return name ~= nil and B.PRICE_TERMS[name] ~= nil
end

--- True when an older MarketDynamics would price this event name by itself.
function B.isOldMarketExcluded(name)
    return B.priceStatus() == B.STATUS_UPDATE_NEEDED and name ~= nil
        and (B.PRICE_TERMS[name] ~= nil or B.OLD_READER_EXTRA[name] == true)
end

--- Bind once at loadMission00Finished on the server, before the restore block.
--- MarketDynamics publishes its handle at its own Mission00.load.
function B.bind()
    B.market, B.live, B.handle = "absent", false, nil
    if g_server == nil then return B.market end

    local okH, handle = pcall(function()
        return (g_currentMission ~= nil and g_currentMission.MarketDynamics) or g_MarketDynamics
    end)
    if not okH or type(handle) ~= "table" or type(handle.registerPriceModifier) ~= "function" then
        log("MarketDynamics not present: market price events are unavailable")
        return B.market
    end

    local okV, version = pcall(function() return handle.rweConsumerContractVersion end)
    if not okV or type(version) ~= "number" or version < B.CONTRACT_VERSION then
        B.market, B.handle = "old", handle
        log("MarketDynamics does not declare rweConsumerContractVersion >= 1: nothing registered, update MarketDynamics to enable market price events")
        return B.market
    end

    local okR, err = pcall(handle.registerPriceModifier, handle, B.MODIFIER_NAME, B.modifier)
    if not okR then
        Logging.warning("[RWE] MarketDynamics price modifier registration failed (%s); market price events are unavailable", tostring(err))
        return B.market
    end
    B.market, B.live, B.handle = "current", true, handle
    log("registered the RandomWorldEvents price modifier with MarketDynamics")
    return B.market
end

--- Delete path: unregister only when live.
function B.unbind()
    if B.live and B.handle ~= nil and type(B.handle.unregisterPriceModifier) == "function" then
        pcall(B.handle.unregisterPriceModifier, B.handle, B.MODIFIER_NAME)
    end
    B.market, B.live, B.handle = "absent", false, nil
    B.lastPriceStatus = nil
    B.clientPriceStatus = nil
end

--- The server's price status. A field compare, never a price read.
function B.priceStatus()
    if B.live then
        local ok, enabled = pcall(function() return B.handle.settings.pricesEnabled ~= false end)
        if ok and enabled then return B.STATUS_AVAILABLE end
        return B.STATUS_PRICES_OFF
    end
    if B.market == "old" then return B.STATUS_UPDATE_NEEDED end
    return B.STATUS_NO_MARKET
end

--- The status a player sees: the server's own read, or the synced copy on a client.
function B.displayStatus()
    if g_server ~= nil then return B.priceStatus() end
    return B.clientPriceStatus
end

--- Seed the watch at restore, whether or not an event is restored.
function B.seed()
    B.lastPriceStatus = B.priceStatus()
    return B.lastPriceStatus
end

--- Once per server update, before the scheduler: an unchanged read does nothing;
--- a change is stored and handed to the manager's one change path.
function B.watch(mgr)
    if g_server == nil then return false end
    local status = B.priceStatus()
    if status == B.lastPriceStatus then return false end
    B.lastPriceStatus = status
    if mgr ~= nil and type(mgr.onPriceStatusChanged) == "function" then
        mgr:onPriceStatusChanged(status)
    end
    return true
end

--- Ask MarketDynamics, through its public refresh only, to recompose current quotes.
--- Missing, false or throwing is logged once per session and otherwise ignored:
--- MarketDynamics then recomposes on its own clock.
function B.refresh()
    if B.market ~= "current" or B.handle == nil then return false end
    local fn = B.handle.refreshConsumerPrices
    local ok, result = false, nil
    if type(fn) == "function" then
        ok, result = pcall(fn, B.handle)
    end
    if not ok or result ~= true then
        if not B._refreshLogged then
            B._refreshLogged = true
            Logging.warning("[RWE] MarketDynamics refreshConsumerPrices did not recompose (%s); quotes update at the next market update",
                type(fn) ~= "function" and "missing" or (ok and tostring(result) or "error"))
        end
        return false
    end
    return true
end

--- The registered consumer modifier: ctx = { fillTypeIndex, basePrice, marketPrice }.
--- Returns the product of the active terms, or nil when none applies or the
--- product is exactly 1. Reads the event name and activation intensity, never the
--- flag fields, so a resumed event keeps its term.
function B.modifier(ctx)
    if g_server == nil then return nil end
    local mgr = g_RandomWorldEvents
    if mgr == nil or mgr.EVENT_STATE == nil then return nil end
    local es = mgr.EVENT_STATE

    local product, applied = 1, false
    local name = es.activeEvent
    local term = name ~= nil and B.PRICE_TERMS[name] or nil
    if term ~= nil then
        -- A crisis moves prices only when its price part was announced and still holds.
        local allowed = name ~= "economic_crisis" or (type(es.eventData) == "table" and es.eventData.crisisHasPrice == true)
        if allowed then
            local i = es.activeIntensity or (mgr.events ~= nil and mgr.events.intensity) or 1
            product = product * term(i)
            applied = true
        end
    end

    local mods = es.customPriceModifiers
    local fillTypeIndex = type(ctx) == "table" and ctx.fillTypeIndex or nil
    if type(mods) == "table" and fillTypeIndex ~= nil then
        local entry = mods[fillTypeIndex]
        if type(entry) == "table" then
            if entry.expiresAt ~= nil and g_currentMission ~= nil and g_currentMission.time > entry.expiresAt then
                mods[fillTypeIndex] = nil
            elseif type(entry.multiplier) == "number" and entry.multiplier > 0 then
                product = product * entry.multiplier
                applied = true
            end
        end
    end

    if not applied or product == 1 or product <= 0 then return nil end
    return product
end
