# CaPowHr — Claude rulebook

Standalone Apple Watch app (watchOS 11.5+) that records indoor workouts from BLE
gym equipment (FTMS bikes/treadmills/rowers, power, CSC) into Apple Health.
Product: `docs/PRD.md`. How the loop works: `docs/WORKFLOW.md`.

## Commands
- **Verify (the gate):** `scripts/verify.sh` (build + typecheck + lint + unit tests, ~80s).
  `VERIFY_UI=1 scripts/verify.sh` adds UI tests. Evidence → `.claude/last-verify.log`.
- Build: `xcodebuild build-for-testing -project CaPowHr.xcodeproj -scheme "CaPowHr Watch App" -destination id=<watch sim udid>`
- Unit tests: `... test-without-building -only-testing:"CaPowHr Watch AppTests"`
- Typecheck = the build. Lint: none configured (SwiftLint not installed).
- Pick simulators by **UDID**, not name; two watchOS 27.0 runtimes make names ambiguous. Override: `VERIFY_DEST=id=<udid>`.
- New clone/worktree: `scripts/setup.sh` (installs `.githooks/`).

## Architecture boundaries (details: `docs/ARCHITECTURE.md`)
- Use existing frameworks only (SwiftUI, HealthKit, CoreBluetooth, WidgetKit, AuthenticationServices). **Ask before adding any dependency.**
- `WorkoutManager` is the single coordinator; views don't talk to `BluetoothManager`/`HealthKitManager` directly.
- BLE byte parsing stays in pure `*SensorParser` / `BLEDataReader` types with unit tests.
- Put new testable logic in pure types (like `EnergyOwnership`, `DistanceEstimator`), not in views or managers.
- Folder-synced Xcode groups: add files on disk; don't hand-edit `project.pbxproj`.
- Watch-only app. The `CaPowHr` iOS target is an empty App Store container; don't add code to it.

## Change rules
- **Quick Path** (typo, one-line fix, copy change, obvious bug, no risk path): implement → `scripts/verify.sh` → commit.
- **Full Path** (any feature, behavior change, persistence change, or risk-path touch): `/spec <feature>` → human approves → `/build <feature>` → `/ship <feature>`.
- Feature branch + PR for non-trivial work; never merge your own PR. Stage only files you changed.
- Never use `--no-verify`. The hooks block it anyway.

## Risk paths: any diff here goes in the PR's ⚠️ Human eyeball section
- **Auth/credentials/keychain:** `Shared/KeychainStore.swift`, `Shared/StravaConfig.swift`, `CaPowHr Watch App/StravaAuthManager.swift`, `Config/*.xcconfig`, `**/*.entitlements`
- **Persistence formats** (UserDefaults keys/raw values, App Group, Codable): `CaPowHr Watch App/AppSettings.swift`, `TrustedDeviceStore.swift`, `WorkoutMetricsLayout.swift`, `WorkoutManager.swift` (`HeartRateSource` raw values), `CaPowHrComplications/`
- **Health data written / file formats:** `CaPowHr Watch App/HealthKitManager.swift`, `FITExporter.swift`, `BluetoothLogManager.swift`
- **Deletes user data:** `HealthKitManager.discardWorkout`, `WorkoutManager.discardCurrentWorkout`, `StravaAuthManager.logout`, `TrustedDeviceStore.forget`, `KeychainStore.delete`
- **Network/device contracts:** `StravaClient.swift`, `StravaUploader.swift`, `StravaAuthManager.swift`; BLE: `BluetoothManager.swift` (incl. FTMS Control Point writes), `*SensorParser.swift`, `BLEDataReader.swift`, `CSCDistanceEstimator.swift`
- **App config/privacy:** `**/Info.plist`, `**/PrivacyInfo.xcprivacy`, `CaPowHr.xcodeproj/` (build settings, schemes)
- **Payments/IAP:** none in this app.
- **Workflow guardrails:** `scripts/`, `.githooks/`, `.claude/` (hooks, agents, skills, test-lock)

## Testing rules
- Write tests from acceptance criteria **before** implementation; show them failing; human locks them.
- New feature tests go in `CaPowHr Watch AppTests/<Feature>Tests.swift` (Swift Testing). Name tests after ACs.
- **Never weaken, delete, or skip an existing assertion** to make a test pass. If a test seems wrong, stop and say so.
- Files in `.claude/test-lock` are uneditable (hook-enforced). Only the human runs `scripts/lock-tests.sh` / `scripts/unlock-tests.sh`.

## Docs duty
When a task finishes: update `docs/specs/<feature>.md` (tick plan boxes, record Deviations).
Append to `docs/decisions.md` if a real decision was made. Update `docs/ARCHITECTURE.md` if structure changed.
Update `STATE.md` at session end (snapshot, not log).

## Lessons (max ~10, one line each; prune old ones)
- Reproduce a bug on the real failure (often a device BLE log) before fixing; first guesses here have been wrong.
- `HeartRateSource.bike` raw value `"bike"` is stored on users' watches; renaming the case label is fine, the raw value is not.
- The complication reads `lastWorkoutType` from the App Group, so write it through `AppSettings.lastWorkoutType` only.
- FTMS fields are optional per flags bit; a missing field must not shift later offsets. Test with real captured hex frames.
- Apple owns calories by default (Move ring); machine energy only when the user picks Equipment.
- Real-device behavior (BLE background, HealthKit save) can't be proven in the simulator; say so in the PR Dogfood notes.
