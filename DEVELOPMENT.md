# FS25_RandomWorldEvents - Developer Reference

## Table of Contents

1. [Project Summary](#1-project-summary)
2. [Runtime Lifecycle](#2-runtime-lifecycle)
3. [Event System](#3-event-system)
4. [Settings System](#4-settings-system)
5. [Physics System](#5-physics-system)
6. [GUI System](#6-gui-system)
7. [Module Registration Protocol](#7-module-registration-protocol)
8. [How to Add a New Event](#8-how-to-add-a-new-event)
9. [How to Add a New Event Category](#9-how-to-add-a-new-event-category)
10. [Known Bugs & Limitations](#10-known-bugs--limitations)
11. [Multiplayer Considerations](#11-multiplayer-considerations)
12. [Build & Deploy](#12-build--deploy)

---

## 1. Project Summary

FS25_RandomWorldEvents adds:
- A **probabilistic event engine** that fires timed world events (economic, vehicle,
  field, special) with configurable frequency, intensity, and cooldown.
- A **real vehicle-physics layer** (`RWEVehiclePhysics`, a vehicle specialization) that
  drives speed, top speed, acceleration and steering through the engine's own fields,
  plus a loose-ground traction governor. See §5.
- An **in-game settings screen** (tabbed GUI) for toggling categories and tuning all
  parameters without restarting the game.
- **Per-savegame persistence** so each farm's settings survive restarts.

Mod version: **2.0.0.0** (note: `modDesc.xml` incorrectly shows `1.0.0.0`).

---

## 2. Runtime Lifecycle

```
FS25 engine boots
│
├─ Loads all extraSourceFiles in order (modDesc.xml):
│   RandomWorldEvents.lua         ← defines class + hooks lifecycle
│   gui/RandomWorldEventsScreen.lua
│   gui/RandomWorldEventsFrame.lua
│   gui/RandomWorldDebugFrame.lua
│   utils/economicEvents.lua      ← queues pendingRegistrations
│   utils/vehicleEvents.lua       ← queues pendingRegistrations
│   utils/fieldEvents.lua         ← queues pendingRegistrations
│   utils/animalEvents.lua        ← queues pendingRegistrations (see Bug #1)
│   utils/specialEvents.lua       ← queues pendingRegistrations
│   utils/VehiclePhysics.lua      ← installs TypeManager.finalizeTypes hook on load
│   utils/PhysicsUtils.lua        ← debug telemetry only (queues pendingRegistrations)
│
├─ Mission00.load fires
│   ├─ RandomWorldEvents:new(mission)
│   │   ├─ createSettingsManager()
│   │   ├─ loadSettings()           ← reads savegame XML
│   │   └─ registerConsoleCommands()
│   ├─ g_RandomWorldEvents = rweManager  ← global exposed HERE
│   ├─ loadEventModules()           ← drains pendingRegistrations
│   ├─ loadGUI()                    ← sources + registers screen/frame classes
│   └─ isInitialized = true
│
├─ FSBaseMission.update fires every frame
│   └─ rweManager:update(dt)
│       ├─ Event timer check → triggerRandomEvent() if chance fires
│       ├─ Active event tick → applyActiveEventEffects()
│       ├─ Event expiry check → event.onEnd()
│       └─ (optional) debug readout → PhysicsUtils:showPhysicsInfo(vehicle)
│         Real physics runs per-vehicle in the RWEVehiclePhysics spec, not here.
│
└─ FSBaseMission.delete fires on exit/unload
    ├─ saveSettings()
    └─ g_RandomWorldEvents = nil
```

---

## 3. Event System

### Event Object Schema

Every registered event is a Lua table with the following fields:

```lua
{
    name         = "my_event_name",   -- string: unique key in EVENTS table
    category     = "economic",        -- string: must match a <category>Events key in settings
    weight       = 1,                 -- number: relative selection weight (currently unused; all events have equal chance)
    duration     = { min = 15,        -- table: duration range in in-game minutes
                     max = 60 },      --   converted to ms: value * 60000
    minIntensity = 1,                 -- number 1-5: minimum intensity level required
    canTrigger   = function()         -- function() → bool: runtime eligibility check
        return g_currentMission ~= nil
    end,
    onStart      = function(intensity) -- function(intensity) → string|nil
        -- Apply event effects here.
        -- Return a notification string, or nil to suppress.
        return "Event started!"
    end,
    onEnd        = function()          -- function() → string|nil
        -- Clean up all effects applied by onStart.
        -- Return a notification string, or nil to suppress.
        return "Event ended."
    end
}
```

**Important**: `onEnd` is shared across all events registered in a single module. It
must clear every possible `EVENT_STATE` key that any event in that module could set.
Failing to do so causes stale state from a previous event to persist.

### EVENT_STATE Keys (current)

The `g_RandomWorldEvents.EVENT_STATE` table holds all transient effect data:

| Key | Set by | Meaning |
|-----|--------|---------|
| `activeEvent` | core | Name of the currently running event, or `nil` |
| `eventStartTime` | core | `g_currentMission.time` when event started |
| `eventDuration` | core | Duration in ms |
| `cooldownUntil` | core | `g_currentMission.time` after which next event may fire |
| `marketBonus` | economicEvents | Sell price multiplier bonus (fraction, e.g. `0.15`) |
| `marketMalus` | economicEvents | Sell price multiplier penalty |
| `seedDiscount` | economicEvents | Seed cost reduction fraction |
| `fertilizerDiscount` | economicEvents | Fertilizer cost reduction fraction |
| `fuelDiscount` | economicEvents | Fuel cost reduction fraction |
| `equipmentDiscount` | economicEvents | Equipment cost reduction fraction |
| `priceFixing` | economicEvents | Fixed sell price bonus |
| `priceFixingDuration` | economicEvents | Minutes remaining on price fixing |
| `exportBonus` | economicEvents | Export price bonus fraction |
| `exportDuration` | economicEvents | Minutes remaining on export bonus |
| `economicCrisis` | economicEvents | Table `{marketMalus, loanPenalty, duration}` |
| `yieldBonus` | fieldEvents | Crop yield multiplier bonus |
| `yieldMalus` | fieldEvents | Crop yield multiplier penalty |
| `fertilizerBonus` | fieldEvents | Fertilizer effectiveness flag |
| `fertilizerMalus` | fieldEvents | Fertilizer effectiveness flag |
| `seedBonus` | fieldEvents | Seed growth speed flag |
| `seedMalus` | fieldEvents | Seed growth speed flag |
| `harvestBonus` | fieldEvents | Harvest amount flag |
| `harvestMalus` | fieldEvents | Harvest amount flag |
| `fieldSaleBonus` | fieldEvents | Field crop sale price bonus fraction |
| `fieldSaleMalus` | fieldEvents | Field crop sale price penalty fraction |
| `vehiclePhysics` | vehicleEvents | `{vehicle}` - vehicle with active RWEVehiclePhysics modifiers (speed/engine/steering); restored via `RWEVehiclePhysics.clearEventMods` |
| `vehicleAccident` | vehicleEvents | `{vehicle, damagePercent}` table |
| `vehicleUpgrade` | vehicleEvents | `{vehicle}` table (color tint state) |
| `originalTimeScale` | specialEvents | Saved `missionInfo.timeScale` before time warp |
| `xpBonus` | specialEvents | XP gain multiplier bonus |
| `xpMalus` | specialEvents | XP gain multiplier penalty |
| `moneyBonus` | specialEvents | Money gain multiplier bonus |
| `moneyMalus` | specialEvents | Money gain multiplier penalty |
| `durabilityBoost` | specialEvents | Equipment durability flag |
| `durabilityMalus` | specialEvents | Equipment durability flag |
| `tradeBonus` | specialEvents | Trade price flag |

> **Note:** Most `EVENT_STATE` flags (e.g. `yieldBonus`, `xpBonus`) are set but never
> actually read by any game hook. They function as observable state indicators only -
> the actual gameplay integration (hooking FS25 crop yield or XP grant callbacks) is
> not yet implemented.

### Trigger Logic

Each frame in `update(dt)`:

1. If `events.enabled` and `g_currentMission.time > cooldownUntil`:
   - Roll `math.random() <= frequency * 0.001`. At frequency=5 this is a 0.5% chance
     **per game tick** (typically ~60 Hz), making events fire very frequently.
   - If roll passes: call `triggerRandomEvent()`, then set cooldown to
     `cooldown * 60000 * ((11 - frequency) / 10)` ms.
2. If an event is active: call `applyActiveEventEffects()` (currently a no-op stub).
3. Check if `eventStartTime + eventDuration` has elapsed → call `event.onEnd()`.

---

## 4. Settings System

Settings are split into three sub-tables on the `RandomWorldEvents` instance:

### `self.events`

| Key | Type | Default | Range | Description |
|-----|------|---------|-------|-------------|
| `enabled` | bool | `true` | - | Master on/off switch |
| `frequency` | int | `5` | 1-10 | Trigger chance multiplier |
| `intensity` | int | `2` | 1-5 | Event magnitude |
| `showNotifications` | bool | `true` | - | In-game HUD notices |
| `showWarnings` | bool | `true` | - | Warning notifications |
| `cooldown` | int | `30` | 1-240 | Minutes between events |
| `weatherEvents` | bool | `false` | - | Weather category (stub) |
| `economicEvents` | bool | `true` | - | Economic category |
| `vehicleEvents` | bool | `true` | - | Vehicle category |
| `fieldEvents` | bool | `true` | - | Field category |
| `wildlifeEvents` | bool | `true` | - | Wildlife/animal category |
| `specialEvents` | bool | `true` | - | Special category |
| `debugLevel` | int | `1` | - | Verbosity (unused in core) |

### `self.physics`

| Key | Type | Default | Range | Description |
|-----|------|---------|-------|-------------|
| `enabled` | bool | `true` | - | Physics layer master switch (traction governor) |
| `wheelGripMultiplier` | float | `1.0` | 0.5-2.0 | Loose-ground traction: higher = more grip, less slowdown |
| `showPhysicsInfo` | bool | `false` | - | Log the honest physics readout each frame |
| `debugMode` | bool | `false` | - | Extra verbose physics logging |
| `articulationDamping` | float | `0.5` | - | **Legacy/unused** - kept only so old save XML still loads |
| `comStrength` | float | `1.0` | - | **Legacy/unused** - kept only so old save XML still loads |
| `suspensionStiffness` | float | `1.0` | - | **Legacy/unused** - no script lever exists for it in FS25 |

### `self.debug`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `false` | Debug mode flag |
| `debugLevel` | int | `1` | Verbosity level |
| `showDebugInfo` | bool | `false` | Show HUD debug info |

### Persistence File Location

```
<g_currentMission.missionInfo.savegameDirectory>/FS25_RandomWorldEvents.xml
```

Root XML tag: `RandomWorldEvents`. Sub-paths mirror the table hierarchy
(e.g. `RandomWorldEvents.events.frequency`).

---

## 5. Physics System

The physics layer was rebuilt to use only fields the GIANTS engine actually reads. The
old version (`PhysicsUtils:applyAdvancedPhysics` + `RandomWorldEvents:updatePhysics`)
wrote to `wheel.physics.frictionScale`, `wheel.suspension.springForce` and
`wheel.contact.groundTypeName` - **none of which exist** - so it never affected the
game. That dead code is gone.

### `RWEVehiclePhysics` (`utils/VehiclePhysics.lua`)

A **vehicle specialization** injected into every `drivable` + `motorized` + `wheels`
type via a `TypeManager.finalizeTypes` hook (matched against `g_vehicleTypeManager`).
It owns all real vehicle-physics changes and restores them cleanly.

Real, engine-respected levers:

| Lever | Field / call | Used for |
|-------|--------------|----------|
| Speed cap | `vehicle.speedLimit` (km/h, read by `Vehicle:getRawSpeedLimit`) | speed boost / slow-down |
| Top speed | `motor.maxForwardSpeed` (restore from `motor.maxForwardSpeedOrigin`) | true turbo above gear cap |
| Acceleration | `motor:setAccelerationLimit()` | engine sluggishness / limp home |
| Steering | `spec_drivable.lastInputValues.axisSteer` (per frame) | steering pull |
| Surface (read) | `wheel.physics:getSurfaceSoundAttributes()` | traction governor |

Per-vehicle state lives on `vehicle._rwePhysics` (event scales + captured baselines), so
the event API can reach it even on a vehicle that did not receive the spec. Baselines are
captured lazily on first update. Enforcement runs in `onUpdate`/`onPreUpdate` on the
server, and only writes when a value actually deviates, so untouched parked machines are
never modified. Restore happens on `clearEventMods`, `onLeaveVehicle` and `onDelete`.

### Public API (used by events / `RWEVehicleAPI`)

```lua
RWEVehiclePhysics.applyEventMods(vehicle, {
    speedScale = 1.4,   -- km/h cap multiplier
    topScale   = 1.4,   -- physical top-speed multiplier
    accelScale = 0.5,   -- acceleration multiplier (engine feel)
    steerPull  = 0.10,  -- -1..1 continuous steering bias
})
RWEVehiclePhysics.clearEventMods(vehicle)  -- restore baselines
```

### Traction governor

When `physics.enabled` is on, the spec eases speed/acceleration for the *controlled*
vehicle on loose ground (field, mud, snow), scaled by the `wheelGripMultiplier` setting.
Surfaces come from the real `getSurfaceSoundAttributes()` data, never a faked field.

### `PhysicsUtils` (`utils/PhysicsUtils.lua`)

Reduced to honest debug telemetry. `showPhysicsInfo(vehicle)` logs the real speed
(`getLastSpeed()`, km/h - the old `lastSpeedReal * 3.6` was 1000x too small), the surface
under the wheels, and any active modifiers.

### Credit

> The steering technique - writing into `spec_drivable.lastInputValues.axisSteer` each
> frame so the game steers as if the player were holding the wheel - and the approach of
> injecting a specialization into existing vehicle types via `TypeManager.finalizeTypes`
> are **adapted from "RealPhysics Steering" by Tubez47**. The source header of
> `utils/VehiclePhysics.lua` records this inline. Thank you, Tubez47.

---

## 6. GUI System

The GUI is a standard FS25 **TabbedMenuWithDetails** with two frames:

| Tab | Frame Class | XML | Controls |
|-----|-------------|-----|----------|
| Events/Settings | `RandomWorldEventsFrame` | `xml/RandomWorldEventsFrame.xml` | Toggle switches + text inputs for all event settings |
| Physics/Debug | `RandomWorldEventsDebugFrame` | `xml/RandomWorldDebugFrame.xml` | Toggle switches + text inputs for all physics settings |

### Opening the GUI

The settings screen is not yet wired to a menu button or keyboard shortcut -
`F3` is stubbed in the `keyEvent` handler but calls no screen-open logic.
To open it programmatically:

```lua
g_gui:showGui("RandomWorldEventsScreen")
```

### Control Binding Pattern

Each control's `id` in the XML maps directly to a key in `g_RandomWorldEvents.events`
or `g_RandomWorldEvents.physics`. The frame handlers use `element.id` to write back
to the correct sub-table:

```lua
-- In RandomWorldEventsFrame:
g_RandomWorldEvents.events[element.id] = value

-- In RandomWorldEventsDebugFrame:
g_RandomWorldEvents.physics[element.id] = value
```

This means XML element IDs **must** exactly match the settings key names.

### Trigger Event Button

`RandomWorldEventsFrame` includes a `triggerEventButtonWrapper` control. Clicking it
calls `g_RandomWorldEvents:triggerRandomEvent()` directly - useful for testing without
console commands.

---

## 7. Module Registration Protocol

Each event module follows the same pattern to safely register with the core:

```lua
local function registerXxxEvents()
    if not g_RandomWorldEvents or not g_RandomWorldEvents.registerEvent then
        Logging.warning("[XxxEvents] g_RandomWorldEvents not available yet")
        return false
    end
    -- call g_RandomWorldEvents:registerEvent({...}) for each event
    return true
end

-- At module load time:
if g_RandomWorldEvents and g_RandomWorldEvents.registerEvent then
    registerXxxEvents()
else
    -- Defer to after core is initialized
    if not RandomWorldEvents then RandomWorldEvents = {} end
    if not RandomWorldEvents.pendingRegistrations then
        RandomWorldEvents.pendingRegistrations = {}
    end
    table.insert(RandomWorldEvents.pendingRegistrations, function()
        registerXxxEvents()
    end)
end
```

The core drains `pendingRegistrations` in `loadEventModules()` after the singleton
is assigned to `g_RandomWorldEvents`.

---

## 8. How to Add a New Event

1. Open the appropriate utils file (e.g. `utils/economicEvents.lua`) or create a
   new module file (see §9).
2. Add an entry to the module's `eventList`:

```lua
{
    name = "crop_insurance_payout",    -- must be globally unique
    minI = 2,                          -- minimum intensity (1-5)
    func = function(intensity)
        local amount = 1000 * intensity
        if g_currentMission and g_currentMission.addMoney then
            g_currentMission:addMoney(
                amount,
                economicEvents.getFarmId(),
                MoneyType.OTHER,
                true
            )
        end
        return string.format("Crop insurance payout! +€%d", amount)
    end
}
```

3. The `registerXxxEvents()` loop will pick it up automatically on the next load.
   `onEnd` for the whole module clears all `EVENT_STATE` keys used by any event in
   the module - add any new keys your event sets to that cleanup block.
4. If the event sets a state flag that needs per-tick logic, implement it in the
   module's `update` override (see §10, Bug 4 for the chaining fragility warning
   before doing this).

---

## 9. How to Add a New Event Category

1. Create `utils/myNewEvents.lua` following the registration protocol in §7.
2. Use a unique `category` string in every event (e.g. `"community"`).
3. Add `self.events.communityEvents = true` to the default config in
   `RandomWorldEvents:createSettingsManager()` (both the `defaultConfig` block and the
   load/save XML paths).
4. Add the matching toggle to `gui/RandomWorldEventsFrame.lua` CONTROLS list and
   implement the GUI checkbox binding.
5. Add the XML element to `xml/RandomWorldEventsFrame.xml`.
6. Register the file in `modDesc.xml` under `<extraSourceFiles>`.

---

## 10. Known Bugs & Limitations

### Bug 1 - `animalEvents.lua` contains `specialEvents` code
`utils/animalEvents.lua` is a verbatim copy of `utils/specialEvents.lua`. This means:
- Animal/wildlife events are **not implemented**.
- `specialEvents` are double-registered (once from each file), creating duplicate event
  names in `g_RandomWorldEvents.EVENTS`. The second registration silently overwrites
  the first (Lua table key collision).
- The `wildlifeEvents` toggle in settings controls nothing.
- **Fix**: Write actual animal events in `animalEvents.lua` using the `"wildlife"`
  category (or `"animal"` - then update `canTrigger` to check for animal husbandry
  structures and update the setting key to `animalEvents` for consistency).

### Bug 2 - `modDesc.xml` duplicate attribute on `<filename>` tag
```xml
<filename name="RandomWorldEventsScreen" filename="gui/RandomWorldEventsScreen.xml"/>
```
The `name` attribute is used twice as `name` and `filename`. Depending on the FS25
XML parser this may load incorrectly or be ignored.
- **Fix**: Verify the correct attribute names from the FS25 SDK and correct the tag.

### Bug 3 - `modDesc.xml` version mismatch
The `<version>` element says `1.0.0.0`; all Lua headers say `2.0.0.0`.
- **Fix**: Synchronize to `2.0.0.0`.

### Bug 4 - Fragile `originalUpdate` chaining in event modules
`economicEvents.lua` and `vehicleEvents.lua` both inject per-tick logic by
overwriting `g_RandomWorldEvents:update` and saving the previous function as
`originalUpdate`. If both modules run this at load time (which they do not - the
guard `if g_RandomWorldEvents` prevents it since `g_RandomWorldEvents` does not yet
exist at load time), the second would lose the first module's chain. Currently both
guards evaluate false, so neither per-tick function runs at all.
- **Fix**: Implement `applyActiveEventEffects()` in the core and dispatch per-tick
  work there, or use a registered listener list instead of monkey-patching `:update`.

### Bug 5 - GUI tab icons swapped
In `RandomWorldEventsScreen:setupPages()`, the Events frame receives `settings.dds`
and the Debug/Physics frame receives `events.dds`.
- **Fix**: Swap the icon strings.

### Bug 6 - `fieldEvents` `canTrigger` may never pass
`g_currentMission.fieldController.fields` is not the canonical FS25 field API.
- **Fix**: Use `g_fieldManager` or simply `g_currentMission ~= nil` as the guard.

### Bug 7 - EVENT_STATE flags are never consumed
Most `EVENT_STATE` entries (`yieldBonus`, `xpBonus`, `marketBonus`, etc.) are set but
no game hooks read them to actually apply the effects. The events fire, the
notification shows, the flag is set, but gameplay is unchanged.
- **Fix**: Hook the relevant FS25 callbacks (sell point price calculation, crop yield
  calculation, XP award) to check and apply the flag.

### Bug 8 - Frequency chance is per-frame, not per-minute
With `frequency = 5`, the probability per frame is `0.5%`. At 60 Hz this is roughly
once every 3 seconds of real time (with a 30-minute cooldown). At `frequency = 10`
events fire almost every cooldown period. The UX label should clarify this is a
relative scale, not events-per-hour.

---

## 11. Multiplayer Considerations

`modDesc.xml` declares `multiplayer supported="true"`. However:
- `g_currentMission.addMoney` is client-authoritative on the calling client only;
  funds are not synchronized to other clients without a network event.
- Vehicle-physics changes (`RWEVehiclePhysics`) are enforced server-side and applied to
  the locally controlled vehicle, matching the pre-existing single-vehicle event scope;
  there is no dedicated network event syncing them to other clients yet.
- No `FSCareerMissionInfo` or network synchronization code exists in the mod.
- **Recommendation**: Set `multiplayer supported="false"` until network sync is
  implemented, or document clearly that effects are visual/local only in multiplayer.

---

## 12. Build & Deploy

```bash
# From C:\Users\tison\Desktop\FS25 MODS
bash build.sh --deploy
```

The deploy step zips the mod and copies it to:
```
C:\Users\tison\Documents\My Games\FarmingSimulator2025\mods
```

After deploy, watch the log for mod output:
```
C:\Users\tison\Documents\My Games\FarmingSimulator2025\log.txt
```

Key log lines to verify successful load:
```
[RandomWorldEvents] Core initialized successfully
[RWE] Processing N pending registrations
[EconomicEvents] Registered 15 economic events
[VehicleEvents] Registered 10 vehicle events
[FieldEvents] Registered 10 field events
[SpecialEvents] Registered 10 special events
[RWEVehiclePhysics] Type hook installed
[RWEVehiclePhysics] Registered for N vehicle types
[PhysicsUtils] Initialized (debug telemetry)
[RWE] GUI loading complete
[RandomWorldEvents] Initialized successfully with N events
```
