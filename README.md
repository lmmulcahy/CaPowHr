# CaPowHr — BLE Indoor Workout App for Apple Watch

A standalone watchOS app for recording indoor workouts from Bluetooth gym equipment — smart bikes, treadmills, and rowers — with power, cadence, heart rate, distance, and calories saved to Apple Health. Optional Strava sync via the iPhone companion app.

## Features

### Core recording
- **Multi-modality support**: Indoor cycling, treadmill run/walk, and rowing via FTMS
- **Real-time metrics**: Heart rate, power, cadence, speed, distance, incline, pace, stroke rate
- **Intelligent heart rate selection**: Auto (prefers equipment HR), equipment-only, or Apple Watch-only
- **Multi-strategy distance tracking**: FTMS total distance → CSC wheel revolutions → speed integration
- **Energy tracking**: FTMS expended energy or power-based estimation
- **HealthKit integration**: Workouts, HR, power, cadence, distance, speed, and active energy
- **Display-only mode**: Live data when HealthKit write permission is denied

### Daily-use polish
- **Start without pre-connecting**: Tap start and connect while the workout runs
- **Trusted devices**: Auto-reconnect to remembered BLE equipment
- **Units**: Miles or kilometers
- **Pause / resume** and **manual lap splits**
- **Post-workout summary** before save/discard (or auto-save)
- **Customizable metric layouts** per equipment type
- **Training zones** from max HR and FTP
- **Structured workout templates** (free, warm/work/cool, 4×4 intervals)

### Integrations
- **Strava** (optional, Settings): Upload after save when authenticated
- **iPhone companion**: Strava OAuth and token sync to watch
- **FIT export** from the workout summary screen
- **Equipment compatibility list** built from successful connections/workouts
- **Watch complications**: Quick-start your last workout type from the watch face

### Diagnostics
- **BLE log capture** for sensor compatibility troubleshooting (Settings)

## Supported Sensors

| Profile | Service UUID | Data |
|---------|------------|------|
| FTMS | `0x1826` | Bike, treadmill, rower metrics; total distance/energy when provided |
| Cycling Power | `0x1818` | Instantaneous watts |
| CSC | `0x1816` | Cadence and wheel-based distance |

## Requirements

- Apple Watch Series 4 or later
- watchOS 11.5 or later
- BLE indoor equipment (FTMS bike/treadmill/rower and/or power/cadence sensors)
- iPhone optional (recommended for Strava setup)

## Setup

1. Open the project in Xcode
2. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`
3. Add optional `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` from [Strava API settings](https://www.strava.com/settings/api)
4. Build **CaPowHr Watch App** to your Apple Watch
5. Grant HealthKit and Bluetooth permissions

## Usage

1. Launch CaPowHr on Apple Watch
2. Optional: **Settings** → heart rate source, units, save mode, Strava, trusted devices, training
3. Tap **Start Ride/Run/Walk/Row** — connect sensors first or let the app scan while the workout runs
4. Use **Pause**, **Lap**, and live zone feedback during the workout
5. Review the **workout summary**, export FIT if desired, then **Save** or **Discard**
6. Saved workouts appear in Apple Health; Strava uploads when enabled and connected

## Architecture

| Component | Role |
|-----------|------|
| `WorkoutManager` | Workout lifecycle coordinator |
| `BluetoothManager` | BLE scan, connect, trusted reconnect, parsing |
| `HealthKitManager` | Authorization, session, samples, pause/resume |
| `WorkoutStatsTracker` | Averages, laps, summary data |
| `StructuredWorkoutController` | Template phase timing |
| `FITExporter` | Post-workout FIT file generation |
| `CompatibilityStore` | Tested equipment tracking |
| `WatchConnectivityManager` | Strava token sync with iPhone companion |

## Data Saved to Apple Health

- Workout session (cycling, running, walking, or rowing — indoor)
- Heart rate, cycling power, cadence
- Distance (cycling or walking/running as appropriate)
- Running/walking speed when available
- Active energy

## App Store Positioning

> **CaPowHr is the Apple Watch app for people whose indoor workouts live on BLE equipment** — smart bikes, treadmills, and rowers — who want accurate power, cadence, heart rate, and distance in Apple Health without carrying a phone.

See [AppStoreCopy.md](AppStoreCopy.md) for listing text.

## Troubleshooting

- **Sensors not connecting**: Power on equipment; try **Connect Sensors** or trusted-device reconnect in Settings
- **No HR**: Check wrist fit and heart rate source setting
- **Workout not saving**: Enable Health write permissions for CaPowHr on iPhone → Health → Data Access
- **Strava**: Configure API keys in `Secrets.xcconfig` or use the iPhone companion app
- **Distance gaps**: Some sensors omit cumulative distance; CaPowHr falls back to CSC or speed integration

## Development

- SwiftUI + HealthKit + CoreBluetooth
- watchOS 11.5+
- Unit tests for parsers and distance estimators in `CaPowHr Watch AppTests`
