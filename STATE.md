# CaPowHr
**Last Updated:** 2026-08-08
**Status:** active

### 🎯 Current Phase
Closing out v2.3 of the standalone watchOS BLE indoor-workout app before App Store submission. A user bug report against shipped 2.2 (Grupetto/OpenPelo on an original Peloton Bike) surfaced a calorie-recording defect that 2.3 would not have fixed on its own.

### ✅ Just Completed
- [x] Diagnosed the 2.2 field report: the watch target set `INFOPLIST_KEY_UIBackgroundModes` (an iOS key Xcode ignores for watchOS), so the built Info.plist declared no background modes and watchOS suspended the app whenever it was not frontmost — freezing BLE data and starving HealthKit energy collection. Already fixed post-2.2 by `9791034`; verified `WKBackgroundModes` is present in the built product.
- [x] Hybrid energy ownership: Apple's HR-informed estimate owns `activeEnergyBurned` by default; a machine takes over only once its FTMS Expended Energy counter is seen to actually increment (new `EnergyOwnership` type, unit tested)
- [x] Removed the power-integration energy write that reported mechanical work as kcal (`joules / 4184`, ~4x too low); the corrected constant now applies only to the display-only-mode estimate
- [x] Wired `HKLiveWorkoutBuilderDelegate` and `HKWorkoutSessionDelegate` — the session previously had no delegate, so failures were invisible
- [x] Removed unwanted v2.3 features (training-zone banner/zones, structured workouts, tested-equipment log)
- [x] Added privacy manifests for watch and iOS targets; declared export compliance

### 🚀 Next Steps
- [ ] Review and merge PR for `fix-workout-calorie-source`
- [ ] Merge open PR #5 (branch `trim-unwanted-v2.3-features`: App Store metadata + compliance prep)
- [ ] Hardware validation before submitting: recording continues wrist-down and through a notification; a machine reporting Expended Energy hands over to machine-owned energy; Grupetto stays on Apple's estimate and the Move ring does not drop on save
- [ ] Submit v2.3 to App Store review
- [ ] Reply to the bug reporter

### 📋 Backlog / Later
- [ ] Investigate BLE Log Capture upload — it creates a GitHub issue with a PAT baked in at build time via `Config/Secrets.xcconfig`; a revoked or expired token would fail silently for every App Store user (the reporter could not get it to work)
- [ ] Stop re-writing Apple's own HR samples into the builder in Apple-Watch HR mode (redundant and lossy)
- [ ] Wait for the session to reach `.ended` before calling `endCollection`, rather than ending both immediately — can truncate trailing data
- [ ] Surface a mid-workout session failure in the active-workout UI; the error alert currently lives only on StartView

### 🛑 Blockers & Known Issues
- The hybrid energy handover cannot be exercised in the simulator: there is no BLE, and the start button is gated on a connected sensor. Simulator verification covers the build, the unit tests, and app launch only — the FTMS paths need a real machine.
