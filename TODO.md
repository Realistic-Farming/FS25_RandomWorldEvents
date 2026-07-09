# TODO: FS25_RandomWorldEvents

> Ecosystem role: **World and NPCs** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [ ] Fast-track F17: the event id is `geopolitical`, not `geopolitical_crisis`. Correct it wherever referenced.
- [ ] Add a save hook so state is crash-safe (today it saves only on delete()).
- [ ] Remove the RWESettingsIntegration ESC injection (19 settings) and the FSBaseMission draw + mouseEvent hooks; keep the Shift+O RWESettingsPanel.

## Bugs
- [x] MP money bug (F16): RESOLVED in v2.1.7.1. Money now routes through `rweAddMoney`, which gates on `getIsServer` across all five event files (confirmed by the 2026-07-09 ecosystem money-authority sweep).
- [!] Crash data loss: settings and active event state save only on delete(); a crash loses them.

## Features / enhancements
- [ ] Bedrock migration per Point 1-5.

## Cross-mod integration
- [ ] StateLedger: `RandomWorldEvents_Settings` (26 keys) + `RandomWorldEvents_EventState` (4 keys), with a save hook.
- [ ] NetworkSync: `RandomWorldEvents_Sync`.
- [ ] MasterHUD: 2 panels (EventHUD + SettingsPanel).
- [ ] SettingsHub: register the 19 settings.
- [x] Companion surface: `RWEEconomicAPI` subsystem (getPriceModifier) is consumed by MarketDynamics; top-level reads defined.

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [!] Vehicle-event server-gate exemption decision (waits on: audit answer, whether physics events skip the getIsServer gate since they are local-player physics, not farm balance).
