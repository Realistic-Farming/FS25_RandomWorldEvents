# Vision: FS25_RandomWorldEvents

> Ecosystem role: **World and NPCs** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit (Point 1-5, ecosystem-map, notes).
> Last updated: 2026-07-08

## 1. One-line purpose
Random world events: periodic economic and physical events (droughts, financial panics, geopolitical shifts, and more) that shake up the world and economy so no two seasons play the same.

## 2. Problem it solves
The FS25 world is static between seasons. Nothing unexpected happens, so there is no risk to plan against. RandomWorldEvents injects probabilistic events that modify prices and finances (and optionally vehicle physics) to add variety and consequence.

## 3. Design pillars
- **Server-authoritative effects.** Money and economy effects apply on the server only, once per event, never per client.
- **Probabilistic, not scheduled.** Events roll on a cadence; there is no calendar or prediction, only active state and cooldown.
- **Crash-safe persistence.** Event state and settings survive a crash, not only a clean shutdown.
- **Companion price-modifier surface.** The economic subsystem exposes a stable price-modifier API that MarketDynamics consumes.

## 4. Role in the ecosystem
- Public handle: `g_currentMission.randomWorldEvents` (getfenv alias `g_RandomWorldEvents`), set in `Mission00.load` PREPEND.
- Reads from (consumes): nothing cross-mod. Economic events use base-game `g_farmManager:getFarmById()` and `player.farmId`.
- Read by (consumers): MarketDynamics (via the `RWEEconomicAPI` economic subsystem, `getPriceModifier`), FarmTablet RandomWorldEventsApp (currently a stub; the handle is published, so finishing it is app-side work).
- Companion surface: `g_currentMission.randomWorldEvents:getSubsystem("economic")` (setPriceModifier / getPriceModifier / registerEvent), plus top-level reads (isEventSystemActive, getActiveEvent, getActiveEventCategory, getActiveEventRemainingMs, getCooldownRemainingMs, getIntensity).
- Core-API registration status (specced in Point 1-5, not yet wired):
  - StateLedger (save/load): planned, split into `RandomWorldEvents_Settings` (26 keys) + `RandomWorldEvents_EventState` (4 keys), and it ADDS a save hook (today state only saves on delete()).
  - NetworkSync (MP state): planned, channel `RandomWorldEvents_Sync`.
  - MasterHUD (overlays): planned, 2 panels (EventHUD + the Shift+O quick SettingsPanel); removes the FSBaseMission.draw and mouseEvent hooks.
  - SettingsHub (admin settings): planned, 19 settings; removes the ESC-menu injection (RWESettingsIntegration).

## 5. Explicit non-goals
- No event scheduling or prediction. Peers read active state and cooldown, not a forecast.
- Economic effects are never client-applied.

## 6. Success criteria
- Events fire believably and their money effects apply exactly once in multiplayer.
- Event state and settings survive a mid-session crash (save hook, not delete-only).
- MarketDynamics reads the price modifier correctly through the economic subsystem.

## 7. Open questions for the audit
- Should vehicle physics events be exempt from the server gate? They affect local player physics, not farm balance, so a blanket `getIsServer()` guard at `applyActiveEventEffects()` may be too broad for them.
