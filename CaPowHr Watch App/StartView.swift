import SwiftUI

struct StartView: View {
    @State private var showingScanSheet = false
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaAuthManager: StravaAuthManager
    @ObservedObject var stravaUploader: StravaUploader
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if workoutManager.connectedDevices.isEmpty {
                    Image(systemName: "bicycle").foregroundColor(.orange)
                    Image(systemName: "figure.run").foregroundColor(.orange)
                    Image(systemName: "figure.walk").foregroundColor(.orange)
                    Image(systemName: "oar.2.crossed").foregroundColor(.orange)
                } else {
                    switch workoutManager.detectedDeviceType {
                    case .treadmill:
                        Image(systemName: "bicycle").foregroundColor(.gray)
                        Image(systemName: "figure.run").foregroundColor(.green)
                        Image(systemName: "figure.walk").foregroundColor(.green)
                        Image(systemName: "oar.2.crossed").foregroundColor(.gray)
                    case .rower:
                        Image(systemName: "bicycle").foregroundColor(.gray)
                        Image(systemName: "figure.run").foregroundColor(.gray)
                        Image(systemName: "figure.walk").foregroundColor(.gray)
                        Image(systemName: "oar.2.crossed").foregroundColor(.green)
                    case .bike, .unknown:
                        Image(systemName: "bicycle").foregroundColor(.green)
                        Image(systemName: "figure.run").foregroundColor(.gray)
                        Image(systemName: "figure.walk").foregroundColor(.gray)
                        Image(systemName: "oar.2.crossed").foregroundColor(.gray)
                    }
                }
            }
            .padding(.top, 4)
            
            Button(workoutManager.connectedDevices.isEmpty ? "Connect Sensors" : "Disconnect \(workoutManager.connectedDevices.joined(separator: ", "))") {
                if workoutManager.connectedDevices.isEmpty {
                    showingScanSheet = true
                } else {
                    workoutManager.disconnectSensors()
                }
            }
            .font(.subheadline)
            .foregroundColor(workoutManager.connectedDevices.isEmpty ? .blue : .red)
            .sheet(isPresented: $showingScanSheet) {
                DeviceConnectionView(workoutManager: workoutManager, isPresented: $showingScanSheet)
            }

            startButtons
            
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
        }
        .alert(workoutManager.alertTitle ?? "Notice", isPresented: $workoutManager.showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workoutManager.lastErrorMessage ?? "Unknown error")
        }
        .onChange(of: workoutManager.showingErrorAlert) { isShowing in
            if !isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    workoutManager.beginDisplayOnlyWorkoutIfPending()
                }
            }
        }
        .onAppear {
            workoutManager.attemptReconnectToTrustedDevices()
        }
    }

    @ViewBuilder
    private var startButtons: some View {
        if workoutManager.connectedDevices.isEmpty {
            VStack(spacing: 6) {
                Button(AppSettings.lastWorkoutType.startButtonTitle) {
                    workoutManager.startWorkout(type: AppSettings.lastWorkoutType, connectIfNeeded: true)
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)

                HStack(spacing: 6) {
                    compactStartButton("Ride", type: .indoorCycle)
                    compactStartButton("Run", type: .indoorRun)
                }
                HStack(spacing: 6) {
                    compactStartButton("Walk", type: .indoorWalk)
                    compactStartButton("Row", type: .indoorRow)
                }
            }
        } else {
            switch workoutManager.detectedDeviceType {
            case .treadmill:
                HStack(spacing: 8) {
                    startButton("Start Run", type: .indoorRun)
                    startButton("Start Walk", type: .indoorWalk)
                }
            case .rower:
                startButton("Start Row", type: .indoorRow)
            case .bike, .unknown:
                startButton("Start Ride", type: .indoorCycle)
            }
        }
    }

    private func startButton(_ title: String, type: WorkoutType) -> some View {
        Button(title) {
            workoutManager.startWorkout(type: type)
        }
        .font(.headline)
        .fontWeight(.bold)
        .foregroundColor(.green)
    }

    private func compactStartButton(_ title: String, type: WorkoutType) -> some View {
        Button(title) {
            workoutManager.startWorkout(type: type, connectIfNeeded: true)
        }
        .font(.caption)
        .foregroundColor(.green)
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
#endif
