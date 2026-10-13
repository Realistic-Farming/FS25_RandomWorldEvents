-- =========================================================
-- Random World Events - private settlement notice (EC-6)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Server to the players of ONE farm (EC-6 brief v1.7 section 3.3.8). settle()
-- sends it after a statement line posted, with broadcastEventToFarm, so only
-- clients whose player is on the paid farm receive it; the host connection is
-- skipped and a listen host on that farm is shown the notice locally instead. No
-- other farm and no dedicated-server console ever sees another farm's amount.
--
-- Payload: labelKey (the event's statement-line key) and amount (signed whole
-- euros). The native addMoney notice is the other half of the private feedback.
-- =========================================================

RWESettlementNoticeEvent = RWESettlementNoticeEvent or {}
local RWESettlementNoticeEvent_mt = Class(RWESettlementNoticeEvent, Event)
InitEventClass(RWESettlementNoticeEvent, "RWESettlementNoticeEvent")

function RWESettlementNoticeEvent.emptyNew()
    return Event.new(RWESettlementNoticeEvent_mt)
end

function RWESettlementNoticeEvent.new(labelKey, amount)
    local self = RWESettlementNoticeEvent.emptyNew()
    self.labelKey = labelKey or ""
    self.amount   = math.floor(tonumber(amount) or 0)
    return self
end

function RWESettlementNoticeEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.labelKey)
    streamWriteInt32(streamId, self.amount)
end

function RWESettlementNoticeEvent:readStream(streamId, connection)
    self.labelKey = streamReadString(streamId)
    self.amount   = streamReadInt32(streamId)
    self:run(connection)
end

function RWESettlementNoticeEvent:run(connection)
    if g_server ~= nil then return end
    if connection ~= nil and type(connection.getIsServer) == "function" and not connection:getIsServer() then return end
    RWESettlementNoticeEvent.show(self.labelKey, self.amount)
end

--- The notice text: the event's statement line and this farm's own amount.
function RWESettlementNoticeEvent.text(labelKey, amount)
    local function t(key)
        if g_i18n ~= nil and type(g_i18n.hasText) == "function" and g_i18n:hasText(key) then return g_i18n:getText(key) end
        return key
    end
    local money = tostring(amount)
    if g_i18n ~= nil and type(g_i18n.formatMoney) == "function" then
        local ok, formatted = pcall(g_i18n.formatMoney, g_i18n, amount, 0, true, true)
        if ok and type(formatted) == "string" then money = formatted end
    end
    local ok, text = pcall(string.format, t("rwe_settlement_notice"), t(labelKey), money)
    if ok then return text end
    return t(labelKey) .. ": " .. money
end

function RWESettlementNoticeEvent.show(labelKey, amount)
    local text = RWESettlementNoticeEvent.text(labelKey, amount)
    local mgr = g_RandomWorldEvents
    if mgr ~= nil and type(mgr.notifyEvent) == "function" then
        mgr:notifyEvent(text, "economic", (tonumber(amount) or 0) > 0 and true or "warn")
    end
    return text
end
