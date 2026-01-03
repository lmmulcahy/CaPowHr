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
                Text("No sensors connected")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            } else {
                Text("Connected: \(workoutManager.connectedDevices.joined(separator: ", "))")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.green)
                    .padding(.horizontal, 4)
            }
            
            if workoutManager.connectedDevices.isEmpty {
                Button("Connect Sensors") {
                    workoutManager.startScanningForTesting()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            } else {
                Button("Disconnect Sensors") {
                    workoutManager.disconnectSensors()
                }
                .font(.subheadline)
                .foregroundColor(.red)
            }

            Spacer(minLength: 6)

            Button(action: {
                workoutManager.startWorkout()
            }) {
                Text("Start")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: 150)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            NavigationLink {
                SettingsView()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.footnote)
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

#Preview("With Devices") {
    let wm = WorkoutManager()
    wm.connectedDevices = ["ICSE"]
    return StartView(workoutManager: wm)
}
#endif


