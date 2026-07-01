# 🌍 FS25 Random World Events

![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_RandomWorldEvents/total?style=for-the-badge)
![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_RandomWorldEvents?style=for-the-badge)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=for-the-badge)
<a href="https://paypal.me/TheCodingDad">
  <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate via PayPal" height="50">
</a>

Adds **45+ dynamic random events**, a real vehicle-physics layer, and a full in-game settings screen to **Farming Simulator 25** - making every playthrough feel different.

[Download Latest Release](https://github.com/TheCodingDad-TisonK/FS25_RandomWorldEvents/releases/latest) •
[Report Bug](https://github.com/TheCodingDad-TisonK/FS25_RandomWorldEvents/issues) •
[FS22 Version](https://github.com/TheCodingDad-TisonK/FS22_RandomWorldEvents)

---

> ℹ️ **Info**
>
> This mod is actively developed and supported on GitHub.
> Any uploads to other platforms not listed in the Availability section may not be authorized.

---

## 📌 Overview

**Random World Events** is the full FS25 rewrite of the FS22 original. It introduces a
probabilistic event engine that fires timed world events during gameplay, affecting your
economy, vehicles, fields, and more. Each event has configurable intensity, duration,
and cooldown. A real vehicle-physics layer drives the machine you're in through the
game's own engine fields - speed, acceleration, top end and steering - so vehicle
events are actually felt, not just shown as a popup.

All settings save per-savegame, so each farm can have its own configuration.

---

## ✨ Features

### 🌍 Random Event System
- **45+ unique events** across 4 active categories
- Configurable **frequency** (1-10), **intensity** (1-5), and **cooldown** (1-240 min)
- Events trigger automatically on a probability timer during gameplay
- Manual trigger via **F9** or the `rweTest` console command
- Per-category enable/disable toggles (economic, vehicle, field, special)
- In-game HUD notifications and warnings when events start and end
- Single active event at a time - a cooldown prevents event spam

### 💰 Economic Events (15 events)
Government subsidies, market booms and crashes, tax refunds, loan interest, seed/fuel/fertilizer/equipment discounts, insurance payouts, export opportunities, economic crises, and more.

### 🚜 Vehicle Events (10 events)
Speed boosts, free fuel refills, fuel leaks, minor accidents, fleet repair bills, visual upgrades, vehicle cleaning, engine trouble, a loose-axle steering pull, and slippery low-traction conditions. The speed, engine and steering effects act through the game's real vehicle physics, so you feel them at the wheel.

### 🌾 Field Events (10 events)
Crop yield bonuses and penalties, fertilizer effectiveness changes, seed growth speed adjustments, harvest modifiers, and field sale price shifts.

### ⚡ Special Events (10 events)
Time acceleration, time slowdown, XP bonuses and penalties, money multipliers, equipment durability changes, trade price bonuses, and town festivals.

### 🔧 Real Vehicle Physics
- **Honest engine fields only** - speed cap (`vehicle.speedLimit`), top speed (`motor.maxForwardSpeed`), acceleration (`motor:setAccelerationLimit`) and steering input are the actual values the game reads, so changes are felt and cleanly restored
- **Traction governor** - on loose ground (field, mud, snow) the machine you're driving eases off the throttle and speed for calmer control; surfaces are read from the real wheel-surface data
- **Steering pull** - events can gently tug the wheel to one side, the same way a real loose front axle would
- Tunable from the in-game settings screen, with a correct debug readout (speed, surface, active modifiers)

> The steering-pull effect feeds a value into the game's own steering input each frame - a technique adapted from **RealPhysics Steering by Tubez47**. Big thanks to Tubez47 for showing the clean way to do it. See Credits below.

### 🖥️ In-Game Settings Screen
Full tabbed GUI accessible from the game's menu:
- **Events Tab** - toggle categories, set frequency/intensity/cooldown, enable notifications
- **Physics Tab** - enable the physics layer and tune loose-ground traction

### 💾 Per-Savegame Persistence
Settings are stored alongside each savegame - different farms can have different configurations without touching the mod files.

---

## 🛠️ Installation

1. Download `FS25_RandomWorldEvents.zip` from the [latest release](https://github.com/TheCodingDad-TisonK/FS25_RandomWorldEvents/releases/latest).
2. Place the zip in your FS25 mods folder:
   - **Windows:** `Documents\My Games\FarmingSimulator2025\mods\`
3. Launch Farming Simulator 25.
4. When starting or loading a savegame, enable **Random World Events** in the mod selection screen.
5. Load into your farm - you'll see a confirmation notification when the mod initializes.

---

## 🎛️ Default Settings

| Setting | Default | Range | Description |
|---------|---------|-------|-------------|
| `enabled` | `true` | - | Master on/off switch |
| `frequency` | `5` | 1-10 | Event trigger probability |
| `intensity` | `2` | 1-5 | Event magnitude |
| `cooldown` | `30` | 1-240 min | Minimum time between events |
| `showNotifications` | `true` | - | HUD notices when events start/end |
| `showWarnings` | `true` | - | Warning-level notifications |
| `economicEvents` | `true` | - | Enable economic category |
| `vehicleEvents` | `true` | - | Enable vehicle category |
| `fieldEvents` | `true` | - | Enable field category |
| `specialEvents` | `true` | - | Enable special category |

### Physics Defaults

| Setting | Default | Range | Description |
|---------|---------|-------|-------------|
| `physics.enabled` | `true` | - | Master switch for the vehicle-physics layer |
| `wheelGripMultiplier` | `1.0` | 0.5-2.0 | Loose-ground traction: higher = more grip, less slowdown |

> Legacy settings `suspensionStiffness`, `articulationDamping` and `comStrength` are still read from old save files for compatibility, but they are no longer used - the original code wrote to engine fields that do not exist, so the controls were retired rather than left as silent no-ops.

---

## 🖥️ Console Commands

Open the in-game console (`` ` `` key) and type any of these:

| Command | Description |
|---------|-------------|
| `rwe` | Show all available commands |
| `rweStatus` | Show current status - enabled state, active event, cooldown |
| `rweTest` | Force-trigger a random event immediately |
| `rweEnd` | Forcibly end the currently active event |
| `rweDebug on\|off` | Toggle debug mode (verbose logging) |
| `rweList [category]` | List all registered events, optionally filtered by category |

### Key Bindings

| Key | Action |
|-----|--------|
| **F9** | Force-trigger a random event |
| **F3** | Open settings screen *(coming soon)* |

---

## 🌐 Availability

| Platform | Status |
|----------|--------|
| **GitHub** | ✅ [Official Source](https://github.com/TheCodingDad-TisonK/FS25_RandomWorldEvents) |
| **ModHub** | 🔄 Pending |
| **KingMods** | ✅ [Download](https://www.kingmods.net/en/fs25/mods/75232/random-world-events) |

---

## 📖 Version History

| Version | Date | Notes |
|---------|------|-------|
| **v2.1.7.0** | 2026-06 | Vehicle event category rebuilt on real basegame physics (speed, acceleration, engine, steering pull, traction); fixed fuel and repair-bill events (correct FillUnit + farm APIs); steering technique credited to RealPhysics Steering by Tubez47 |
| **v2.0.0.0** | 2026-02 | Full FS25 rewrite - new event engine, physics layer, tabbed GUI, per-savegame settings |

---

## ⚠️ Known Limitations

- **Wildlife/animal events** - category toggle exists but events are not yet implemented
- **Weather events** - category toggle exists but events are not yet implemented
- **Multiplayer** - declared as supported but money/physics changes are local-only; proper network sync is not yet implemented
- **Suspension tuning** - there is no supported way to rescale a vehicle's suspension spring force from script in FS25, so the old "suspension stiffness" control was removed rather than faked

---

## 🚧 Planned Features

- Complete wildlife/animal event category
- Complete weather event category
- Multiplayer-safe money synchronization
- Full F3 settings screen keybind
- Event history log viewable in-game
- Weighted event selection (rare vs. common events)

---

## ⬆️ Upgrading from FS22

This is a ground-up rewrite for FS25. FS22 savegame settings will not transfer - configure the mod fresh in each savegame. The event catalog has been expanded and the physics system is new in v2.

---

## 🤝 Credits

- **Author**: TisonK
- **RealPhysics Steering by Tubez47** - the vehicle "steering pull" effect feeds a value into the game's own steering input each frame so the wheels behave as if you were turning them, and the mod's vehicle-physics layer attaches itself to existing vehicles using the same approach Tubez47 used. Both techniques are adapted from RealPhysics Steering. Thank you, Tubez47!
- **Special Thanks**: FS25 modding community and everyone who reported bugs on the FS22 version

---

## 📬 SupportRe

Found a bug or have a feature request?
Open an issue on Git

👉 https://github.com/TheCodingDad-TisonK/FS25_RandomWorldEvents/issues

---

## ⚖️ License

**All rights reserved.**

Unauthorized redistribution, modification, reuploading, or claiming this mod as your own is **strictly prohibited**.

Original author: TisonK

---

*Enjoy a more unpredictable farming experience!* 🌾
