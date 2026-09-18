--!load: tools/test/lua/ec6_harness.lua, events/RWENotificationEvent.lua, RandomWorldEvents.lua
-- RandomWorldEvents: the shared server-to-clients notification event.
--
-- Every assertion about delivery goes through a STREAM ROUND TRIP, never a direct
-- call to run. That is deliberate. The engine never calls run on the receive path
-- (Client.lua:417-419 and Server.lua:435-437 do emptyNew, readStream, delete), and
-- run fires only on the local loopback (Connection.lua:72-74). So a direct call to
-- run proves behaviour and not reachability, and the one bug it cannot see is the
-- effect never executing for a joined player. These rows fail if the readStream
-- bridge is removed.
--
-- The tape is width-typed: a read naming a different kind or bit width than the
-- write throws, so a field reorder or a UIntN width drift cannot round-trip clean.
-- Groups: W wire signature, R round trip and tone fidelity, B bit accounting,
-- H host notified once, C a client never rebroadcasts.

local E = RWENotificationEvent

-- What presentNotification did, recorded by replacing nothing: these are the real
-- functions on the real class, called on a minimal object.
local shown = {}
local function newMgr()
    shown = {}
    return setmetatable({
        eventHUD = { pushFlash = function(_, msg, cat, tone)
            shown[#shown + 1] = { via = "flash", msg = msg, cat = cat, tone = tone }
        end },
        events = { showNotifications = false },
    }, { __index = RandomWorldEvents })
end

-- The manager the event's run reaches on a client.
local function installMgr()
    g_RandomWorldEvents = newMgr()
    return g_RandomWorldEvents
end

local SERVER_CONN = { getIsServer = function() return true end }

--- Write, then read back into a FRESH instance, exactly as the engine does.
--- Returns the receiving instance; the effect is observed in `shown`.
local function roundTrip(message, categoryKey, tone, asHost)
    EC6.tapeReset()
    local out = E.new(message, categoryKey, tone)
    out:writeStream(1, nil)

    local back = E.emptyNew()
    EC6.tape.pos = 1
    local savedServer = g_server
    g_server = asHost and {} or nil
    installMgr()
    back:readStream(1, SERVER_CONN)
    g_server = savedServer
    return back
end

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group crashed]", false, tostring(err)) end
end

-- =====================================================================
-- W: the exact wire signature
-- =====================================================================
group("W wire signature", function()
    EC6.tapeReset()
    E.new("hello", "economic", true):writeStream(1, nil)
    T.eq("W1 field order and widths on the wire", EC6.signature(), "String,String,UInt2")
    T.eq("W2 the class is registered by name", E.className, "RWENotificationEvent")
end)

-- =====================================================================
-- R: round trip, and tone survives as a value not just a shape
-- =====================================================================
group("R round trip", function()
    -- The tone cases must DIFFER from each other, or a constant would satisfy
    -- every row and the fixture would pass while carrying nothing.
    local cases = {
        { tone = true,   expect = true,   label = "positive" },
        { tone = "warn", expect = "warn", label = "warn" },
        { tone = false,  expect = nil,    label = "false decodes to neutral" },
        { tone = nil,    expect = nil,    label = "nil stays neutral" },
    }
    for i, c in ipairs(cases) do
        roundTrip("msg " .. c.label, "cat " .. c.label, c.tone, false)
        T.eq("R" .. i .. "a effect fired via readStream (" .. c.label .. ")", #shown, 1)
        T.eq("R" .. i .. "b message survived (" .. c.label .. ")", shown[1] and shown[1].msg, "msg " .. c.label)
        T.eq("R" .. i .. "c category survived (" .. c.label .. ")", shown[1] and shown[1].cat, "cat " .. c.label)
        T.eq("R" .. i .. "d tone survived (" .. c.label .. ")", shown[1] and shown[1].tone, c.expect)
    end
end)

-- =====================================================================
-- B: the reader consumes exactly what the writer wrote
-- =====================================================================
group("B bit accounting", function()
    roundTrip("accounting", "economic", "warn", false)
    T.eq("B1 reader consumed every entry the writer wrote",
        EC6.tape.pos, #EC6.tape.entries + 1)

    -- A field the writer never wrote must not be readable: the engine reports
    -- this as "Not all bits read in event" (Client.lua:421-425), and here the
    -- width-typed tape throws on a read past the end.
    local ok = pcall(function() return streamReadString(1) end)
    T.ok("B2 reading past the end of the tape throws", not ok)
end)

-- =====================================================================
-- H: a listen host is notified exactly once
-- =====================================================================
group("H host notified once", function()
    local mgr = newMgr()
    local sent = {}
    local savedServer = g_server
    g_server = { broadcastEvent = function(_, event, sendLocal)
        sent[#sent + 1] = { event = event, sendLocal = sendLocal }
    end }

    mgr:notifyEvent("host message", "economic", true)

    T.eq("H1 host presented locally exactly once", #shown, 1)
    T.eq("H2 broadcast sent exactly once", #sent, 1)
    T.eq("H3 sendLocal is false, so broadcastEvent skips the loopback",
        sent[1] and sent[1].sendLocal, false)
    T.eq("H4 the broadcast carries the same message", sent[1] and sent[1].event.message, "host message")

    -- Belt and braces: even if the host somehow received its own event back,
    -- run refuses while g_server is set, so it still presents only once.
    roundTrip("host message", "economic", true, true)
    T.eq("H5 a host that receives its own event applies nothing", #shown, 0)

    g_server = savedServer
end)

-- =====================================================================
-- C: a client presents but never rebroadcasts
-- =====================================================================
group("C client does not rebroadcast", function()
    local savedServer = g_server
    local sent = {}
    g_server = nil   -- a pure client has no server

    roundTrip("client message", "field", "warn", false)
    T.eq("C1 client presented the notification", #shown, 1)

    -- run reaches presentNotification, never notifyEvent, so the announce path
    -- cannot be re-entered. If it called notifyEvent, this client would have
    -- attempted a broadcast the moment g_server existed.
    local mgr = newMgr()
    g_server = { broadcastEvent = function(_, e, s) sent[#sent + 1] = { e = e, s = s } end }
    mgr:presentNotification("present only", "field", true)
    T.eq("C2 presentNotification is purely local", #sent, 0)
    T.eq("C3 presentNotification still presents", #shown, 1)

    g_server = savedServer
end)
