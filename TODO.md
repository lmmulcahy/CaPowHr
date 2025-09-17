# CaPowHr Codebase Review & TODO

## High-Level Architecture Review

### Strengths ✅
- **Clean SwiftUI Architecture**: Good separation between UI views and business logic via `WorkoutManager`
- **Proper ObservableObject Pattern**: Reactive UI updates through `@Published` properties
- **Comprehensive Integration**: Well-integrated HealthKit and CoreBluetooth functionality
- **Modern SwiftUI Patterns**: Proper use of `NavigationStack`, view composition, and state management
- **Good Documentation**: Clear README with usage instructions and technical details

### Areas for Improvement 🔄

#### 1. Monolithic WorkoutManager Class
- **Issue**: Single 687-line class handling multiple responsibilities
- **Impact**: Difficult to maintain, test, and debug
- **Solution**: Break into smaller, focused classes:
  - `BluetoothManager` for sensor communication
  - `HealthKitManager` for workout session management
  - `WorkoutTimer` for duration tracking
  - Keep `WorkoutManager` as coordinator

#### 2. State Management Complexity
- **Issue**: Mixed state handling between UI state and data state
- **Solution**: Consider using a more structured state management pattern (e.g., TCA, Redux-like)

## Critical Bugs & Issues 🐛

### 1. Memory Management
- **Location**: `WorkoutManager.stopWorkoutTimer()` line 253
- **Issue**: `workoutDuration` reset to 0 when stopping timer, losing workout data
- **Fix**: Only reset duration in `discardCurrentWorkout()`, not `stopWorkoutTimer()`

### 2. Bluetooth Connection Race Conditions
- **Location**: `WorkoutManager.startScanning()` lines 261-281
- **Issue**: No check if already connected to prevent duplicate connections
- **Fix**: Add connection state validation before attempting new connections

### 3. Heart Rate Query Lifecycle
- **Location**: `WorkoutManager.stopHeartRateQuery()` line 233
- **Issue**: Query stopped but not properly cleaned up if called multiple times
- **Fix**: Add nil check and ensure single cleanup

### 4. Peripheral Memory Leak
- **Location**: `WorkoutManager.connectedPeripherals` array
- **Issue**: Strong references to peripherals without proper cleanup
- **Fix**: Use weak references or ensure proper cleanup in all exit paths

### 5. Concurrency Issues
- **Location**: Multiple Bluetooth delegate methods
- **Issue**: UI updates not consistently dispatched to main queue
- **Fix**: Wrap all `@Published` property updates in `DispatchQueue.main.async`

### 6. Error Handling Gaps
- **Location**: Throughout `WorkoutManager`
- **Issue**: Many operations lack proper error handling and user feedback
- **Fix**: Add comprehensive error handling with user-visible error states

## Code Quality & Best Practices 📝

### Immediate Fixes Needed

#### 1. Magic Numbers & Hardcoded Values
```swift
// Lines 274-278: Replace magic timing values
let BLUETOOTH_SCAN_TIMEOUT = 5.0
let HEART_RATE_QUERY_LIMIT = HKObjectQueryNoLimit

// Line 272: Make scan options configurable
let SCAN_OPTIONS = [CBCentralManagerScanOptionAllowDuplicatesKey: false]
```

#### 2. Inconsistent Naming
- `startScanningForTesting()` - remove "ForTesting" suffix for production code
- `ftmsServiceUUID` vs `cyclingPowerServiceUUID` - standardize naming convention

#### 3. Missing Input Validation
```swift
// Add validation for data parsing methods
private func parsePowerData(_ data: Data) {
    guard data.count >= 2 else { 
        handleDataError("Power data too short")
        return 
    }
    // ... existing code
}
```

#### 4. Force Unwrapping
- **Location**: Line 230 `healthStore.execute(heartRateQuery!)`
- **Fix**: Use proper optional handling

### Code Organization

#### 1. Extract Constants
```swift
struct BluetoothConstants {
    static let cyclingPowerServiceUUID = CBUUID(string: "1818")
    static let cyclingSpeedCadenceServiceUUID = CBUUID(string: "1816")
    // ... etc
}
```

#### 2. Protocol Conformance
Move delegate implementations to separate extensions for better organization (already partially done)

#### 3. Add Computed Properties
```swift
var isConnectedToDevices: Bool {
    !connectedDevices.isEmpty
}

var formattedHeartRate: String {
    heartRate > 0 ? "\(Int(heartRate))" : "--"
}
```

## Performance & Memory Issues ⚡

### 1. Timer Management
- **Issue**: Multiple timers created without proper cleanup
- **Solution**: Use single timer manager with lifecycle management

### 2. Bluetooth Scanning Strategy
- **Issue**: Broad scanning (line 271) before specific service scanning
- **Solution**: Start with specific services, fallback to broad scan only if needed

### 3. Data Processing Overhead
- **Issue**: Complex parsing in main Bluetooth callback thread
- **Solution**: Move data parsing to background queue, only update UI on main queue

