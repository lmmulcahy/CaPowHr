# CaPowHr
**Last Updated:** 2026-10-11
**Status:** active

### 🎯 Current Phase
2.2.1 is shipped; `main` carries the 3.0 feature set as a pure watch-only app. A
spec-driven, verify-don't-review workflow (specs, locked tests, verify hooks,
independent reviewer) is being set up on `agent-workflow-setup`; the first real
feature will trial `/spec` → `/build` → `/ship`.

### ✅ Just Completed
- [x] Set up the agent workflow: CLAUDE.md, docs/ (PRD draft, ARCHITECTURE, decisions, specs), verify.sh, hooks, reviewer, /spec /build /ship /drift (PR open).
- [x] Merged PR #15: BLE log capture shares via the share sheet; GitHub upload and bundled token removed.
- [x] Audited repo and full history for sensitive data; rotated the leaked Strava client secret and deleted the remote `ios-companion-strava-wip` branch.
- [x] Merged PR #14: removed the incomplete iOS companion app and WatchConnectivity bridge.
- [x] Fixed App Store Connect ITMS validation failures for the watch-only container.
- [x] Released 2.2.1; tagged `v2.2.1` and the `v2.2` baseline.

### 🚀 Next Steps
- [ ] Review and edit `docs/PRD.md` (DRAFT; Strava and 3.0 scope questions), then merge the workflow PR.
- [ ] Trial the workflow on a small feature: default the distance unit from the device locale.
- [ ] On a real watch, confirm a full 20-second BLE log shares intact via Messages and Mail.
- [ ] Verify on real hardware: FTMS Control Point handshake, and that a saved ride keeps its Move ring calories.
- [ ] Decide the rest of the 3.0 scope (incl. keep/remove Strava) and trigger an Xcode Cloud build from `main`.
- [ ] Delete stale local branches: `diag/2.2.1-ble-trace`, `state-refresh-2.2.1-readiness`, `fix/2.2.1-reconnect-and-distance`, `port/2.2.1-ftms-fixes`, `fix/calorie-source-setting`, `ios-companion-strava-wip`, `ble-log-share-sheet`.

### 📋 Backlog / Later
- [ ] Whole-ride BLE logging behind a user-facing debug toggle.
- [ ] `didFailToConnect` fallback retry handling.
- [ ] FTMS resistance/incline control, now that the Control Point handshake exists.
- [ ] Restore local Strava credentials in `Config/Secrets.local.xcconfig` (blanked during the 2.2.1 CI work; secret since rotated).
- [ ] Add SwiftLint to `scripts/verify.sh` (needs approval: new tool).
- [ ] A few XCUITest flows (start → stop → summary) to replace the template UI tests.

### 🛑 Blockers & Known Issues
- None.
