# CaPowHr
**Last Updated:** 2026-10-10
**Status:** active

### 🎯 Current Phase
2.2.1 is shipped; `main` carries the 3.0 feature set as a pure watch-only app. The repo
was audited for secrets ahead of a fork/contribution request and is clean; the BLE log
capture flow is moving from a bundled GitHub token to the system share sheet.

### ✅ Just Completed
- [x] Audited repo and full history for sensitive data; rotated the leaked Strava client secret and deleted the remote `ios-companion-strava-wip` branch.
- [x] BLE log capture now shares the log via the share sheet; GitHub issue upload, bundled token, and `CAPOWHR_GITHUB_TOKEN` removed (PR open).
- [x] Merged PR #14: removed the incomplete iOS companion app and WatchConnectivity bridge.
- [x] Fixed App Store Connect ITMS validation failures for the watch-only container.
- [x] Released 2.2.1; tagged `v2.2.1` and the `v2.2` baseline.
- [x] Made `main` build from a clean checkout: blank tracked `Secrets.xcconfig`, real values via gitignored `Secrets.local.xcconfig`.

### 🚀 Next Steps
- [ ] Merge the BLE log share-sheet PR; on a real watch, confirm a full 20-second log shares intact via Messages and Mail.
- [ ] Verify on real hardware: FTMS Control Point handshake, and that a saved ride keeps its Move ring calories.
- [ ] Decide the rest of the 3.0 scope and trigger an Xcode Cloud build from `main`.
- [ ] Delete stale local branches: `diag/2.2.1-ble-trace`, `state-refresh-2.2.1-readiness`, `fix/2.2.1-reconnect-and-distance`, `port/2.2.1-ftms-fixes`, `fix/calorie-source-setting`, `ios-companion-strava-wip`.

### 📋 Backlog / Later
- [ ] Default the distance unit from the device locale instead of hard-defaulting to Miles.
- [ ] Whole-ride BLE logging behind a user-facing debug toggle.
- [ ] `didFailToConnect` fallback retry handling.
- [ ] FTMS resistance/incline control, now that the Control Point handshake exists.
- [ ] Restore local Strava credentials in `Config/Secrets.local.xcconfig` (blanked during the 2.2.1 CI work; secret since rotated).

### 🛑 Blockers & Known Issues
- None.
