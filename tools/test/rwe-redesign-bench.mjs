// RWE redesign (non-price half) bench.
//
// Two layers, both runnable here:
//   A. The vendored OptionScalingResolver (pure library, byte-identical to the
//      SettingsHub spine branch) executed in a real Lua 5.1 VM (fengari):
//      OFF/absent == neutral, canonical World-events curve anchors, switch off.
//   B. Structural assertions over the ACTUAL source files: the 13 cut events and
//      the 4 events EC-6 retired are gone, the 4 arcade-physics events carry the
//      toggle gate, the money trickle handlers are removed, the reputation write
//      is gone, the engine price patch is gone (EC-6), the damage patch is
//      arcade-gated, and the core read/difficulty surface is present.
//      EC-6: the catalogue and the gates are read from the STORED definitions,
//      captured by running the five event modules in the Lua VM against a
//      recording registerEvent. A name literal in the source proves nothing: the
//      field and wildlife modules build most events through helper functions, and
//      the gate the scheduler reads is the one the registration loop stored.
//
// The mod has no in-engine test harness; this is the stand-in. Usage:
//   node tools/test/rwe-redesign-bench.mjs <repo-root>
import { readFileSync } from "node:fs";
import { join } from "node:path";
import luaparse from "luaparse";

const ROOT = process.argv[2] || ".";
let pass = 0;
let failCount = 0;
const ok = (msg) => { pass++; console.log(`  \u2713 ${msg}`); };
const fail = (msg) => { failCount++; console.error(`  \u2717 ${msg}`); };

