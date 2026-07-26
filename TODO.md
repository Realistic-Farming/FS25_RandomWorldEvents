# TODO: FS25_RandomWorldEvents

> Ecosystem role: **World and NPCs** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [x] Fast-track F17: MISATTRIBUTED to RandomWorldEvents. The `geopolitical` event id belongs to MarketDynamics (GeopoliticalEvent.lua:14, correct in source); RWE defines no such event. The wrong `geopolitical_crisis` appears only in the DairyCore BUILD-BRIEF. No RWE code change; handed to Arissani to correct the brief (ledger 2026-07-09).
- [x] Add a save hook so state is crash-safe. DONE: event state persists on the game save cycle (server-only), not just on delete().
- [~] SettingsHub + MasterHUD bridged; removing the RWESettingsIntegration ESC injection (19 settings) and the FSBaseMission draw + mouseEvent hooks is deferred (kept as the standalone fallback; Shift+O RWESettingsPanel retained).

## Bugs
- [x] Special-event reputation write not server-gated (7b076c4): the special-event reputation write is now behind a server check, matching the money-authority gating.
- [x] Logging.debug nil-call crash (#20, a49fcbc): the last `Logging.debug` nil call in the vehicle input hook removed.
- [x] MP money bug (F16): RESOLVED in v2.1.7.1. Money now routes through `rweAddMoney`, which gates on `getIsServer` across all five event files (confirmed by the 2026-07-09 ecosystem money-authority sweep).
- [x] Crash data loss RESOLVED: event state now persists on the game save cycle (server-only), not only on delete().

## Features / enhancements
- [x] Bedrock migration DONE: StateLedger + SettingsHub + MasterHUD bridged (NetworkSync N/A by design).

## Cross-mod integration
- [x] StateLedger: `RandomWorldEvents_Settings` + `RandomWorldEvents_EventState` bridge live, with the game-save-cycle save hook (delegate-when-present).
- [x] NetworkSync: N/A by design (server-authoritative event state; no per-frame sync channel needed).
- [x] MasterHUD: EventHUD + settings panel bridged (own draw stands down when active).
- [x] SettingsHub: 19 settings registered (selfPersisted). ESC injection retained as the standalone fallback.
- [x] Companion surface: `RWEEconomicAPI` subsystem (getPriceModifier) is consumed by MarketDynamics; top-level reads defined.

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [!] Vehicle-event server-gate exemption decision (waits on: audit answer, whether physics events skip the getIsServer gate since they are local-player physics, not farm balance).
