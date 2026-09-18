-- =========================================================
-- Random World Events - shared event notification
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Server to all clients. Every RWE announcement travels here, because every
-- announcement funnels through RandomWorldEvents:notifyEvent and always has.
-- Before this event nothing left the machine: notifyEvent ended in eventHUD
-- flash plus addIngameNotification, and addIngameNotification is
-- hud:addSideNotification (FSBaseMission.lua:1888-1890), purely local. So on a
-- listen host only the host ever saw an event fire, and on a dedicated server
-- nobody did. Every joined player sat through effects with no explanation.
--
-- Payload is presentation only: the resolved display text, the category key and
-- a two-bit tone. No figures, no per-farm amounts, no game state. A client that
-- receives this only draws it; nothing here changes the world.
--
-- WHY THE EFFECT LIVES IN readStream. The engine NEVER calls run on the receive
-- path: Client.lua:417-419 and Server.lua:435-437 both do emptyNew, then
-- readStream, then delete. run is called only on the local loopback send
-- (Connection.lua:72-74), where the event never touches a stream. The two paths
-- are mirror images and neither exercises the other, so an effect that lives
-- only in run is dead for exactly the joined players this exists to fix.
-- readStream therefore reads the fields and calls self:run(connection) as its
-- last line, the same bridge GamePauseEvent uses.
--
-- WHY InitEventClass AND NOT InitStaticEventClass. InitStaticEventClass
-- (EventIds.lua:21-32) assigns a compile-time id from a counter the base game
-- owns and requires g_server and g_client to both be nil, which is not true for
-- a mod loading into a client that has already connected. InitEventClass
-- (EventIds.lua:7-20) registers by NAME into EventIds.eventClasses, which is the
-- table Server.sendEventIds (Server.lua:558-571) walks to tell each joining
-- client the id-to-name mapping. That negotiation is what makes a mod event work
-- across peers, so load order does not have to match.
-- =========================================================

RWENotificationEvent = RWENotificationEvent or {}
local RWENotificationEvent_mt = Class(RWENotificationEvent, Event)
InitEventClass(RWENotificationEvent, "RWENotificationEvent")

-- Tone travels as a bounded code, never as a raw value, because isPositive is a
-- mixed-type field: true, false, nil or the string "warn". All four are distinct
-- on the wire.
--
-- false and nil must NOT be collapsed together, even though the ingame-notification
-- branch treats them alike (both fall through to INGAME_NOTIFICATION_INFO). The HUD
-- flash is the other consumer and it distinguishes them: RWEEventHUD:pushFlash stores
-- `isPositive = isPositive ~= false` (gui/RWEEventHUD.lua:181), so nil becomes true
-- and false stays false, and that value picks the flash colour at :647, READY against
-- DISABLED. Collapsing false to neutral would render DISABLED on the host and READY on
-- every client: a silent host-client divergence, the exact class of defect this event
-- exists to remove. pushFlash's own doc at :176 calls false a "bad event", so it is a
-- meaningful value there rather than an accident.
RWENotificationEvent.TONE_BITS     = 2   -- four codes, and all four are used
RWENotificationEvent.TONE_NEUTRAL  = 0   -- nil
RWENotificationEvent.TONE_POSITIVE = 1   -- true
RWENotificationEvent.TONE_WARN     = 2   -- "warn"
RWENotificationEvent.TONE_FALSE    = 3   -- false, distinct from nil for the HUD flash

--- true / false / nil / "warn"  ->  bounded code. All four map distinctly.
function RWENotificationEvent.toneToCode(isPositive)
    if isPositive == true then return RWENotificationEvent.TONE_POSITIVE end
    if isPositive == "warn" then return RWENotificationEvent.TONE_WARN end
    if isPositive == false then return RWENotificationEvent.TONE_FALSE end
    return RWENotificationEvent.TONE_NEUTRAL
end

--- bounded code -> true / false / nil / "warn". An unknown code reads as neutral
--- rather than erroring, so a future sender cannot break an older receiver.
function RWENotificationEvent.codeToTone(code)
    if code == RWENotificationEvent.TONE_POSITIVE then return true end
    if code == RWENotificationEvent.TONE_WARN then return "warn" end
    if code == RWENotificationEvent.TONE_FALSE then return false end
    return nil
end

function RWENotificationEvent.emptyNew()
    return Event.new(RWENotificationEvent_mt)
end

--- @param message     string resolved display text (never nil on the wire)
--- @param categoryKey string event category, "" when absent
--- @param isPositive  true | false | nil | "warn"
function RWENotificationEvent.new(message, categoryKey, isPositive)
    local self = RWENotificationEvent.emptyNew()
    self.message     = message or ""
    self.categoryKey = categoryKey or ""
    self.toneCode    = RWENotificationEvent.toneToCode(isPositive)
    return self
end

function RWENotificationEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.message)
    streamWriteString(streamId, self.categoryKey)
    streamWriteUIntN(streamId, self.toneCode, RWENotificationEvent.TONE_BITS)
end

--- Field order mirrors writeStream exactly. The engine validates that every bit
--- written was read and printErrors "Not all bits read in event" otherwise
--- (Client.lua:421-425), so the two must not drift apart.
function RWENotificationEvent:readStream(streamId, connection)
    self.message     = streamReadString(streamId)
    self.categoryKey = streamReadString(streamId)
    self.toneCode    = streamReadUIntN(streamId, RWENotificationEvent.TONE_BITS)
    self:run(connection)
end

--- Draw it, and only draw it. The server never applies its own notification: it
--- has already presented locally, and the broadcast goes out with sendLocal
--- false so the loopback connection is skipped. The g_server guard pins that
--- "host is notified once" property even if the send side were ever changed.
--- presentNotification is called rather than notifyEvent, so a client can never
--- re-enter the announce path and rebroadcast.
function RWENotificationEvent:run(connection)
    if g_server ~= nil then return end
    if connection ~= nil and type(connection.getIsServer) == "function" and not connection:getIsServer() then return end

    local mgr = g_RandomWorldEvents
    if mgr == nil or type(mgr.presentNotification) ~= "function" then return end
    if self.message == nil or self.message == "" then return end

    mgr:presentNotification(self.message,
        self.categoryKey ~= "" and self.categoryKey or nil,
        RWENotificationEvent.codeToTone(self.toneCode))
end
