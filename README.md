# CaPowHr - watchOS Cycling Workout App

A standalone watchOS app that connects to Bluetooth cycling sensors (Power, Cadence, and Fitness Machine) and uses the Apple Watch's internal heart rate sensor to record indoor cycling workouts. Features intelligent heart rate source selection, real-time distance tracking with multi-strategy estimation, and comprehensive workout data storage to Apple Health. Includes display-only mode when HealthKit permissions are limited.

## Features

- **Real-time Data Display**: Shows heart rate, cycling power, cadence, distance, and workout duration
- **Intelligent Heart Rate Selection**: Choose between Auto (prefers bike HR), Bike-only, or Watch-only heart rate sources
- **Multi-Strategy Distance Tracking**: Prioritizes FTMS total distance, falls back to CSC wheel-based calculation with auto-calibration, or integrates instantaneous speed
- **Energy Tracking**: Real-time calorie burn from FTMS expended energy or estimated from power data
- **Bluetooth Integration**: Connects to Fitness Machine Service (FTMS), cycling power meters, and cadence sensors
- **HealthKit Integration**: Saves comprehensive workout data including heart rate, power, cadence, distance, and calories
- **Display-Only Mode**: Continues to show live data even when HealthKit permissions are denied
- **Save/Discard Workflow**: Choose to save or discard workouts after stopping
- **BLE Diagnostic Logging**: Built-in protocol capture for troubleshooting sensor compatibility (debug builds only)
- **Standalone Operation**: Functions entirely on the Apple Watch without a companion iPhone app
- **Modern SwiftUI Interface**: Clean, intuitive design optimized for the Apple Watch

## Supported Sensors

The app connects to standard Bluetooth Low Energy (BLE) cycling sensors and extracts comprehensive workout data:

- **Fitness Machine Service (FTMS)**: Service UUID `0x1826`
  - Indoor Bike Data Characteristic `0x2AD2` (instantaneous power, cadence, speed, total distance, total energy, heart rate)
- **Cycling Power Meters**: Service UUID `0x1818`
  - Power Measurement Characteristic `0x2A63` (instantaneous power output)
- **Cycling Speed and Cadence Sensors**: Service UUID `0x1816`
  - CSC Measurement Characteristic `0x2A5B` (wheel revolutions for distance, crank revolutions for cadence)

**Data Extraction**: Combines data from multiple sensors for complete workout metrics including multi-strategy distance estimation and energy calculation from power output.

## Requirements

- Apple Watch Series 4 or later
- watchOS 11.5 or later
- Compatible Bluetooth cycling sensors

## Setup Instructions

1. **Open the project** in Xcode
2. **Select your Apple Watch** as the target device
3. **Build and run** the app on your Apple Watch
4. **Grant permissions** when prompted for HealthKit and Bluetooth access
5. **Connect your sensors** by starting a workout - the app will automatically scan for compatible devices

## Usage

1. **Launch the app** on your Apple Watch
2. **Configure settings** (optional, tap "Settings"):
   - Choose heart rate source: Auto (prefers bike), Bike-only, or Watch-only
3. **Prepare sensors**: Ensure cycling sensors are powered on and in pairing mode
4. **Connect sensors** (optional): Tap "Connect Sensors" to pre-connect devices before starting
5. **Tap "Start"** to begin the workout
6. **The app will automatically**:
   - Connect to available FTMS, power, and cadence sensors
   - Start recording heart rate data based on your preference
   - Display real-time metrics: HR, power, cadence, distance, and duration
7. **Monitor progress**: View live data during your workout
8. **Tap "Stop"** when finished
9. **Save or Discard**: Choose to save the workout to Apple Health or discard it

### Heart Rate Source Options

- **Auto (default)**: Prefers heart rate from bike sensors when available, falls back to Apple Watch
- **Bike**: Uses only bike-reported heart rate, shows zero if unavailable
- **Watch**: Uses only Apple Watch heart rate, ignores bike sensors

### Display-Only Mode

If HealthKit permissions are denied, the app continues to show live sensor data but workouts won't be saved to Apple Health. You can still use all sensor functionality for monitoring purposes.

## Data Saved to Apple Health