// ---------------------------------------------------------------------------
// A. Resolver contract in a real Lua 5.1 VM
// ---------------------------------------------------------------------------
try {
  const { lua, lauxlib, lualib, to_luastring } = await import("fengari");
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const resolverSrc = readFileSync(join(ROOT, "utils/OptionScalingResolver.lua"), "utf8");
  if (lauxlib.luaL_loadstring(L, to_luastring(resolverSrc)) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
    throw new Error("resolver failed to load in the Lua VM: " + lua.lua_tostring(L, -1));
  }

  // runExpr evaluates a Lua body that can build a mock settingsHub with set()
  // and call OptionScalingResolver.readProfile/resolve. Returns true/false.
  const runExpr = (body) => {
    const code = `local R = OptionScalingResolver
      local store = {}
      local function val(self, module, key)
        if module ~= R.MODULE then return nil end
        if key == R.PRESET_KEY then return store.preset or "standard" end
        if key:match("^dial_") then return store.dials and store.dials[key:sub(6)] end
        if key:match("^switch_") then return store.switches and store.switches[key:sub(8)] end
        return nil
      end
      local hub = { getValue = val }
      local function set(dials, switches, preset)
        store.dials = dials; store.switches = switches; store.preset = preset or "standard"
      end
      return (${body})`;
    const rc = lauxlib.luaL_dostring(L, to_luastring(code));
    if (rc !== 0) throw new Error("lua eval failed: " + lua.lua_tostring(L, -1));
    const res = lua.lua_toboolean(L, -1);
    lua.lua_pop(L, 1);
    return res;
  };

  const A1 = runExpr(`(function()
    local prof = OptionScalingResolver.readProfile(nil)
    if prof ~= nil then return false end
    local v = OptionScalingResolver.resolve({ dial = "worldEvents", base = 1.0, neutral = 1.0 }, prof)
    if v ~= 1.0 then return false end
    local v2 = OptionScalingResolver.resolve({ dial = "worldEvents", base = 1.0, neutral = 1.0 }, {})
    return v2 == 1.0
  end)()`);
  A1 ? ok("resolver: absent spine resolves to declared neutral (1.0)") : fail("resolver: neutral contract broken");

  const A2 = runExpr(`(function()
    local R = OptionScalingResolver
    local decl = { dial = "worldEvents", base = 1.0, neutral = 1.0 }
    set({ worldEvents = 0.0 }, { worldEvents = true })
    local r0 = R.resolve(decl, R.readProfile(hub))
    set({ worldEvents = 1.0 }, { worldEvents = true })
    local r1 = R.resolve(decl, R.readProfile(hub))
    set({ worldEvents = 2.0 }, { worldEvents = true })
    local r2 = R.resolve(decl, R.readProfile(hub))
    return math.abs(r0 - 0.4) < 1e-9 and math.abs(r1 - 1.0) < 1e-9 and math.abs(r2 - 1.7) < 1e-9
  end)()`);
  A2 ? ok("resolver: worldEvents canonical curve anchors 0.4/1.0/1.7") : fail("resolver: worldEvents curve anchors wrong");

  const A3 = runExpr(`(function()
    local R = OptionScalingResolver
    set({ economy = 2.0 }, { economy = true })
    local v = R.resolve({ dial = "economy", base = 1.0, neutral = 1.0 }, R.readProfile(hub))
    return math.abs(v - 1.8) < 1e-9
  end)()`);
  A3 ? ok("resolver: economy canonical curve anchor 1.8 at punishing") : fail("resolver: economy curve anchor wrong");

  const A4 = runExpr(`(function()
    local R = OptionScalingResolver
    set({ worldEvents = 2.0 }, { worldEvents = false })
    local v = R.resolve({ dial = "worldEvents", base = 1.0, neutral = 1.0 }, R.readProfile(hub))
    return v == 1.0
  end)()`);
  A4 ? ok("resolver: switched-off dial resolves to neutral") : fail("resolver: switch-off not neutral");

  const A5 = runExpr(`(function()
    local R = OptionScalingResolver
    local decl = { dial = "worldEvents", base = 1.0, neutral = 1.0 }
    set({ worldEvents = 2.0 }, { worldEvents = true })
    local d = R.readProfile(hub)
    local factor = R.resolve(decl, d)
    local ef = math.max(1, math.min(10, math.floor(5 * factor)))
    local ei = math.max(1, math.min(5, math.floor(2 * factor)))
    if ef ~= 8 or ei ~= 3 then return false end
    local nf = math.max(1, math.min(10, math.floor(5 * 1.0)))
    local ni = math.max(1, math.min(5, math.floor(2 * 1.0)))
    return nf == 5 and ni == 2
  end)()`);
  A5 ? ok("wrapper math: punishing scales freq 5->8, intensity 2->3; neutral keeps 5/2") : fail("wrapper math wrong");
} catch (e) {
  fail("resolver bench failed: " + e.message);
}

// ---------------------------------------------------------------------------
// B. Structural assertions over the real source
// ---------------------------------------------------------------------------
const src = (rel) => readFileSync(join(ROOT, rel), "utf8");
const parse = (rel) => luaparse.parse(src(rel), { luaVersion: "5.1", comments: false, locations: true });

const CUT = [
  "time_acceleration", "time_slowdown", "bonus_xp", "malus_xp", "money_bonus",
  "money_malus", "vehicle_fuel_bonus", "vehicle_fuel_penalty",
  "vehicle_free_upgrade", "vehicle_cleaning_bonus", "vehicle_steering_pull",
  "vehicle_slippery_roads", "fuel_discount",
  // EC-6, Arissani's 2026-09-16 rulings
  "seed_discount", "fertilizer_discount", "equipment_discount", "tax_refund",
];
const TOGGLE = [
  "vehicle_speed_boost", "vehicle_engine_trouble",
  "equipment_durability_boost", "equipment_durability_drop",
];

