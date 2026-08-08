# CaPowHr
**Last Updated:** 2026-08-08
**Status:** active

### 🎯 Current Phase
Closing out v2.3 of the standalone watchOS BLE indoor-workout app before App Store submission. Working through the open field reports: most of them turned out to share a single root cause that is already fixed on main.

### ✅ Just Completed
- [x] Traced three separate field reports — public #22 (calories far too low), #26 (distance ~60% of console), #27 (workout auto-stops mid-ride) — to one root cause: the watch target set `INFOPLIST_KEY_UIBackgroundModes`, an iOS key Xcode ignores for watchOS, so the built Info.plist declared no background modes and watchOS suspended the app whenever it was not frontmost. Fixed post-2.2 by `9791034`; verified `WKBackgroundModes` is present in the built product.
- [x] Hybrid energy ownership (PR #6, merged): Apple's HR-informed estimate owns `activeEnergyBurned` by default; a machine takes over only once its FTMS Expended Energy counter is seen to actually increment. New `EnergyOwnership` type, unit tested.
- [x] Removed the power-integration energy write that reported mechanical work as kcal (`joules / 4184`, ~4x too low)
- [x] Wired `HKLiveWorkoutBuilderDelegate` and `HKWorkoutSessionDelegate` — the session previously had no delegate, so failures were invisible
- [x] Confirmation before ending a workout (PR #7): Stop ends the `HKWorkoutSession` irreversibly, so a mis-tap lost the ride

### 🚀 Next Steps
- [ ] Review and merge PR #7 (`confirm-before-stopping-workout`)
- [ ] Merge open PR #5 (branch `trim-unwanted-v2.3-features`: App Store metadata + compliance prep)
- [ ] Hardware validation before submitting: recording continues wrist-down and through a notification; a machine reporting Expended Energy hands over to machine-owned energy; Grupetto stays on Apple's estimate and the Move ring does not drop on save
- [ ] Submit v2.3 to App Store review
- [ ] Reply to the reporters on public #22, #26, #27 and the Grupetto/OpenPelo report; #26 also asked for a distance unit setting, which `2eb4741` added for 2.3

### 📋 Backlog / Later
- [ ] Investigate BLE Log Capture upload — it creates a GitHub issue with a PAT baked in at build time via `Config/Secrets.xcconfig`. Auto-created log issues stop dead at 2026-01-30 and a recent reporter could not get the feature to work, so the token has likely expired.
- [ ] Reconsider `DistanceEstimator` discarding any interval longer than 5s — one-directional under-count, which the background bug used to trigger constantly
- [ ] Stop re-writing Apple's own HR samples into the builder in Apple-Watch HR mode (redundant and lossy)
- [ ] Wait for the session to reach `.ended` before calling `endCollection`, rather than ending both immediately — can truncate trailing data
- [ ] Surface a mid-workout session failure in the active-workout UI; the error alert currently lives only on StartView
- [ ] Stop button label wraps to "Sto p" on the 46mm face

### 🛑 Blockers & Known Issues
- Simulator coverage is limited: there is no BLE, and the start button is gated on a connected sensor. Driving the workout screens at all requires temporarily lifting that gate locally. The FTMS paths and the background-execution fix can only be confirmed on real hardware with a real machine.
