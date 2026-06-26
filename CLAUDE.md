# FS25_RandomWorldEvents - Claude Code Project Instructions

## !! MANDATORY: Before Writing ANY FS25 API Code !!
Before implementing any FS25 Lua API call, class usage, or game system interaction,
ALWAYS check the following local reference folders first. These contain CORRECT,
PROVEN API documentation - they are the ground truth. Do NOT rely on training data
for FS25 API specifics; it may be outdated, wrong, or hallucinated.

### Reference Locations
| Reference | Path | Use for |
|-----------|------|---------|
| FS25-Community-LUADOC | `C:\Users\tison\Desktop\FS25 MODS\FS25-Community-LUADOC` | Class APIs, method signatures, function arguments, return values, inheritance chains |
| FS25-lua-scripting | `C:\Users\tison\Desktop\FS25 MODS\FS25-lua-scripting` | Scripting patterns, working examples, proven integration approaches |

### When to Check (mandatory, not optional)
- Any `g_currentMission.*` call
- Any `g_gui.*` / dialog / GUI system usage
- Any hotspot / map icon API (`MapHotspot`, `PlaceableHotspot`, `IngameMap`, etc.)
- Any `addMapHotspot` / `removeMapHotspot` usage
- Any `Class()` / `isa()` / inheritance pattern
- Any `g_i3DManager` / i3d loading
- Any `g_overlayManager` / `Overlay.new` usage
- Any `g_inputBinding` / action event registration
- Any save/load XML API (`xmlFile:setInt`, `xmlFile:getValue`, etc.)
- Any `MessageType` / `g_messageCenter` subscription
- Any placeable specialization or `g_placeableSystem` usage
- Any finance / economy API call
- Any `Utils.*` helper you are not 100% certain about
- Any new FS25 system not previously used in this project

### How to Check
1. Search the LUADOC for the class or function name
2. Read the full method signature including ALL arguments and return values
3. Check inheritance - many FS25 classes require parent constructor calls
4. Look for working examples in FS25-lua-scripting before writing new code
5. If the API is NOT in either reference, state that clearly rather than guessing

---

## Project Overview

**FS25_RandomWorldEvents** is a Farming Simulator 25 mod (v2.0.0.0) that introduces a
random-event system and a real vehicle-physics layer to the base game. Events fire on a
probabilistic timer during gameplay and can affect the economy, vehicles, fields, animals,
and special game-state variables. All settings persist per-savegame via an XML file.

Author: TisonK | License: All rights reserved.

### Vehicle physics

The vehicle-physics layer (`utils/VehiclePhysics.lua`, the `RWEVehiclePhysics`
specialization) only touches fields the engine actually reads. The earlier code wrote to
non-existent fields (`wheel.physics.frictionScale`, `wheel.suspension.springForce`,
`motor.maxPower`, `vehicle.maxSpeed`) and did nothing - see `VEHICLE_PHYSICS_FINDINGS.txt`
in the repo root for the full wrong-vs-correct writeup, and `DEVELOPMENT.md` §5 for the
architecture.

> **Credit:** the steering technique (writing `spec_drivable.lastInputValues.axisSteer`
> each frame) and the `TypeManager.finalizeTypes` specialization-injection approach are
> adapted from **"RealPhysics Steering" by Tubez47**, recorded inline in the source header.
> Keep that credit intact in any future edits to the physics layer.

---

## Repository Layout

```
FS25_RandomWorldEvents/
├── RandomWorldEvents.lua          # Core manager + FS25 lifecycle hooks
├── modDesc.xml                    # Mod metadata, l10n strings, source file list
├── guiProfiles.xml                # GUI style profiles
├── icon.dds                       # Mod icon
├── icons/
│   ├── events.dds                 # Tab icon - Events page
│   └── settings.dds               # Tab icon - Settings page
├── gui/
│   ├── RandomWorldEventsScreen.lua  # TabbedMenuWithDetails screen wrapper
│   ├── RandomWorldEventsFrame.lua   # Events/settings frame (tab 1)
│   └── RandomWorldDebugFrame.lua    # Physics/debug frame (tab 2)
├── xml/
│   ├── RandomWorldEventsScreen.xml
│   ├── RandomWorldEventsFrame.xml
│   └── RandomWorldDebugFrame.xml
└── utils/
    ├── economicEvents.lua           # 15 economic events
    ├── vehicleEvents.lua            # 10 vehicle events (speed/engine/steering via RWEVehiclePhysics)
    ├── fieldEvents.lua              # 10 field events
    ├── animalEvents.lua             # BUG: currently duplicates specialEvents.lua
    ├── specialEvents.lua            # 10 special events (time, XP, money, trade)
    ├── VehiclePhysics.lua           # RWEVehiclePhysics specialization - real vehicle physics
    └── PhysicsUtils.lua             # Debug telemetry only (honest speed/surface readout)
```

---

## Architecture

### Singleton Pattern
There is exactly one runtime instance of `RandomWorldEvents`, exposed globally as
`g_RandomWorldEvents`. It is created inside `Mission00.load` and torn down in
`FSBaseMission.delete`.

