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
- [x] Redesign NON-PRICE HALF (2026-08-14, branch `feat/RWE-redesign-nonprice`, v2.2.0.0): keep the role, delegate the mechanism.
  - CUT 13 arcade edges entirely: time_acceleration, time_slowdown, bonus_xp, malus_xp, money_bonus, money_malus, vehicle_fuel_bonus, vehicle_fuel_penalty, vehicle_free_upgrade, vehicle_cleaning_bonus, vehicle_steering_pull, vehicle_slippery_roads, fuel_discount. No more timeScale writes, no more repPoints writes, no more cash-from-nowhere trickles for the field/animal/special read-signals (the field and animal per-60-second money tick handlers are removed; the harvest festival's money trickle stays until the gated money half lands).
  - World/sim events (crop_yield, fertilizer, seed_growth, animal_product, wolf_sighting, bumper_wool_season, disease_scare, wildlife_pest_invasion) are now PULL read-signals: RWE announces and exposes them; SoilFertilizer / CropDisease / DairyCore apply their own model. The read surface is complete on the manager: getActiveEvent, isEventActive, getProgress, getRemainingTime, getIntensity (nil when nothing active), getEventIntensity (numeric).
  - Arcade physics moved behind the opt-in `RandomWorldEvents.arcadePhysics` toggle (default OFF, admin SettingsHub key): vehicle_speed_boost, vehicle_engine_trouble, equipment_durability_boost/drop only enter the trigger pool when ON, and the `Vehicle.addDamageAmount` patch only scales the player's own vehicle when ON. The 4 events keep the current player-vehicle scoping.
  - Difficulty rides the Option-Scaling Spine: vendored the pure `OptionScalingResolver` (byte-identical to SettingsHub's spine branch); `getDifficulty()` reads the World-events dial (frequency + base intensity, applied to the scheduler) and the Economy dial (exposed for the gated economic half). Spine absent or dial off = neutral = RWE's own settings.
  - Event catalog 53 -> 40 (economic 14, field 10, vehicle 4, wildlife 8, special 4). Help text and category counts updated in 26 languages; new arcadePhysics strings in 26 languages.
- [x] Release gate mechanism (2026-08-04): wired per Arissani's 2026-08-03 lock set (EMPTY for RWE - the redesign is unbuilt; only bug fixes have shipped, and fixes flow free). `ReleaseGate.lua` with an empty registry, `experimentalSystems` opt-in (default false, orthogonal to difficulty) through settings/persistence/SettingsHub/panel, and the `rweRelease` status command. Nothing gated today.
- [x] MP money bug (F16): DONE in v2.1.7.1. Money routes through `rweAddMoney`, gated on `getIsServer` (confirmed by the 2026-07-09 money-authority sweep).
- [x] Server-gate the special-event reputation write (7b076c4) and remove the last `Logging.debug` nil-call crash in the vehicle input hook (#20, a49fcbc). DONE.
- [x] Crash-safe save: event state persists on the game save cycle (server-only), not only on delete(). DONE.
- [x] Event id `geopolitical`: N/A for RWE. It was misattributed - the id belongs to MarketDynamics (correct in source); the wrong `geopolitical_crisis` was only in the DairyCore brief (handed to Arissani). No RWE change.
- [x] 2026-07-26 bug sweep: RWE-001 (server-only event guard), RWE-002 (duplicate HUD drag), RWE-003 (cooldown only on fire), RWE-004 (yieldMalus self-assignment) fixed and merged to main.

## Mid-term (this season)
- [x] StateLedger split: `RandomWorldEvents_Settings` + `RandomWorldEvents_EventState` bridged (remaining-ms to absolute-timestamp conversion preserved on load).
- [x] NetworkSync: N/A by design (server-authoritative event state).
- [~] MasterHUD: EventHUD + settings panel bridged (own draw stands down); removing the FSBaseMission.draw and mouseEvent hooks is deferred (kept as fallback).
- [~] SettingsHub: 20 settings registered (selfPersisted); removing the RWESettingsIntegration ESC injection is deferred (kept as fallback).

## Long-term / aspirational
- [ ] Richer event catalogue and categories without breaking the economic subsystem API.

## Cross-mod / ecosystem dependencies
- [ ] Read by MarketDynamics (`getPriceModifier` via the economic subsystem).
- [x] Bedrock migrations DONE: StateLedger + SettingsHub + MasterHUD bridged (NetworkSync N/A by design).

## Gated follow-up (blocked by design, do not build ahead)
The NON-PRICE HALF of the redesign is built (2026-08-14); these halves stay on the shelf:
- [ ] PRICE half (blocked on the MarketDynamics re-home): market_boom/crash, price_fixing, export_opportunity, harvest/field_sale, bonus_trade_prices and the economic_crisis market-malus move from the EffectHooks getPricePerLiter patch to registered MarketDynamics price modifiers. The patch stays in place until then; only the read-signal flags (yieldBonus/yieldMalus) have left it.
- [ ] MONEY half (blocked on the onDayChange settlement): government_subsidy, sudden_expense, farmer_donation, insurance_bonus, tax_refund, loan_interest, economic_crisis loan cost, feed_shortage, veterinary_windfall, vehicle_accident, vehicle_repair_bill and the shop discounts accrue and settle on onDayChange via TaxMod recordExpense instead of instant addMoney. The instant server-gated addMoney calls are preserved until then.
- [ ] Economy-dial application: the spine's Economy dial is read and exposed via getDifficulty() but not yet applied to economic magnitudes; it lands with the money/price re-homes.
- [ ] NOTE: the workspace notes record MarketDynamics registerPriceModifier as already built (1.2.0.9) as of 2026-07-31, which contradicts the brief's gate note. The price half stays unbuilt per the brief regardless; re-verify the dependency before building it.

## Deferred / parked
- Event scheduling / prediction API: parked by design. Events are probabilistic; peers read active state and cooldown only.
- Stale help copy outside the redesign's cut list (pre-existing fiction in helpLine_rwe_cat3_wildlife and similar) is fixed where it named cut features; the remainder is a docs sweep, not a code issue.