// Run the five event modules in a fresh Lua VM with a recording registerEvent and
// return the stored definitions: [{ name, category, gate }].
async function storedDefinitions() {
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } = await import("fengari");
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
      throw new Error(name + ": " + to_jsstring(lua.lua_tostring(L, -1)));
    }
  };
  run(`Logging = { info = function() end, warning = function() end }
    g_RandomWorldEvents = { EVENTS = {}, EVENT_STATE = { eventData = {} } }
    function g_RandomWorldEvents:registerEvent(e) self.EVENTS[e.name] = e end`, "stubs");
  for (const [rel] of modules) run(src(rel), rel);
  run(`local out = {}
    for name, e in pairs(g_RandomWorldEvents.EVENTS) do
      out[#out + 1] = name .. "=" .. tostring(e.category) .. "=" .. tostring(e.gate)
    end
    table.sort(out)
    STORED = table.concat(out, ";")`, "collect");
  lua.lua_getglobal(L, to_luastring("STORED"));
  const raw = to_jsstring(lua.lua_tostring(L, -1));
  return raw.split(";").filter(Boolean).map((row) => {
    const [name, category, gate] = row.split("=");
    return { name, category, gate: gate === "nil" ? undefined : gate };
  });
}

const modules = [
  ["utils/specialEvents.lua", "special"],
  ["utils/economicEvents.lua", "economic"],
  ["utils/fieldEvents.lua", "field"],
  ["utils/animalEvents.lua", "wildlife"],
  ["utils/vehicleEvents.lua", "vehicle"],
];

const stored = await storedDefinitions();
const allNames = stored.map((e) => e.name);
const stillPresent = CUT.filter((c) => allNames.includes(c));
stillPresent.length === 0
  ? ok(`structural: none of the ${CUT.length} cut events remain registered`)
  : fail(`structural: cut events still registered: ${stillPresent.join(", ")}`);

const ungated = TOGGLE.filter((t) => (stored.find((e) => e.name === t) || {}).gate !== "arcadePhysics");
ungated.length === 0
  ? ok("structural: all 4 arcade-physics events STORE gate=arcadePhysics")
  : fail(`structural: toggle events missing a stored gate: ${ungated.join(", ")}`);
const extraGated = stored.filter((e) => e.gate === "arcadePhysics" && !TOGGLE.includes(e.name)).map((e) => e.name);
extraGated.length === 0
  ? ok("structural: no other event stores the arcade gate")
  : fail(`structural: unexpected arcade gate on: ${extraGated.join(", ")}`);

