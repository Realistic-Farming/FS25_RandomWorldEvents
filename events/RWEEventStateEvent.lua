-- =========================================================
-- Random World Events - shared event state (EC-6)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Server to client (EC-6 brief v1.7 section 3.5). Every joined player sees the
-- same shared event, its figure-free summary and the price status. Sent at
-- activation, end, the midpoint notice, a price-status change, and to a joining
-- connection from sendInitialClientState.
--
-- THE ONLY NUMBERS IN THIS EVENT ARE activeIntensity AND remainingMs. Every
-- argument is a string or a translation key, the same for every receiver: no euro
-- figure, percentage or per-farm amount ever travels here. String lists are sent
-- as bool-terminated sequences, so no count field is on the wire either.
--
-- An arcade event is host-local and is never sent: while one holds the active
-- slot, this carries an empty activeEvent and no summary.
--
-- Clients display only. A client applies the state with the remaining-offset
-- shape restore already uses (eventStartTime = now, eventDuration = remainingMs).
-- =========================================================

RWEEventStateEvent = RWEEventStateEvent or {}
local RWEEventStateEvent_mt = Class(RWEEventStateEvent, Event)
InitEventClass(RWEEventStateEvent, "RWEEventStateEvent")

RWEEventStateEvent.INTENSITY_BITS = 3     -- 0-5
RWEEventStateEvent.MAX_LIST       = 8     -- bounded string lists
RWEEventStateEvent.NOTICE_KINDS   = { [""] = true, start = true, mid = true, ["end"] = true }

function RWEEventStateEvent.emptyNew()
    return Event.new(RWEEventStateEvent_mt)
end

--- @param p table { activeEvent, activeIntensity, activeCategory, remainingMs, midpointFired,
---                  priceStatus, summaryKey, summaryArgs, crisisHasPrice, crisisHasLoan,
---                  noticeKind, noticeKey, noticeArgs }
function RWEEventStateEvent.new(p)
    local self = RWEEventStateEvent.emptyNew()
    p = p or {}
    self.activeEvent     = p.activeEvent or ""
    self.activeIntensity = math.max(0, math.min(5, math.floor(tonumber(p.activeIntensity) or 0)))
    self.activeCategory  = p.activeCategory or ""
    self.remainingMs     = math.max(0, math.min(2147483647, math.floor(tonumber(p.remainingMs) or 0)))
    self.midpointFired   = p.midpointFired == true
    self.priceStatus     = p.priceStatus or ""
    self.summaryKey      = p.summaryKey or ""
    self.summaryArgs     = p.summaryArgs or {}
    self.crisisHasPrice  = p.crisisHasPrice == true
    self.crisisHasLoan   = p.crisisHasLoan == true
    self.noticeKind      = p.noticeKind or ""
    self.noticeKey       = p.noticeKey or ""
    self.noticeArgs      = p.noticeArgs or {}
    return self
end

local function writeStringList(streamId, list)
    local n = 0
    for _, v in ipairs(list or {}) do
        if n >= RWEEventStateEvent.MAX_LIST then break end
        streamWriteBool(streamId, true)
        streamWriteString(streamId, tostring(v))
        n = n + 1
    end
    streamWriteBool(streamId, false)
end

local function readStringList(streamId)
    local out = {}
    while streamReadBool(streamId) do
        local v = streamReadString(streamId)
        if #out < RWEEventStateEvent.MAX_LIST then out[#out + 1] = v end
    end
    return out
end

RWEEventStateEvent.writeStringList = writeStringList
RWEEventStateEvent.readStringList  = readStringList

function RWEEventStateEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.activeEvent)
    streamWriteUIntN(streamId, self.activeIntensity, RWEEventStateEvent.INTENSITY_BITS)
    streamWriteString(streamId, self.activeCategory)
    streamWriteInt32(streamId, self.remainingMs)
    streamWriteBool(streamId, self.midpointFired)
    streamWriteString(streamId, self.priceStatus)
    streamWriteString(streamId, self.summaryKey)
    writeStringList(streamId, self.summaryArgs)
    streamWriteBool(streamId, self.crisisHasPrice)
    streamWriteBool(streamId, self.crisisHasLoan)
    streamWriteString(streamId, self.noticeKind)
    streamWriteString(streamId, self.noticeKey)
    writeStringList(streamId, self.noticeArgs)
end

function RWEEventStateEvent:readStream(streamId, connection)
    self.activeEvent     = streamReadString(streamId)
    self.activeIntensity = streamReadUIntN(streamId, RWEEventStateEvent.INTENSITY_BITS)
    self.activeCategory  = streamReadString(streamId)
    self.remainingMs     = streamReadInt32(streamId)
    self.midpointFired   = streamReadBool(streamId)
    self.priceStatus     = streamReadString(streamId)
    self.summaryKey      = streamReadString(streamId)
    self.summaryArgs     = readStringList(streamId)
    self.crisisHasPrice  = streamReadBool(streamId)
    self.crisisHasLoan   = streamReadBool(streamId)
    self.noticeKind      = streamReadString(streamId)
    self.noticeKey       = streamReadString(streamId)
    self.noticeArgs      = readStringList(streamId)
    self:run(connection)
end

--- Clients apply; a server never does (a listen host is skipped by the broadcast).
function RWEEventStateEvent:run(connection)
    if g_server ~= nil then return end
    if connection ~= nil and type(connection.getIsServer) == "function" and not connection:getIsServer() then return end
    if not RWEEventStateEvent.NOTICE_KINDS[self.noticeKind] then self.noticeKind = "" end
    if g_RandomWorldEvents ~= nil and type(g_RandomWorldEvents.applySyncedState) == "function" then
        g_RandomWorldEvents:applySyncedState(self)
    end
end

--- Broadcast to every client (server only).
function RWEEventStateEvent.broadcast(p)
    if g_server == nil then return false end
    g_server:broadcastEvent(RWEEventStateEvent.new(p))
    return true
end

--- Send to one connection (join state).
function RWEEventStateEvent.sendTo(connection, p)
    if g_server == nil or connection == nil then return false end
    connection:sendEvent(RWEEventStateEvent.new(p))
    return true
end
