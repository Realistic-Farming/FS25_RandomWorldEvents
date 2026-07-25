# Roadmap: FS25_RandomWorldEvents

> Ecosystem role: **World and NPCs** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline.
> Forward-looking only. Shipped history lives in CHANGELOG.md and the releases.

## How to use this file
- Populate the milestones below from the audit baseline once it lands.
- Each item should be small enough to map to a `TODO.md` entry.
- Keep it honest: near-term is committed, mid-term is intended, long-term is aspirational.

## Current baseline
- Version at baseline: v2.1.7.1
- Audit reference: ecosystem-dev-tracking Point 1-5 (FS25_RandomWorldEvents, 2026-06-30)
- Baseline date: 2026-06-30 (updated 2026-07-25)

## Near-term (next release cycle)
- [x] MP money bug (F16): DONE in v2.1.7.1. Money routes through `rweAddMoney`, gated on `getIsServer` (confirmed by the 2026-07-09 money-authority sweep).
- [x] Server-gate the special-event reputation write (7b076c4) and remove the last `Logging.debug` nil-call crash in the vehicle input hook (#20, a49fcbc). DONE.
- [x] Crash-safe save: event state persists on the game save cycle (server-only), not only on delete(). DONE.
- [x] Event id `geopolitical`: N/A for RWE. It was misattributed - the id belongs to MarketDynamics (correct in source); the wrong `geopolitical_crisis` was only in the DairyCore brief (handed to Arissani). No RWE change.

## Mid-term (this season)
- [x] StateLedger split: `RandomWorldEvents_Settings` + `RandomWorldEvents_EventState` bridged (remaining-ms to absolute-timestamp conversion preserved on load).
- [x] NetworkSync: N/A by design (server-authoritative event state).
- [~] MasterHUD: EventHUD + settings panel bridged (own draw stands down); removing the FSBaseMission.draw and mouseEvent hooks is deferred (kept as fallback).
- [~] SettingsHub: 19 settings registered (selfPersisted); removing the RWESettingsIntegration ESC injection is deferred (kept as fallback).

## Long-term / aspirational
- [ ] Richer event catalogue and categories without breaking the economic subsystem API.

## Cross-mod / ecosystem dependencies
- [ ] Read by MarketDynamics (`getPriceModifier` via the economic subsystem).
- [x] Bedrock migrations DONE: StateLedger + SettingsHub + MasterHUD bridged (NetworkSync N/A by design).

## Deferred / parked
- Event scheduling / prediction API: parked by design. Events are probabilistic; peers read active state and cooldown only.