const fieldSrc = src("utils/fieldEvents.lua");
const animalSrc = src("utils/animalEvents.lua");
(!/fieldTickHandler/.test(fieldSrc) && !/registerTickHandler\("fieldEvents"/.test(fieldSrc))
  ? ok("structural: field money-trickle handler removed")
  : fail("structural: field tick handler still present");
(!/animalTickHandler/.test(animalSrc) && !/registerTickHandler\("animalEvents"/.test(animalSrc))
  ? ok("structural: animal money-trickle handler removed")
  : fail("structural: animal tick handler still present");

const specialSrc = src("utils/specialEvents.lua");
const economicSrc = src("utils/economicEvents.lua");
(!/registerTickHandler/.test(specialSrc) && !/moneyBonus/.test(specialSrc))
  ? ok("structural: festival money trickle removed (EC-6)")
  : fail("structural: special tick handler or festival moneyBonus still present");
(!/economicTickHandler/.test(economicSrc) && !/registerTickHandler/.test(economicSrc))
  ? ok("structural: economic money trickle removed (EC-6)")
  : fail("structural: economic tick handler still present");
const moneyWriters = modules.filter(([rel]) => /addMoney/.test(src(rel))).map(([rel]) => rel);
moneyWriters.length === 0
  ? ok("structural: no event module writes money (statement lines only, EC-6)")
  : fail(`structural: addMoney still called in: ${moneyWriters.join(", ")}`);
!/repPoints/.test(specialSrc)
  ? ok("structural: reputation (repPoints) write removed")
  : fail("structural: repPoints still written in specialEvents");

const hooks = src("utils/EffectHooks.lua");
!/EconomyManager\.getPricePerLiter\s*=/.test(hooks)
  ? ok("structural: the EconomyManager.getPricePerLiter patch is gone (EC-6)")
  : fail("structural: EffectHooks still patches EconomyManager.getPricePerLiter");
(/allowsArcadePhysics/.test(hooks) && !/g_localPlayer/.test(hooks))
  ? ok("structural: damage patch gated behind arcadePhysics, no player-vehicle rule (Design d3c0626)")
  : fail("structural: damage patch not gated, or the retired player-vehicle rule is back");

const physics = src("utils/VehiclePhysics.lua");
const governorCalls = (physics.match(/getTerrainScales\(vehicle\)/g) || []).length - 1;
(/if controlled and governorAllowed\(\) then/.test(physics)
  && /if governorAllowed\(\) and isPlayerVehicle\(vehicle\) then/.test(physics)
  && /governorAllowed\(\) and isPlayerVehicle\(self\)/.test(physics)
  && governorCalls === 2)
  ? ok("structural: the terrain governor applies only with Arcade Physics (both call sites + relevance, EC-6)")
  : fail(`structural: terrain governor not behind allowsArcadePhysics (call sites ${governorCalls})`);
(!/eventSteerPull|axisSteer|onPreUpdate/.test(physics))
  ? ok("structural: steering-pull machinery removed (EC-6)")
  : fail("structural: steering pull still present in VehiclePhysics");
const hud = src("gui/RWEEventHUD.lua");
(/eventTitle\(eventId\)/.test(hud) && !/eventId:gsub/.test(hud))
  ? ok("structural: HUD shows the translated title, never a name built from the id (EC-6)")
  : fail("structural: HUD still builds the event name from the raw id");

const core = src("RandomWorldEvents.lua");
const need = ["getIntensity", "isEventActive", "getProgress", "getRemainingTime", "getDifficulty", "allowsArcadePhysics", "getEffectiveFrequency", "getBaseIntensity", 'event.gate == "arcadePhysics"'];
const missing = need.filter((n) => !core.includes(n));
missing.length === 0
  ? ok("structural: core read-surface + difficulty + toggle gate present")
  : fail(`structural: core missing: ${missing.join(", ")}`);

const hubBridge = src("integrations/RWESettingsHubBridge.lua");
const esc = src("gui/RWESettingsIntegration.lua");
const panel = src("gui/RWESettingsPanel.lua");
(hubBridge.includes("arcadePhysics") && esc.includes("onRWEArcadePhysicsChanged") && panel.includes("Arcade Physics"))
  ? ok("structural: arcadePhysics exposed in SettingsHub, ESC and quick panel")
  : fail("structural: arcadePhysics not exposed in all settings surfaces");

const resolverSrc = src("utils/OptionScalingResolver.lua");
(resolverSrc.includes("OptionScalingResolver.CONTRACT_VERSION = 1") && resolverSrc.includes('"worldEvents"'))
  ? ok("structural: vendored OptionScalingResolver present (contract v1)")
  : fail("structural: vendored resolver missing or contract drift");

const counts = {};
for (const e of stored) counts[e.category] = (counts[e.category] || 0) + 1;
const total = stored.length;
if (counts.economic === 10 && counts.field === 10 && counts.vehicle === 4 && counts.wildlife === 8 && counts.special === 4 && total === 36) {
  ok(`structural: stored event catalog = 36 (economic ${counts.economic}, field ${counts.field}, vehicle ${counts.vehicle}, wildlife ${counts.wildlife}, special ${counts.special})`);
} else {
  fail(`structural: unexpected catalog ${JSON.stringify(counts)} (total ${total})`);
}

console.log(`\n[bench] passed: ${pass}, failed: ${failCount}`);
if (failCount > 0) {
  console.error("[bench] FAILED");
  process.exit(1);
}
console.log("[bench] PASSED");
