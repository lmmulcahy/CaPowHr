# CaPowHr
**Last Updated:** 2026-08-08
**Status:** active

### 🎯 Current Phase
Split into two release trains. `main` becomes **3.0** — the multi-modality feature release (Strava, iPhone companion, complications, trusted devices, metric layouts, FIT export) plus this summer's bug fixes. Separately, **2.2.1** is a minimal hotfix cut from the 2.2 baseline so the background-recording bug reaches users without waiting on 3.0 review.

### ✅ Just Completed
- [x] Traced three field reports — public #22 (calories far too low), #26 (distance ~60% of console), #27 (workout auto-stops mid-ride) — to one root cause: the watch target set `INFOPLIST_KEY_UIBackgroundModes`, an iOS key Xcode ignores for watchOS, so the built Info.plist declared no background modes and watchOS suspended the app whenever it was not frontmost
- [x] Hybrid energy ownership (PR #6): Apple's HR-informed estimate owns `activeEnergyBurned` unless the machine's FTMS Expended Energy counter demonstrably increments. New `EnergyOwnership` type, unit tested
- [x] Confirmation before ending a workout (PR #7) — Stop ends the `HKWorkoutSession` irreversibly, so a mis-tap lost the ride
- [x] App Store metadata and compliance prep merged (PR #5)
- [x] `release/2.2.1` branch cut from 2.2: WKBackgroundModes fix, FTMS More Data parser fix, privacy manifest, export compliance, version 2.2.1 build 1. Verified in the built product; 18 tests pass
- [x] Relabelled `main` from 2.3 to 3.0 and updated the What's New copy

### 🚀 Next Steps
- [ ] Review and merge the 3.0 relabel PR
- [ ] Submit **2.2.1** to App Store review first — it is the urgent one
- [ ] Hardware validation before submitting either: recording continues wrist-down and through a notification; a machine reporting Expended Energy hands over to machine-owned energy; Grupetto stays on Apple's estimate and the Move ring does not drop on save
- [ ] Submit 3.0 once 2.2.1 is out and the hardware checks pass
- [ ] App Store Connect by hand for 3.0: App Privacy questionnaire (Strava data sharing), fresh screenshots, review notes on 4.8
- [ ] Reply to reporters on public #22, #26, #27 and the Grupetto/OpenPelo report

### 📋 Backlog / Later
- [ ] No git tags exist. Tag the 2.2 baseline (`5b58569`) and each release going forward — this hotfix had to be cut from a bare SHA
- [ ] Investigate BLE Log Capture upload — it creates a GitHub issue with a PAT baked in at build time via `Config/Secrets.xcconfig`. Auto-created log issues stop dead at 2026-01-30 and a recent reporter could not get the feature to work, so the token has likely expired
- [ ] Reconsider `DistanceEstimator` discarding any interval longer than 5s — one-directional under-count, which the background bug used to trigger constantly
- [ ] Stop re-writing Apple's own HR samples into the builder in Apple-Watch HR mode (redundant and lossy)
- [ ] Wait for the session to reach `.ended` before calling `endCollection` — can truncate trailing data
- [ ] Surface a mid-workout session failure in the active-workout UI; the error alert currently lives only on StartView
- [ ] Stop button label wraps to "Sto p" on the 46mm face

### 🛑 Blockers & Known Issues
- Simulator coverage is limited: there is no BLE, and the start button is gated on a connected sensor, so driving the workout screens requires temporarily lifting that gate locally. The FTMS paths and the background-execution fix can only be confirmed on real hardware with a real machine.
- `release/2.2.1` must never be merged into `main` — it is a release branch off the 2.2 baseline, and merging it would drag `main` back to 2.2-era code. Its two fix commits were cherry-picked *from* `main` and are already there.
