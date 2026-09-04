# CaPowHr
**Last Updated:** 2026-08-25
**Status:** active

### 🎯 Current Phase
2.2.1 is released and tagged; the hotfix train is closed. All work now happens on
`main`, which carries the 3.0 multi-modality feature set (bike/treadmill/rower,
Strava, iOS companion) plus every 2.2.1 BLE fix. Next macro goal is defining and
building the 3.0 release scope.

### ✅ Just Completed
- [x] Released 2.2.1; tagged `v2.2.1` and retroactively tagged the `v2.2` baseline.
- [x] Ported the FTMS Control Point (`0x2AD9`) Request Control + Start/Resume handshake to `main`.
- [x] Ported targeted FTMS characteristic discovery to `main` (was discovering all characteristics).
- [x] Confirmed `main` already had the FTMS distance-delta accumulation fix; no port needed.
- [x] Made `main` build from a clean checkout: `Config/Secrets.xcconfig` tracked blank, real values via gitignored `Secrets.local.xcconfig`.
- [x] Brought the Xcode Cloud manifest onto `main`.
- [x] Watch unit suite green at 20/20 on the watchOS 26.5 simulator.

### 🚀 Next Steps
- [ ] Merge PR `port/2.2.1-ftms-fixes` into `main`.
- [ ] Decide the 3.0 release scope and cut a `release/3.0` plan.
- [ ] Verify the FTMS Control Point handshake on real hardware against the 3.0 build.
- [ ] Trigger an Xcode Cloud build from `main` to confirm CI works there.
- [ ] Delete stale branches: `diag/2.2.1-ble-trace`, `state-refresh-2.2.1-readiness`, `fix/2.2.1-reconnect-and-distance`.

### 📋 Backlog / Later
- [ ] Whole-ride BLE logging behind a user-facing debug toggle.
- [ ] `didFailToConnect` fallback retry handling.
- [ ] Restore local Strava credentials in `Config/Secrets.local.xcconfig` (blanked during the 2.2.1 CI work).
- [ ] Finish the iOS companion Strava OAuth flow (`ios-companion-strava-wip`).

### 🛑 Blockers & Known Issues
- 3.0 scope is undefined — needs a decision before implementation starts.