### 4. State Update Frequency
- **Issue**: Potential UI update spam from high-frequency sensor data
- **Solution**: Implement throttling/debouncing for UI updates

## Testing Strategy 🧪

### Current State
- **Unit Tests**: Empty test file with no actual tests
- **UI Tests**: Basic launch test only

### Recommendations
1. **Unit Tests Needed**:
   - Data parsing methods (`parsePowerData`, `parseCadenceData`, `parseFTMSData`)
   - Duration formatting (`formatDuration`)
   - State transitions in `WorkoutManager`

2. **Integration Tests**:
   - HealthKit authorization flow
   - Bluetooth discovery and connection simulation

3. **UI Tests**:
   - Workout start/stop flow
   - Data display validation
   - Error state handling

## Security & Privacy 🔒

### 1. Bluetooth Security
- **Issue**: No device authentication or pairing validation
- **Recommendation**: Add device allowlist or pairing confirmation

### 2. Data Privacy
- **Issue**: No data sanitization before HealthKit storage
- **Recommendation**: Validate sensor data ranges before storage

### 3. Permission Handling
- **Issue**: Basic permission handling without graceful degradation
- **Recommendation**: Add proper permission state management and user guidance

## Immediate Action Items (Priority Order) 📋

### High Priority 🔴
1. **Fix memory leak in timer management** (lines 241-254)
2. **Add missing HealthKit data storage** (distance, calories) - major functionality gap
3. **Add proper error handling** throughout `WorkoutManager`
4. **Fix concurrent access issues** in Bluetooth delegates
5. **Validate data parsing** edge cases

### Medium Priority 🟡
1. **Extract Bluetooth logic** to separate manager class
2. **Add comprehensive unit tests** for data parsing
3. **Implement proper state management** patterns
4. **Add input validation** for all parsing methods

### Low Priority 🟢
1. **Refactor UI styling** into reusable components
2. **Add accessibility support** for VoiceOver
3. **Implement data export** functionality
4. **Add workout history** tracking

## Architecture Recommendations 🏗️

### 1. Modular Architecture
```
WorkoutCoordinator
├── BluetoothManager
├── HealthKitManager  
├── WorkoutTimer
└── DataProcessor
```

### 2. Protocol-Based Design
```swift
protocol SensorDataProvider {
    func startCollecting()
    func stopCollecting()
    var currentValue: Double { get }
}
```

### 3. State Machine
Implement formal state machine for workout lifecycle:
- Idle → Scanning → Connected → Active → Stopping → Complete

## HealthKit Data Storage Issues 📊

### Missing HealthKit Data Storage
Currently collecting but **NOT storing** to HealthKit:

#### 1. Distance Data ❌
- **Issue**: `distanceMeters` collected from FTMS data (line 462) but no `addDistanceSample()` method
- **Missing Permission**: `.distanceCycling` not in `typesToWrite` (line 73-79)
- **Fix**: Add distance storage method and permission

#### 2. Active Energy Burned ❌  
- **Issue**: Permission requested (line 78) but no calculation or storage implemented
- **Fix**: Calculate calories from power/duration and store to HealthKit

#### 3. Speed Data (Optional) ⚠️
- **Issue**: Could derive speed from distance/time but not implemented
- **Fix**: Add `.speed` permission and calculation method

### Required Code Changes
```swift
// Add to typesToWrite permissions:
HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
HKObjectType.quantityType(forIdentifier: .speed)!,

// Add new storage methods:
private func addDistanceSample(_ distance: Double)
private func addEnergyBurnedSample(_ calories: Double)  
private func addSpeedSample(_ speed: Double)
```

### HealthKit Data Completeness Summary
| Metric | Collected | Stored to HealthKit | Status |
|--------|-----------|-------------------|--------|
| Heart Rate | ✅ | ✅ (automatic) | Complete |
| Power | ✅ | ✅ | Complete |
| Cadence | ✅ | ✅ | Complete |
| Duration | ✅ | ✅ (workout session) | Complete |
| Distance | ✅ | ❌ | **Missing** |
| Calories | ❌ | ❌ | **Missing** |
| Speed | ❌ | ❌ | Optional |

## Long-term Improvements 🚀

1. **Add Apple Watch Complications** for quick workout access
2. **Implement workout templates** for different cycling types
3. **Add data export** to popular cycling platforms
4. **Implement offline data sync** for connectivity issues
5. **Add advanced analytics** and trend tracking
6. **Support for additional sensor types** (e.g., temperature, gear)

---

## Review Summary

**Overall Assessment**: The codebase demonstrates good understanding of watchOS development patterns and modern SwiftUI architecture. The core functionality is well-implemented, but there are several critical issues around memory management, error handling, and code organization that should be addressed before production use.

**Estimated Effort**: 
- Critical fixes: 2-3 days
- Architecture improvements: 1-2 weeks  
- Testing implementation: 1 week
- Performance optimization: 3-5 days

**Recommendation**: Focus on critical bug fixes first, then gradually refactor toward a more modular architecture while maintaining existing functionality.
