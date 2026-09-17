--!load: tools/test/lua/ec6_harness.lua, events/RWEEventStateEvent.lua, events/RWESettlementNoticeEvent.lua
-- EC-6 RandomWorldEvents: the two server-to-client events on a WIDTH-TYPED tape
-- (brief v1.7 sections 3.5.1 and 3.3.8). A read that names a different type or
-- bit width than the write throws, and sized writes wrap to their width, so a
-- width drift or a reordered field cannot round-trip clean here.
-- Groups: W wire signature, R round trip, N numbers on the wire, L lists, A apply, S settlement notice.

local E = RWEEventStateEvent

local applied = {}
g_RandomWorldEvents = { applySyncedState = function(_, p) applied[#applied + 1] = p end }

local FULL = {
    activeEvent = "economic_crisis", activeIntensity = 5, activeCategory = "economic",
    remainingMs = 3600000, midpointFired = true, priceStatus = "available",
    summaryKey = "rwe_summary_crisis_both", summaryArgs = { "a1", "a2" },
    crisisHasPrice = true, crisisHasLoan = true,
    noticeKind = "start", noticeKey = "rwe_event_economic_crisis_start_both", noticeArgs = { "n1" },
}

local function roundTrip(p)
    EC6.tapeReset()
    local out = E.new(p)
    out:writeStream(1, nil)
    local back = E.emptyNew()
    EC6.tape.pos = 1
    g_server = nil
    applied = {}
    back:readStream(1, { getIsServer = function() return true end })
    g_server = {}
    return back
end

-- =====================================================================
-- W: the exact wire signature
-- =====================================================================
do
    EC6.tapeReset()
    E.new(FULL):writeStream(1, nil)
    T.eq("W1 field order and widths on the wire",
        EC6.signature(),
        "String,UInt3,String,Int32,Bool,String,String,Bool,String,Bool,String,Bool,Bool,Bool,String,String,Bool,String,Bool")
    T.eq("W2 the class is registered", E.className, "RWEEventStateEvent")
end

-- =====================================================================
-- R: round trip
-- =====================================================================
do
    local b = roundTrip(FULL)
    T.eq("R1 activeEvent", b.activeEvent, "economic_crisis")
    T.eq("R2 activeIntensity 5 survives 3 bits", b.activeIntensity, 5)
    T.eq("R3 activeCategory", b.activeCategory, "economic")
    T.eq("R4 remainingMs of one hour survives the width", b.remainingMs, 3600000)
    T.eq("R5 midpointFired", b.midpointFired, true)
    T.eq("R6 priceStatus", b.priceStatus, "available")
    T.eq("R7 summaryKey", b.summaryKey, "rwe_summary_crisis_both")
    T.eq("R8 summaryArgs", table.concat(b.summaryArgs, ","), "a1,a2")
    T.eq("R9 crisisHasPrice", b.crisisHasPrice, true)
    T.eq("R10 crisisHasLoan", b.crisisHasLoan, true)
    T.eq("R11 noticeKind", b.noticeKind, "start")
    T.eq("R12 noticeKey", b.noticeKey, "rwe_event_economic_crisis_start_both")
    T.eq("R13 noticeArgs", table.concat(b.noticeArgs, ","), "n1")
    T.eq("R14 the tape was consumed exactly", EC6.tape.pos, #EC6.tape.entries + 1)

    local long = roundTrip({ activeEvent = "market_boom", activeIntensity = 1, remainingMs = 7200000 })
    T.eq("R15 two hours survives the width", long.remainingMs, 7200000)
    local cleared = roundTrip({})
    T.eq("R16a an empty state sends an empty event", cleared.activeEvent, "")
    T.eq("R16b an empty state sends intensity 0", cleared.activeIntensity, 0)
    local clamped = E.new({ activeIntensity = 9, remainingMs = -5 })
    T.eq("R17a intensity clamped to 5", clamped.activeIntensity, 5)
    T.eq("R17b negative remaining clamped to 0", clamped.remainingMs, 0)
end

-- =====================================================================
-- N: the only numbers on the wire
-- =====================================================================
do
    EC6.tapeReset()
    E.new(FULL):writeStream(1, nil)
    local nums = EC6.numericEntries()
    T.eq("N1 exactly two numbers travel", #nums, 2)
    T.eq("N2a the first is the intensity", nums[1] and nums[1].v, 5)
    T.eq("N2b the second is remainingMs", nums[2] and nums[2].v, 3600000)
    local numericArg = false
    for _, e in ipairs(EC6.tape.entries) do
        if e.kind == "String" and tonumber(e.v) ~= nil then numericArg = true end
    end
    T.eq("N3 no string on the wire is a bare number", numericArg, false)
end

-- =====================================================================
-- L: bounded bool-terminated lists
-- =====================================================================
do
    local many = {}
    for i = 1, 12 do many[i] = "k" .. i end
    local b = roundTrip({ summaryArgs = many })
    T.eq("L1 lists are capped at MAX_LIST", #b.summaryArgs, E.MAX_LIST)
    T.eq("L2 the cap keeps the first entries", b.summaryArgs[8], "k8")
    local none = roundTrip({ noticeArgs = {} })
    T.eq("L3 an empty list round-trips", #none.noticeArgs, 0)
end

-- =====================================================================
-- A: apply on a client only
-- =====================================================================
do
    roundTrip(FULL)
    T.eq("A1 a client applies the received state", #applied, 1)
    applied = {}
    local e = E.new(FULL)
    g_server = {}
    e:run(nil)
    T.eq("A2 a server never applies", #applied, 0)
    g_server = nil
    e:run({ getIsServer = function() return false end })
    T.eq("A3 a state from a non-server connection is ignored", #applied, 0)
    local odd = E.new({ noticeKind = "sneaky" })
    odd:run({ getIsServer = function() return true end })
    T.eq("A4 an unknown notice kind is cleared", odd.noticeKind, "")
    g_server = { broadcastEvent = function(_, ev) applied[#applied + 1] = ev end }
    applied = {}
    T.eq("A5a broadcast on the server", E.broadcast({ activeEvent = "x" }), true)
    T.eq("A5b one broadcast event", #applied, 1)
    g_server = nil
    T.eq("A6 a client never broadcasts", E.broadcast({}), false)
end

-- =====================================================================
-- S: settlement notice wire
-- =====================================================================
do
    EC6.tapeReset()
    RWESettlementNoticeEvent.new("rwe_event_feed_shortage_title", -123456):writeStream(1, nil)
    T.eq("S1 notice wire signature", EC6.signature(), "String,Int32")
    local back = RWESettlementNoticeEvent.emptyNew()
    EC6.tape.pos = 1
    g_server = {}
    back:readStream(1, nil)
    T.eq("S2 a large charge survives the width", back.amount, -123456)
    T.eq("S3 label key", back.labelKey, "rwe_event_feed_shortage_title")
end
