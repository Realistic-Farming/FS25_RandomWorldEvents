# TODO: FS25_RandomWorldEvents

> Ecosystem role: **World and NPCs** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [x] Fast-track F17: MISATTRIBUTED to RandomWorldEvents. The `geopolitical` event id belongs to MarketDynamics (GeopoliticalEvent.lua:14, correct in source); RWE defines no such event. The wrong `geopolitical_crisis` appears only in the DairyCore BUILD-BRIEF. No RWE code change; handed to Arissani to correct the brief (ledger 2026-07-09).
- [x] Add a save hook so state is crash-safe. DONE: event state persists on the game save cycle (server-only), not just on delete().
- [~] SettingsHub + MasterHUD bridged; removing the RWESettingsIntegration ESC injection (20 settings) and the FSBaseMission draw + mouseEvent hooks is deferred (kept as the standalone fallback; Shift+O RWESettingsPanel retained).

## Bugs
- [x] Special-event reputation write not server-gated (7b076c4): the special-event reputation write is now behind a server check, matching the money-authority gating.
- [x] Logging.debug nil-call crash (#20, a49fcbc): the last `Logging.debug` nil call in the vehicle input hook removed.
- [x] MP money bug (F16): RESOLVED in v2.1.7.1. Money now routes through `rweAddMoney`, which gates on `getIsServer` across all five event files (confirmed by the 2026-07-09 ecosystem money-authority sweep).
- [x] Crash data loss RESOLVED: event state now persists on the game save cycle (server-only), not only on delete().
- [x] RWE-001 / RWE-002 / RWE-003 / RWE-004: additional RandomWorldEvents bugs fixed in 2026-07-26 bug sweep, merged to main.

## Features / enhancements
- [x] Redesign NON-PRICE HALF (2026-08-14, branch `feat/RWE-redesign-nonprice`, v2.2.0.0). CUT 13 arcade edges (time warps, rep, cash-from-nowhere, magic fuel, free upgrades/cleaning, steering pull, slippery roads, fuel discount); world/sim events are now PULL read-signals; arcade physics behind the opt-in `arcadePhysics` toggle (default OFF, player-vehicle only, never economy); difficulty rides the Option-Scaling Spine (vendored resolver, World-events dial applied to frequency + base intensity, Economy dial exposed); read surface completed (getActiveEvent / isEventActive / getProgress / getRemainingTime / getIntensity / getIntensity-nil). Event catalog 53 -> 40. Bench at `tools/test/rwe-redesign-bench.mjs` (16 checks).
- [x] Release gate mechanism (2026-08-04): `ReleaseGate.lua` with an EMPTY registry (Arissani 2026-08-03). `experimentalSystems` opt-in (default false, orthogonal to difficulty) through the settings manager load/save, the SettingsHub mirror and a settings-panel toggle. `rweRelease` status command. Nothing gated; a row drops in the moment a system needs locking.
- [x] Bedrock migration DONE: StateLedger + SettingsHub + MasterHUD bridged (NetworkSync N/A by design).

## Cross-mod integration
- [x] StateLedger: `RandomWorldEvents_Settings` + `RandomWorldEvents_EventState` bridge live, with the game-save-cycle save hook (delegate-when-present).
- [x] NetworkSync: N/A by design (server-authoritative event state; no per-frame sync channel needed).
- [x] MasterHUD: EventHUD + settings panel bridged (own draw stands down when active).
- [x] SettingsHub: 20 settings registered (selfPersisted). ESC injection retained as the standalone fallback.
- [x] Companion surface: `RWEEconomicAPI` subsystem (getPriceModifier) is consumed by MarketDynamics; top-level reads defined.

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [!] Redesign PRICE half (gated): re-home the retained price events to MarketDynamics registered price modifiers; the EffectHooks getPricePerLiter patch stays until then. Brief gate says registerPriceModifier is unbuilt; notes.md records it as built (1.2.0.9, MarketDynamics.lua:301) since 2026-07-31 - re-verify at build time, do not build ahead.
- [!] Redesign MONEY half (gated): accrue retained money events and settle on onDayChange via TaxMod recordExpense (both directions); instant server-gated addMoney stays until then. Includes the harvest-festival money trickle.
- [!] Economy-dial application: read + exposed via getDifficulty(), application lands with the money/price re-homes.
- [!] Vehicle-event server-gate exemption decision (waits on: audit answer, whether physics events skip the getIsServer gate since they are local-player physics, not farm balance). Superseded in practice by the arcadePhysics opt-in + player-vehicle scoping.
