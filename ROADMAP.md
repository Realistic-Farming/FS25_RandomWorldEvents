# Roadmap: FS25_RandomWorldEvents

> Ecosystem role: **World and NPCs** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline.
> Forward-looking only. Shipped history lives in CHANGELOG.md and the releases.

## How to use this file
- Populate the milestones below from the audit baseline once it lands.
- Each item should be small enough to map to a `TODO.md` entry.
- Keep it honest: near-term is committed, mid-term is intended, long-term is aspirational.

## Current baseline
- Version at baseline: confirm from modDesc.xml
- Audit reference: ecosystem-dev-tracking Point 1-5 (FS25_RandomWorldEvents, 2026-06-30)
- Baseline date: 2026-06-30

## Near-term (next release cycle)
- [x] MP money bug (F16): DONE in v2.1.7.1. Money routes through `rweAddMoney`, gated on `getIsServer` (confirmed by the 2026-07-09 money-authority sweep).
- [ ] Crash-safe save: add a save hook (StateLedger) so event state and settings persist mid-session, not only on delete().
- [ ] Correct the event id `geopolitical` (not `geopolitical_crisis`) wherever it is referenced.

## Mid-term (this season)
- [ ] StateLedger split: `RandomWorldEvents_Settings` (26 keys) + `RandomWorldEvents_EventState` (4 keys); preserve the remaining-ms to absolute-timestamp conversion on load.
- [ ] NetworkSync channel `RandomWorldEvents_Sync`.
- [ ] MasterHUD: 2 panels (EventHUD + Shift+O SettingsPanel); remove the FSBaseMission.draw and mouseEvent hooks.
- [ ] SettingsHub: register the 19 settings; remove the RWESettingsIntegration ESC injection.

## Long-term / aspirational
- [ ] Richer event catalogue and categories without breaking the economic subsystem API.

## Cross-mod / ecosystem dependencies
- [ ] Read by MarketDynamics (`getPriceModifier` via the economic subsystem).
- [ ] All four bedrock migrations (blocks on: StateLedger, NetworkSync, MasterHUD, SettingsHub).

## Deferred / parked
- Event scheduling / prediction API: parked by design. Events are probabilistic; peers read active state and cooldown only.
