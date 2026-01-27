import SwiftUI

struct StartView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaAuthManager: StravaAuthManager
    @ObservedObject var stravaUploader: StravaUploader
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                // Device-specific start buttons
                if workoutManager.connectedDevices.isEmpty {
                    Image(systemName: "bicycle")
                        .foregroundColor(.orange)
                    Image(systemName: "figure.run")
                        .foregroundColor(.orange)
                    Image(systemName: "figure.walk")
                        .foregroundColor(.orange)
                    Image(systemName: "oar.2.crossed")
                        .foregroundColor(.orange)
                } else {
                    switch workoutManager.detectedDeviceType {
                    case .treadmill:
                        Image(systemName: "bicycle")
                            .foregroundColor(.gray)
                        Image(systemName: "figure.run")
                            .foregroundColor(.green)
                        Image(systemName: "figure.walk")
                            .foregroundColor(.green)
                        Image(systemName: "oar.2.crossed")
                            .foregroundColor(.gray)
                    case .rower:
                        Image(systemName: "bicycle")
                            .foregroundColor(.gray)
                        Image(systemName: "figure.run")
                            .foregroundColor(.gray)
                        Image(systemName: "figure.walk")
                            .foregroundColor(.gray)
                        Image(systemName: "oar.2.crossed")
                            .foregroundColor(.green)
                    case .bike, .unknown:
                        Image(systemName: "bicycle")
                            .foregroundColor(.green)
                        Image(systemName: "figure.run")
                            .foregroundColor(.gray)
                        Image(systemName: "figure.walk")
                            .foregroundColor(.gray)
                        Image(systemName: "oar.2.crossed")
                            .foregroundColor(.gray)
                    }
                }
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
                        .foregroundColor(.green)
                        
                        Button("Start Walk") {
                            workoutManager.startWorkout(type: .indoorWalk)
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    }
                case .rower:
                    Button("Start Row") {
                        workoutManager.startWorkout(type: .indoorRow)
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
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
                SettingsView(
                    workoutManager: workoutManager,
                    stravaAuthManager: stravaAuthManager,
                    stravaUploader: stravaUploader
                )
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
    let authManager = StravaAuthManager()
    return StartView(
        workoutManager: wm,
        stravaAuthManager: authManager,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}

#Preview("Bike Connected") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["ICSE"]
    wm.detectedDeviceType = .bike
    let authManager = StravaAuthManager()
    return StartView(
        workoutManager: wm,
        stravaAuthManager: authManager,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}

#Preview("Treadmill Connected") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["Treadmill"]
    wm.detectedDeviceType = .treadmill
    let authManager = StravaAuthManager()
    return StartView(
        workoutManager: wm,
        stravaAuthManager: authManager,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}

#Preview("Rower Connected") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["Rower"]
    wm.detectedDeviceType = .rower
    let authManager = StravaAuthManager()
    return StartView(
        workoutManager: wm,
        stravaAuthManager: authManager,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}
#endif


