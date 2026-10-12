# CaPowHr — Architecture (current state)

Describes the code on `main` as of 2026-10-11 (`df2d468`). Keep it true: update
it in the same PR as any structural change. `/drift` audits it.

## Targets
| Target | Platform | Role |
|---|---|---|
| `CaPowHr Watch App` | watchOS 11.5+ | The app. Bundle `com.MulcahyHeavyIndustries.CaPowHr.watchkitapp`, version 3.0 |
| `CaPowHrComplicationsExtension` | watchOS | WidgetKit complication: "Start <last type>" deep link |
| `CaPowHr` | iOS | Empty App Store container for the watch-only app (no code) |
| `CaPowHr Watch AppTests` | watchOS | Swift Testing unit tests (parsers, estimators, energy, FIT) |
| `CaPowHr Watch AppUITests` | watchOS | Xcode-template launch tests only |

Scheme `CaPowHr Watch App` builds/tests everything. Swift 5 mode, no third-party dependencies.

## Directory conventions
- `CaPowHr Watch App/`: all app code, flat (no subfolders). Views are `*View.swift`.
- `Shared/`: `KeychainStore`, `StravaConfig` (shared when an iOS companion existed).
- `CaPowHrComplications/`: the widget extension.
- `Config/`: `Secrets.xcconfig` (tracked, blank) includes gitignored `Secrets.local.xcconfig` (real Strava keys).
- `docs/`: PRD, this file, decisions, `specs/<feature>.md`, `drift/`.
- `scripts/`, `.githooks/`, `.claude/`: workflow tooling (see `docs/WORKFLOW.md`).
- **Xcode project uses folder-synced groups** (`PBXFileSystemSynchronizedRootGroup`,
  objectVersion 77). Files added on disk join their target automatically, so
  `project.pbxproj` rarely changes and parallel worktrees rarely conflict on it.
  No XcodeGen/Tuist.

## Data flow
```
BLE peripheral ─notify─► BluetoothManager ─parse─► *SensorParser / BLEDataReader
                                │ delegate (BluetoothManagerDelegate)
                                ▼
HealthKit ◄──samples── HealthKitManager ◄──── WorkoutManager (ObservableObject, @Published state)
   │  HR/energy (delegate)        ▲                 │  + WorkoutTimer, WorkoutStatsTracker,
   └──────────────────────────────┘                 │    DistanceEstimator, CSCDistanceEstimator,
                                                    │    EnergyOwnership
                                                    ▼
                                         SwiftUI views (ContentView switches screens)
                                                    │ after save
                                                    ▼
                                StravaUploader → StravaClient → Strava API
```
- `CaPowHr_Watch_AppApp` owns one `WorkoutManager` (environment object) and
  handles the `capowhr://start?type=` deep link from the complication.
- `ContentView` is a state machine over `WorkoutManager` flags:
  summary → awaiting save → active workout (Bike/Treadmill/Rower view by type) → `StartView`.
- `WorkoutManager` (~950 lines) is the coordinator: workout lifecycle, scan/connect,
  metric routing, HR source selection, distance strategy, calorie ownership,
  stale-metric zeroing (5 s), stop/save/discard.
- `BluetoothManager`: two-phase scan (unfiltered with RSSI, then narrowed to
  FTMS/CP/CSC after 5 s), connects, discovers only the characteristics used,
  subscribes, writes the **FTMS Control Point** (Request Control 0x00,
  Start/Resume 0x07), auto-reconnects trusted devices after drops.
- `HealthKitManager`: `HKWorkoutSession` + `HKLiveWorkoutBuilder`. Disables
  automatic collection of HR and distance (app writes its own samples) but
  leaves active energy to Apple unless the machine takes ownership.
- Pure, unit-tested logic: `CyclingSensorParser`, `TreadmillSensorParser`,
  `RowerSensorParser`, `BLEDataReader`, `DistanceEstimator`,
  `CSCDistanceEstimator`, `EnergyOwnership`, `FITExporter`, `DistanceFormatter`.

