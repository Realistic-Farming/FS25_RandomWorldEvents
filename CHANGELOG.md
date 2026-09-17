# Changelog

All notable changes to FS25_RandomWorldEvents will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

## [Unreleased]

### Added
- Changelog file established (suite ruling 2026-08-22).
- Playtest fixes: RWE_TOGGLE_HUD (RShift+E) and RWE_HUD_DRAG (RShift+Q) chords, event HUD, vehicle hook with spam guard.
- Control Center action: RWE_TOGGLE_SETTINGS opens world-event settings from the suite Control Center (requires SettingsHub).

### Changed
- EC-6 (paired with MarketDynamics EC-6, ship both in the same release). **BALANCE CHANGE: money events now pay.** Before, money went to a local player farm that was never set, so it reached farm 0 and the game refused it. Now each money event posts one statement line to every eligible farm, fixed when the event is announced and settled once at the end of the in-game day, in single player, on a listen host and on a dedicated server. Each paid farm sees its own amount privately; shared notices never name an amount.
- Price events move selling prices only through MarketDynamics' registered modifier, at the next market update, and only while MarketDynamics prices are on. The old engine price patch is gone (selling stations never read it; fill-trigger purchases, bales and production payouts did). Settings show the market price status.
- Seed discount, fertilizer discount, equipment discount and tax refund are retired; the catalogue is 36 events. The harvest festival is a price event only.
- Vehicle incident and inspection invoice events post an invoice and no longer damage or repair machines. The loose-ground traction effect is part of Arcade Physics (off by default); the unused steering-pull effect is removed (RWEVehicleAPI ignores steerPull).
- Every event notice, title and summary is translated in all 27 game languages and names no figure. Joining players see the active event and its summary.
- A reload keeps an active event whole: intensity, summary, crisis parts and pending statement lines are saved (StateLedger block schema 2).

### Fixed
- Equipment Durability events (Low Wear / High Wear) now change the wear the player's own vehicle takes while Arcade Physics is on. The old hook targeted a function that does not exist and never installed; the durability scaling now wraps each vehicle's own usage-damage step as it loads. The scaling applies to every vehicle in use (driven by any player, run by a hired worker, or attached to one), decided on the server, on a dedicated server too; parked vehicles are untouched.
- The Arcade Physics setting texts held Simplified Chinese under the French Canadian column; French Canadian and Simplified Chinese now each get their own text.
- RSF-F201: cab and on-foot controls stay valid across vehicle entry and exit. Each input context now registers through its own private target, so the PLAYER and VEHICLE registrations no longer share one engine identifier that a cab rebuild wiped. Membership is checked in the wrap's own context, a complete set costs no registration work, and the input wrappers install once per session instead of being restored on every mission teardown. The cab early return that skipped re-registration after a rebuilt context is gone; the hook record lives on RWE_InputHookRecord.

## [2.2.0.1] - 2026-08-22

- First entry under changelog tracking.
