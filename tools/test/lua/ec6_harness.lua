-- EC-6 bench harness (RandomWorldEvents). Loaded through --!load: before the
-- production files. Models only what the EC-6 specs bind to:
--   * Event / InitEventClass and a WIDTH-TYPED stream tape: every write records its
--     type and bit width; every read must name the same type and width or it throws,
--     and sized writes wrap to their width the way the wire does. A width drift or a
--     swapped field therefore fails instead of round-tripping clean (the untyped
--     prelude lane, see the bench-prelude memory).
--   * An in-memory XMLFile store keyed by path.
--   * A world: farms (Farm objects with getLoan), husbandries, vehicles, a mission
--     with addMoney / broadcastEventToFarm / getFarmId, g_server with broadcastEvent,
--     g_messageCenter with subscribe / publish, Time Guard, and a MarketDynamics handle.
-- Every recorder is a plain list so a spec can assert order and count.

EC6 = EC6 or {}

-- ---------------------------------------------------------------------------
-- Event classes
-- ---------------------------------------------------------------------------
Event = Event or {}
function Event.new(mt) return setmetatable({}, mt) end
EC6.eventClasses = {}
function InitEventClass(cls, name)
    cls.className = name
    EC6.eventClasses[#EC6.eventClasses + 1] = name
end

-- ---------------------------------------------------------------------------
-- Width-typed stream tape
-- ---------------------------------------------------------------------------
EC6.tape = { entries = {}, pos = 1 }
function EC6.tapeReset() EC6.tape = { entries = {}, pos = 1 } end

local function wrapSigned(v, bits)
    local m = 2 ^ bits
    v = v % m
    if v >= m / 2 then v = v - m end
    return v
end
local function wrapUnsigned(v, bits) return v % (2 ^ bits) end

local function put(kind, bits, v) local t = EC6.tape; t.entries[#t.entries + 1] = { kind = kind, bits = bits, v = v } end
local function take(kind, bits)
    local t = EC6.tape
    local e = t.entries[t.pos]
    if e == nil then error("stream lane: read " .. kind .. " past the end of the tape") end
    if e.kind ~= kind or e.bits ~= bits then
        error(string.format("stream lane: read %s/%s but the writer wrote %s/%s at entry %d", kind, tostring(bits), e.kind, tostring(e.bits), t.pos))
    end
    t.pos = t.pos + 1
    return e.v
end

function streamWriteString(_, v) assert(type(v) == "string", "streamWriteString needs a string"); put("String", 0, v) end
function streamReadString(_) return take("String", 0) end
function streamWriteBool(_, v) put("Bool", 0, v == true) end
function streamReadBool(_) return take("Bool", 0) end
function streamWriteInt32(_, v) assert(type(v) == "number" and math.floor(v) == v, "streamWriteInt32 needs an integer"); put("Int", 32, wrapSigned(v, 32)) end
function streamReadInt32(_) return take("Int", 32) end
function streamWriteInt16(_, v) put("Int", 16, wrapSigned(math.floor(v), 16)) end
function streamReadInt16(_) return take("Int", 16) end
function streamWriteUInt8(_, v) put("UInt", 8, wrapUnsigned(math.floor(v), 8)) end
function streamReadUInt8(_) return take("UInt", 8) end
function streamWriteUIntN(_, v, bits) assert(type(bits) == "number", "streamWriteUIntN needs a width"); put("UInt", bits, wrapUnsigned(math.floor(v), bits)) end
function streamReadUIntN(_, bits) return take("UInt", bits) end
function streamWriteFloat32(_, v) put("Float", 32, v) end
function streamReadFloat32(_) return take("Float", 32) end

--- The wire signature: "String", "UInt3", "Int32", "Bool", ...
function EC6.signature()
    local out = {}
    for _, e in ipairs(EC6.tape.entries) do out[#out + 1] = e.kind .. (e.bits > 0 and tostring(e.bits) or "") end
    return table.concat(out, ",")
end

--- Every numeric entry on the tape.
function EC6.numericEntries()
    local out = {}
    for _, e in ipairs(EC6.tape.entries) do
        if e.kind == "Int" or e.kind == "UInt" or e.kind == "Float" then out[#out + 1] = e end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- XMLFile memory store
-- ---------------------------------------------------------------------------
EC6.xmlStore = {}
local function xmlObject(path, data)
    local x = { path = path, data = data }
    local function setter(self, key, v) self.data[key] = v end
    local function getter(self, key, default) local v = self.data[key]; if v == nil then return default end; return v end
    x.setString, x.setInt, x.setFloat, x.setBool = setter, setter, setter, setter
    x.getString, x.getInt, x.getFloat, x.getBool = getter, getter, getter, getter
    function x:save() EC6.xmlStore[self.path] = self.data end
    function x:delete() end
    return x
end
XMLFile = XMLFile or {}
function XMLFile.create(_, path, _) return xmlObject(path, {}) end
function XMLFile.load(_, path)
    local d = EC6.xmlStore[path]
    if d == nil then return nil end
    local copy = {}
    for k, v in pairs(d) do copy[k] = v end
    return xmlObject(path, copy)
end
fileExists = function(path) return EC6.xmlStore[path] ~= nil end

-- Native hook targets the core appends to at load (they must exist first).
FSBaseMission.sendInitialClientState = FSBaseMission.sendInitialClientState or function() end
FSCareerMissionInfo.saveToXMLFile = FSCareerMissionInfo.saveToXMLFile or function() end
FSBaseMission.INGAME_NOTIFICATION_OK = FSBaseMission.INGAME_NOTIFICATION_OK or 1
FSBaseMission.INGAME_NOTIFICATION_CRITICAL = FSBaseMission.INGAME_NOTIFICATION_CRITICAL or 2
FSBaseMission.INGAME_NOTIFICATION_INFO = FSBaseMission.INGAME_NOTIFICATION_INFO or 3

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
MessageType = MessageType or {}
MessageType.DAY_CHANGED  = MessageType.DAY_CHANGED or "DAY_CHANGED"
MessageType.FARM_DELETED = MessageType.FARM_DELETED or "FARM_DELETED"
MoneyType.LOAN_INTEREST  = MoneyType.LOAN_INTEREST or 20
MoneyType.VEHICLE_REPAIR = MoneyType.VEHICLE_REPAIR or 21
FarmManager.GUIDED_TOUR_FARM_ID = FarmManager.GUIDED_TOUR_FARM_ID or 16

EC6.subs = {}
g_messageCenter = {
    subscribe = function(_, msg, fn, target) EC6.subs[#EC6.subs + 1] = { msg = msg, fn = fn, target = target } end,
    unsubscribe = function(_, msg, target)
        for i = #EC6.subs, 1, -1 do
            if EC6.subs[i].msg == msg and EC6.subs[i].target == target then table.remove(EC6.subs, i) end
        end
    end,
    publish = function(_, msg, ...)
        local list = {}
        for _, s in ipairs(EC6.subs) do if s.msg == msg then list[#list + 1] = s end end
        for _, s in ipairs(list) do s.fn(s.target, ...) end
    end,
}
function EC6.subCount(msg)
    local n = 0
    for _, s in ipairs(EC6.subs) do if s.msg == msg then n = n + 1 end end
    return n
end

-- ---------------------------------------------------------------------------
-- World
-- ---------------------------------------------------------------------------
EC6.log = {}
Logging.info = function(fmt, ...) local ok, s = pcall(string.format, fmt, ...); EC6.log[#EC6.log + 1] = ok and s or tostring(fmt) end
Logging.warning = Logging.info
Logging.error = Logging.info
function EC6.logged(pattern)
    for _, line in ipairs(EC6.log) do if string.find(line, pattern, 1, true) then return true end end
    return false
end

function EC6.newFarm(id, loan)
    local f = { farmId = id, loan = loan or 0 }
    function f:getLoan() return self.loan end
    return f
end

--- Build a fresh world. opts: farms = { {id, loan}... } in the ORDER the farm
--- manager returns them; localFarmId; day; server (default true).
function EC6.world(opts)
    opts = opts or {}
    local w = { farms = {}, byId = {}, money = {}, farmBroadcasts = {}, broadcasts = {}, calls = {} }
    for _, spec in ipairs(opts.farms or {}) do
        local f = EC6.newFarm(spec[1], spec[2])
        w.farms[#w.farms + 1] = f
        w.byId[f.farmId] = f
    end
    w.husbandries, w.vehicles = {}, {}
    w.mission = {
        time = opts.time or 1000,
        environment = { currentMonotonicDay = opts.day or 10, currentDay = opts.day or 10 },
        husbandrySystem = { placeables = w.husbandries },
        vehicleSystem = { vehicles = w.vehicles },
        missionInfo = { savegameDirectory = "save1" },
        getIsServer = function() return opts.server ~= false end,
        getIsClient = function() return true end,
        addIngameNotification = function() end,
        localFarmId = opts.localFarmId,
    }
    function w.mission:getFarmId() return self.localFarmId end
    function w.mission:addMoney(amount, farmId, moneyType, addChange, showChange)
        w.calls[#w.calls + 1] = "addMoney"
        if w.throwOnAddMoney then error("addMoney threw") end
        w.money[#w.money + 1] = { amount = amount, farmId = farmId, moneyType = moneyType, addChange = addChange, showChange = showChange }
        if w.onAddMoney then w.onAddMoney(amount, farmId) end
    end
    function w.mission:broadcastEventToFarm(event, farmId, sendLocal)
        w.calls[#w.calls + 1] = "broadcastEventToFarm"
        w.farmBroadcasts[#w.farmBroadcasts + 1] = { event = event, farmId = farmId, sendLocal = sendLocal }
    end
    g_currentMission = w.mission
    g_farmManager = {
        getFarms = function() return w.farms end,
        getFarmById = function(_, id) return w.byId[id] end,
    }
    if opts.server == false then g_server = nil else
        g_server = { broadcastEvent = function(_, event) w.calls[#w.calls + 1] = "broadcastEvent"; w.broadcasts[#w.broadcasts + 1] = event end }
    end
    EC6.subs = {}
    EC6.log = {}
    return w
end

function EC6.addHusbandry(w, owner, animals, throws)
    local p = { owner = owner, animals = animals }
    function p:getOwnerFarmId() return self.owner end
    function p:getNumOfAnimals() if throws then error("husbandry threw") end; return self.animals end
    w.husbandries[#w.husbandries + 1] = p
    return p
end

function EC6.addVehicle(w, owner, motorized, damage)
    local v = { owner = owner, damage = damage or 0 }
    if motorized then v.spec_motorized = {} end
    function v:getOwnerFarmId() return self.owner end
    function v:getDamageAmount() return self.damage end
    w.vehicles[#w.vehicles + 1] = v
    return v
end

--- Reuse a farm id: the id now resolves to a NEW Farm object.
function EC6.replaceFarm(w, id, loan)
    local f = EC6.newFarm(id, loan)
    for i, old in ipairs(w.farms) do if old.farmId == id then w.farms[i] = f end end
    w.byId[id] = f
    return f
end

function EC6.removeFarm(w, id)
    for i = #w.farms, 1, -1 do if w.farms[i].farmId == id then table.remove(w.farms, i) end end
    w.byId[id] = nil
end

function EC6.setDay(w, day)
    w.mission.environment.currentMonotonicDay = day
    w.mission.environment.currentDay = day
end

-- Time Guard
function EC6.timeGuard()
    local tg = { accruals = {}, unregistered = {} }
    function tg:registerAccrual(id, def) self.accruals[id] = def; return true end
    function tg:unregisterAccrual(id) self.unregistered[#self.unregistered + 1] = id; self.accruals[id] = nil end
    return tg
end

-- MarketDynamics handle
function EC6.market(opts)
    opts = opts or {}
    local md = { settings = { pricesEnabled = opts.pricesEnabled ~= false }, modifiers = {}, refreshes = 0, calls = opts.calls }
    md.rweConsumerContractVersion = opts.version
    function md:registerPriceModifier(name, fn)
        if opts.throwOnRegister then error("register threw") end
        self.modifiers[name] = fn
    end
    function md:unregisterPriceModifier(name) self.modifiers[name] = nil; self.unregistered = name end
    if opts.refresh ~= false then
        function md:refreshConsumerPrices()
            self.refreshes = self.refreshes + 1
            if self.calls then self.calls[#self.calls + 1] = "refresh" end
            if opts.refreshThrows then error("refresh threw") end
            return opts.refreshResult ~= false
        end
    end
    return md
end

-- Translations: a key resolves to "T(key)" so a spec can see it was translated.
g_i18n = {
    hasText = function(_, key) return EC6.i18nMissing == nil or not EC6.i18nMissing[key] end,
    getText = function(_, key) return "T(" .. tostring(key) .. ")" end,
    formatMoney = function(_, amount) return "M(" .. tostring(amount) .. ")" end,
}