### Lifecycle Hooks
```
Mission00.load        → creates g_RandomWorldEvents, loads modules + GUI
FSBaseMission.update  → drives the event timer and active-event tick
FSBaseMission.delete  → saves settings, clears g_RandomWorldEvents
FSBaseMission.keyEvent → F3 (settings screen, stub), F9 (force trigger)
```

### Deferred Module Registration
Event modules load before `g_RandomWorldEvents` is guaranteed to exist (FS25 loads
all `extraSourceFiles` in order). Each module checks for `g_RandomWorldEvents` at
load time; if absent it pushes a closure into `RandomWorldEvents.pendingRegistrations`.
The core then drains that list inside `loadEventModules()` after the singleton is
ready.

### Settings Persistence
Settings are stored at:
```
<savegameDirectory>/<MOD_NAME>.xml
```
The `settingsManager` embedded in `RandomWorldEvents:new()` handles load/save via
FS25's `XMLFile` API. On first run (no file), defaults are deep-copied from
`manager.defaultConfig`.

### EVENT_STATE
`RandomWorldEvents.EVENT_STATE` is a **class-level table** (not per-instance). It
stores the active event ID, start time, duration, cooldown timestamp, and all
transient effect flags (e.g. `marketBonus`, `yieldBonus`, `vehicleSpeedBoost`).
Only one event can be active at a time.

---

## Known Bugs & Issues

| # | Location | Issue |
|---|----------|-------|
| 1 | `utils/animalEvents.lua` | File contains `specialEvents` code verbatim - animal/wildlife events are **not implemented**. The `wildlifeEvents` toggle controls nothing. |
| 2 | `modDesc.xml:90` | `<filename>` tag uses the attribute name `filename` twice: `<filename name="RandomWorldEventsScreen" filename="gui/..."/>`. The second attribute should be `filename` but the first should likely be `name`. Some parsers may reject this. |
| 3 | `modDesc.xml` | Version field says `1.0.0.0` but Lua headers say `2.0.0.0`. |
| 4 | `economicEvents.lua:242` + `vehicleEvents.lua:420` | Both modules monkey-patch `g_RandomWorldEvents:update` via `originalUpdate` chaining. If both run, the second module overwrites the first module's override, **silently dropping** the first module's per-tick effects. This pattern is fragile. |
| 5 | `RandomWorldEventsScreen.lua:45-50` | Tab icons are swapped: the Events frame gets `settings.dds` and the Debug frame gets `events.dds`. |
| 6 | `RandomWorldEvents.lua:664-673` | `keyEvent` has a redundant inner `if rweManager then` check (the outer guard already confirms it). Minor but misleading. |
| 7 | `PhysicsUtils.lua:140-158` | `PhysicsUtils` is self-clobbered: `PhysicsUtils = PhysicsUtils:new()`. If the pending-registration path runs AND `loadEventModules` also instantiates it, there is a double-init. Both produce the same result but log confusingly. |
| 8 | `fieldEvents.lua:99-104` | `canTrigger` checks `fieldController.fields` exists and `#fields > 0`. FS25 uses a `g_fieldManager` API, not `g_currentMission.fieldController` - this guard may never pass, causing field events to silently not fire on many maps. |

---

## Coding Conventions

- **Logging prefix**: always `[RWE]` for the core, `[EconomicEvents]`, `[VehicleEvents]`,
  etc. for modules. Use `Logging.info`, `Logging.warning`, `Logging.error`.
- **Guard patterns**: every module function that touches `g_RandomWorldEvents` or
  `g_currentMission` begins with a nil-check.
- **Event registration**: call `g_RandomWorldEvents:registerEvent({ ... })`. See
  `DEVELOPMENT.md` for the full event schema.
- **No globals**: use `local` for all module-internal tables. Only `g_RandomWorldEvents`
  is intentionally global.
- **FS25 API**: prefer `vehicle:method()` over direct field access. Do not assume
  `getFillUnitInformation`, `getMotor`, `addDamageAmount` exist - guard with `if vehicle.method`.
- **Settings**: never write settings directly to disk except via `g_RandomWorldEvents:saveSettings()`.

---

## Build & Deploy

```bash
# From Mods Base Directory
bash build.sh --deploy
```

Deploys zip to:
```
C:\Users\tison\Documents\My Games\FarmingSimulator2025\mods
```

After deploying, tail the game log for the `[RandomWorldEvents]` / `[RWE]` prefix:
```
C:\Users\tison\Documents\My Games\FarmingSimulator2025\log.txt
```

---

## Console Commands (in-game)

| Command | Description |
|---------|-------------|
| `rwe` | Print help |
| `rweStatus` | Show enabled state, active event, cooldown |
| `rweTest` | Force-trigger a random event |
| `rweEnd` | Forcibly end the active event |
| `rweDebug on\|off` | Toggle debug mode |
| `rweList [category]` | List registered events |

Hotkeys: **F9** - force trigger event.
