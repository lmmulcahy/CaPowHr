# CaPowHr - watchOS Cycling Workout App

A standalone watchOS app that connects to Bluetooth cycling sensors (Power and Cadence) and uses the Apple Watch's internal heart rate sensor to record indoor cycling workouts. All data is saved to Apple Health as a single workout.

## Features

- **Real-time Data Display**: Shows heart rate, cycling power, cadence, and workout duration
- **Bluetooth Integration**: Connects to standard cycling power meters and cadence sensors
- **HealthKit Integration**: Saves all workout data to Apple Health
- **Standalone Operation**: Functions entirely on the Apple Watch without a companion iPhone app
- **Modern SwiftUI Interface**: Clean, intuitive design optimized for the Apple Watch

## Supported Sensors

The app connects to standard Bluetooth Low Energy (BLE) cycling sensors:

- **Cycling Power Meters**: Service UUID `0x1818` (Power Measurement Characteristic `0x2A63`)
- **Cycling Speed and Cadence Sensors**: Service UUID `0x1816` (CSC Measurement Characteristic `0x2A5B`)

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
2. **Ensure your cycling sensors are powered on** and in pairing mode
3. **Tap "Start"** to begin the workout
4. **The app will automatically**:
   - Connect to available power meters and cadence sensors
   - Start recording heart rate data
   - Display real-time metrics
5. **Tap "Stop"** when finished to save the workout to Apple Health

## Data Saved to Apple Health

- Workout type: Indoor Cycling
- Heart rate data (from Apple Watch)
- Cycling power data (from power meter)
- Cycling cadence data (from cadence sensor)
- Workout duration and timestamps

## Technical Details

### Architecture
- **WorkoutManager**: Central `ObservableObject` managing all app state, HealthKit, and Bluetooth interactions
- **SwiftUI Views**: Modern, reactive UI that updates in real-time
- **CoreBluetooth**: Handles BLE communication with cycling sensors
- **HealthKit**: Manages workout sessions and data storage

### Key Components
- `WorkoutManager.swift`: Main business logic and data management
- `ContentView.swift`: Primary UI with real-time data display
- `Info.plist`: Required permissions for HealthKit and Bluetooth

## Permissions Required

The app requires the following permissions (configured in Info.plist):

- **NSHealthShareUsageDescription**: Read heart rate data
- **NSHealthUpdateUsageDescription**: Write workout data to Apple Health
- **NSBluetoothAlwaysUsageDescription**: Connect to cycling sensors

## Troubleshooting

- **Sensors not connecting**: Ensure sensors are powered on and in pairing mode
- **No heart rate data**: Check that the Apple Watch is properly positioned on your wrist
- **Workout not saving**: Verify HealthKit permissions are granted
- **App crashes**: Ensure you're running on a compatible Apple Watch model

## Development

This app is built using:
- SwiftUI for the user interface
- HealthKit for workout data management
- CoreBluetooth for sensor communication
- Modern Swift concurrency patterns

The codebase follows Apple's recommended patterns for watchOS development and maintains a clean separation of concerns between UI, business logic, and data management.
