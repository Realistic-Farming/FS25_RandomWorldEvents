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

### Fixed
- RSF-F201: cab and on-foot controls stay valid across vehicle entry and exit. Each input context now registers through its own private target, so the PLAYER and VEHICLE registrations no longer share one engine identifier that a cab rebuild wiped. Membership is checked in the wrap's own context, a complete set costs no registration work, and the input wrappers install once per session instead of being restored on every mission teardown. The cab early return that skipped re-registration after a rebuilt context is gone; the hook record lives on RWE_InputHookRecord.

## [2.2.0.1] - 2026-08-22

- First entry under changelog tracking.
