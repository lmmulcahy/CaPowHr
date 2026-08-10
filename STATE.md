# CaPowHr
**Last Updated:** 2026-08-09
**Status:** active

### 🎯 Current Phase
Two release trains. `main` is **3.0** (multi-modality features plus this summer's fixes); **2.2.1** is a minimal hotfix cut from the 2.2 baseline. Both are held pending one more hardware ride, because on-device logging overturned the original diagnosis of the field reports.

### ✅ Just Completed
- [x] Instrumented a device build (whole-ride BLE logging plus a 1 Hz heartbeat) and rode it. The log settled what three field reports could not.
- [x] **The real defect: the app never reconnects after a mid-workout drop.** Steady ~4 Hz packets for 174s, bike disconnects at 2:54, then nothing for the remaining 1:49. On disconnect the manager only restarted a scan, and `didDiscover` deliberately does not auto-connect — it feeds a device picker that is not on screen during a workout. Fixed in PR #10 by re-issuing a pending `connect()`.
- [x] 174 of 283 seconds carried data — 62% of the ride, closely matching the ~60% distance shortfall reported in public #26
- [x] Confirmed the app is **not** suspended during workouts: 283 heartbeats across a 283-second session, no gaps. The earlier suspension diagnosis was wrong.
- [x] `bluetooth-central` in `UIBackgroundModes` (PR #9) — `workout-processing` keeps the app running, this keeps Core Bluetooth delivering while backgrounded
- [x] Both fixes cherry-picked onto `release/2.2.1`; suite green on both trains
- [x] Earlier: hybrid energy ownership (PR #6), stop confirmation (PR #7), 3.0 relabel (PR #8)

### 🚀 Next Steps
- [ ] Review and merge PR #9 and PR #10
- [ ] **Verification ride on the instrumented build**: confirm the log shows a `connect` after a `disconnect`, and `rx` resuming. That is the one thing still unproven.
- [ ] Submit **2.2.1** once the reconnect is confirmed on hardware
- [ ] Submit 3.0 after, with the App Store Connect work (privacy questionnaire, screenshots, review notes)
- [ ] Reply to reporters on public #22, #26, #27 and the Grupetto/OpenPelo report — the cause is not what the earlier analysis said

### 📋 Backlog / Later
- [ ] Delete throwaway branch `diag/2.2.1-ble-trace` once verification is done — it carries diagnostic logging that must never ship
- [ ] Whole-ride BLE logging behind a user-facing debug toggle. It was decisive here, and the existing 20-second capture could never have found this.
- [ ] No git tags exist. Tag the 2.2 baseline (`5b58569`) and each release going forward.
- [ ] `didFailToConnect` still falls back to scanning, so a failed *reconnect* abandons the retry. Rare with a pending connect, but a real edge.
- [ ] Investigate BLE Log Capture upload — PAT baked in at build time via `Config/Secrets.xcconfig`; auto-created log issues stop dead at 2026-01-30
- [ ] Reconsider `DistanceEstimator` discarding intervals longer than 5s
- [ ] Stop re-writing Apple HR samples into the builder in Apple-Watch HR mode
- [ ] Wait for the session to reach `.ended` before calling `endCollection`
- [ ] Surface a mid-workout session failure in the active-workout UI
- [ ] Stop button label wraps to "Sto p" on the 46mm face

### 🛑 Blockers & Known Issues
- The reconnect fix is **unverified on hardware**. It cannot be unit tested — `BluetoothManager` needs live Core Bluetooth, and the suite only covers pure helpers.
- Device connectivity for `devicectl` is flaky. The watch drops from `connected` to `available (paired)` whenever it sleeps or leaves range, and installs only succeed while `connected`.
- The simulator cannot exercise any of this: no BLE, and the start button is gated on a connected sensor.
- `release/2.2.1` must never be merged into `main` — it is a release branch off the 2.2 baseline. Its commits were cherry-picked *from* `main`.
