import SwiftUI

struct StartView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "bicycle")
                    .foregroundColor(.green)
            }
            .padding(.top, 4)
            
            if workoutManager.connectedDevices.isEmpty {
                Button("Connect Sensors") {
                    workoutManager.startScanningForTesting()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            } else {
                Button("Disconnect \(workoutManager.connectedDevices.joined(separator: ", "))") {
                    workoutManager.disconnectSensors()
                }
                .font(.subheadline)
                .foregroundColor(.red)
            }

            // Device-specific start buttons
            if workoutManager.connectedDevices.isEmpty {
                Button("Start") {}
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                    .disabled(true)
            } else {
                switch workoutManager.detectedDeviceType {
                case .treadmill:
                    HStack(spacing: 8) {
                        Button("Start Run") {
                            workoutManager.startWorkout(type: .indoorRun)
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        
                        Button("Start Walk") {
                            workoutManager.startWorkout(type: .indoorWalk)
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    }
                case .bike, .unknown:
                    Button("Start Ride") {
                        workoutManager.startWorkout(type: .indoorCycle)
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                }
            }
            
            NavigationLink {
                SettingsView(workoutManager: workoutManager)
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        .contentShape(Rectangle())
        .alert(workoutManager.alertTitle ?? "Notice", isPresented: $workoutManager.showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workoutManager.lastErrorMessage ?? "Unknown error")
        }
        .onChange(of: workoutManager.showingErrorAlert) { isShowing in
            if !isShowing {
                // Alert was dismissed; begin display-only start on next tick to avoid publish-in-update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    workoutManager.beginDisplayOnlyWorkoutIfPending()
                }
            }
        }
        }
    }
}

#if DEBUG
#Preview("No Devices") {
    let wm = WorkoutManager()
    return StartView(workoutManager: wm)
}

#Preview("Bike Connected") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["ICSE"]
    wm.detectedDeviceType = .bike
    return StartView(workoutManager: wm)
}

#Preview("Treadmill Connected") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["Treadmill"]
    wm.detectedDeviceType = .treadmill
    return StartView(workoutManager: wm)
}
#endif