## Data model & persistence
| Store | Key / item | Owner | Format |
|---|---|---|---|
| UserDefaults.standard | `heartRateSource` | `HeartRateSource` | `"auto"`, `"bike"` (=Equipment, legacy raw value), `"watch"` |
| | `distanceUnit` | `AppSettings` | `"miles"` / `"kilometers"` (default miles) |
| | `calorieSource` | `AppSettings` | `"appleWatch"` / `"equipment"` |
| | `workoutSaveMode` | `AppSettings` | `"askEveryTime"` / `"autoSave"` |
| | `lastWorkoutType` | `AppSettings` | `"indoorCycle"`/`"indoorRun"`/`"indoorWalk"`/`"indoorRow"` |
| | `fitExportEnabled`, `stravaSyncEnabled` | `@AppStorage` | Bool |
| | `bikeMetricsLayout`, `treadmillMetricsLayout`, `rowerMetricsLayout` | `WorkoutMetricsLayout` | `[String]` of 4 metric raw values |
| | `trustedBLEDevices` | `TrustedDeviceStore` | JSON `[TrustedDevice]` (id, name, deviceType, lastConnectedAt) |
| App Group `group.com.MulcahyHeavyIndustries.CaPowHr` | `lastWorkoutType` | mirrored for the complication | same raw values |
| Keychain service `com.capowhr.strava` | `strava_access_token`, `strava_refresh_token`, `strava_expires_at`, `strava_athlete_id` | `StravaAuthManager` via `KeychainStore` | strings |
| HealthKit (write) | workout; heartRate, cyclingPower, cyclingCadence, activeEnergyBurned, distanceCycling, distanceWalkingRunning, runningSpeed, walkingSpeed | `HealthKitManager` | HK samples |
| Files | `Documents/BLELogs/ble-session-<ts>.jsonl` | `BluetoothLogManager` | JSON Lines `BLELogRecord` |
| Files | `tmp/CaPowHr-<epoch>.fit` | `FITExporter` | minimal FIT activity |

No migrations exist; persistence compatibility relies on keeping raw values stable.

## External APIs / services
- **BLE GATT**: services 0x1826 FTMS, 0x1818 Cycling Power, 0x1816 CSC;
  characteristics 0x2AD2 Indoor Bike, 0x2ACD Treadmill, 0x2AD1 Rower,
  0x2A63 Power, 0x2A5B CSC, 0x2AD9 FTMS Control Point (write), 0x2ADA FTMS Status.
  Reference: `FTMS_v1.0.pdf` in the repo root.
- **Strava**: OAuth via `ASWebAuthenticationSession` on the watch
  (`capowhr://strava-callback`, scope `activity:write`); token exchange/refresh
  at `/oauth/token`; `POST /api/v3/activities` (manual activity, not a FIT
  upload). Client ID/secret come from `Secrets.local.xcconfig` → Info.plist.
- **HealthKit**, **WidgetKit**. No backend of our own.

## Build / deploy
- Local: `scripts/verify.sh` (simulator by UDID; see CLAUDE.md).
- Release: Xcode Cloud (workflow configured in App Store Connect; manifest at
  `CaPowHr.xcodeproj/xcshareddata/xcodecloud/`), builds `main` from a clean
  checkout with the blank tracked `Secrets.xcconfig`. No GitHub Actions.
- Background modes: `bluetooth-central` (UIBackgroundModes), `workout-processing` (WKBackgroundModes).
- Release trains so far: `release/2.2.1` (shipped, tag `v2.2.1`); `main` = 3.0.

## Known debt (observed, not judged)
- `WorkoutManager` is large and untested directly; tests cover the pure helpers.
- Unit tests live in one 463-line file; new features add their own files.
- 8 compiler warnings (deprecated `onChange(of:perform:)`, an unused variable in `StravaUploader`).
- UI tests are the Xcode template (launch only). If UI regressions become a
  problem, consider a few XCUITest flows (start → stop → summary) or
  snapshot tests. That would need a dependency for snapshots, so ask first.