- **Workout Type**: Indoor Cycling
- **Heart Rate**: Continuous heart rate data (from Apple Watch or bike sensor based on user preference)
- **Cycling Power**: Instantaneous power output in watts
- **Cycling Cadence**: Crank revolutions per minute (RPM)
- **Distance**: Total distance traveled (from FTMS sensors, CSC wheel data, or estimated from speed)
- **Active Energy**: Calories burned (from FTMS expended energy or estimated from power output)
- **Workout Duration**: Start and end timestamps with total duration

## Technical Details

### Architecture
- **WorkoutManager**: Central coordinator managing workout lifecycle and UI state
- **BluetoothManager**: Handles BLE scanning, connection management, and sensor communication
- **HealthKitManager**: Manages HealthKit authorization, workout sessions, and data storage
- **SwiftUI Views**: Modern, reactive UI that updates in real-time based on published state
- **CoreBluetooth**: Low-level BLE communication with cycling sensors
- **HealthKit**: Comprehensive workout data storage and heart rate monitoring

### Key Components
- `WorkoutManager.swift`: Workout lifecycle coordination and state management
- `BluetoothManager.swift`: Bluetooth scanning, connection management, and sensor discovery
- `HealthKitManager.swift`: HealthKit integration, workout sessions, and sample storage
- `SensorDataParser.swift`: Comprehensive BLE data parsing for all cycling profiles (FTMS, Power, CSC)
- `DistanceEstimator.swift`: Speed-based distance integration for sensors without total distance
- `CSCDistanceEstimator.swift`: Wheel revolution-based distance with auto-calibrating circumference
- `WorkoutTimer.swift`: Workout duration timer with tick-based updates
- `WorkoutView.swift`: Real-time workout data display with heart rate, power, cadence, and distance
- `StartView.swift`: Pre-workout screen with sensor connection and settings access
- `SaveDiscardView.swift`: Post-workout save or discard workflow
- `SettingsView.swift`: User preferences including heart rate source selection
- `BLELogCaptureView.swift`: Diagnostic BLE logging for sensor troubleshooting (debug builds)
- `BluetoothLogManager.swift`: BLE protocol logging infrastructure
- `FeatureFlags.swift`: Build-specific feature toggles

### Distance Estimation Strategy

The app uses a prioritized approach for distance tracking:

1. **FTMS Total Distance** (preferred): If the bike reports cumulative distance via Indoor Bike Data, use it directly
2. **CSC Wheel Revolutions**: If wheel data is available from a CSC sensor, calculate distance using auto-calibrated wheel circumference (calibrated from FTMS speed when available)
3. **Speed Integration** (fallback): Integrate instantaneous speed over time when no cumulative source is available

### Energy Calculation Strategy

1. **FTMS Expended Energy** (preferred): If the bike reports total energy via Indoor Bike Data, use incremental deltas
2. **Power-Based Estimation** (fallback): Calculate energy from instantaneous power using joules-to-kilocalories conversion

## Permissions Required

The app requires the following permissions (configured in Xcode build settings):

- **NSHealthShareUsageDescription**: Read heart rate data during workouts
- **NSHealthUpdateUsageDescription**: Write workout data, power, cadence, distance, and calories to Apple Health
- **NSBluetoothAlwaysUsageDescription**: Connect to cycling power meters and cadence sensors

## Troubleshooting

- **Sensors not connecting**: Ensure sensors are powered on and in pairing mode. Try the "Connect Sensors" button before starting a workout.
- **No heart rate data**: Check that the Apple Watch is properly positioned on your wrist. Verify heart rate source setting matches your setup.
- **Workout not saving**: Verify HealthKit permissions are granted in the iPhone Health app under CaPowHr.
- **Distance not updating**: Some sensors don't report distance; the app will fall back to speed-based estimation.
- **App crashes**: Ensure you're running on a compatible Apple Watch model with watchOS 11.5+

## Development

This app is built using:
- SwiftUI for the user interface
- HealthKit for workout data management
- CoreBluetooth for sensor communication
- Modern Swift concurrency patterns

The codebase follows Apple's recommended patterns for watchOS development and maintains a clean separation of concerns between UI, business logic, and data management.

### Debug Features

In debug builds, additional features are available:
- **BLE Log Capture**: Record 20 seconds of sensor protocol data for diagnostic purposes (accessible from Settings)
