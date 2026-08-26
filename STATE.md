# CaPowHr
**Last Updated:** 2026-08-25
**Status:** active

### 🎯 Current Phase
2.2.1 is released and tagged; the hotfix train is closed. All work is now on `main`,
which carries the 3.0 multi-modality feature set plus every 2.2.1 BLE fix. Currently
working 3.0 feature requests off the back of field reports.

### ✅ Just Completed
- [x] Released 2.2.1; tagged `v2.2.1` and retroactively tagged the `v2.2` baseline.
- [x] Ported the FTMS Control Point (`0x2AD9`) handshake and targeted characteristic discovery to `main` (PR #11).
- [x] Made `main` build from a clean checkout: `Config/Secrets.xcconfig` tracked blank, real values via gitignored `Secrets.local.xcconfig`.
- [x] Diagnosed the disappearing-calories reports: eager FTMS energy handover displaced Apple's estimate ~1 min into every ride.
- [x] Added a Calories setting (Apple Watch / Equipment, default Apple Watch) so machine energy is opt-in.
- [x] Confirmed the miles/kilometers option users asked for already exists in 3.0 — it was absent only in shipped 2.2.1.
- [x] Watch unit suite green at 23/23 on the watchOS 26.5 simulator.

### 🚀 Next Steps
- [ ] Merge PR #11 (`port/2.2.1-ftms-fixes`) and the calorie-source PR into `main`.
- [ ] Verify on real hardware: FTMS Control Point handshake, and that a saved ride now keeps its Move ring calories.
- [ ] Fix the stale README on `main` — it still lists training zones, structured workouts, and the equipment compatibility list, all removed in PRs #4/#5.
- [ ] Decide the rest of the 3.0 scope and trigger an Xcode Cloud build from `main`.
- [ ] Delete stale branches: `diag/2.2.1-ble-trace`, `state-refresh-2.2.1-readiness`, `fix/2.2.1-reconnect-and-distance`.

### 📋 Backlog / Later
- [ ] Default the distance unit from the device locale instead of hard-defaulting to Miles.
- [ ] Whole-ride BLE logging behind a user-facing debug toggle.
- [ ] `didFailToConnect` fallback retry handling.
- [ ] FTMS resistance/incline control, now that the Control Point handshake exists.
- [ ] Finish the iOS companion Strava OAuth flow (`ios-companion-strava-wip`).
- [ ] Restore local Strava credentials in `Config/Secrets.local.xcconfig` (blanked during the 2.2.1 CI work).

### 🛑 Blockers & Known Issues
- Rest of the 3.0 scope is undefined beyond the current field-report fixes.
