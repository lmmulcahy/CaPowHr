import SwiftUI

struct WorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 6) {
            Text(formatDuration(workoutManager.workoutDuration))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if workoutManager.connectedDevices.isEmpty {
                Text("Connecting sensors…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(workoutManager.connectedDevices.count) sensor(s) connected")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                DataCard(
                    title: "Heart Rate",
                    value: "\(Int(workoutManager.heartRate))",
                    unit: "BPM",
                    icon: "heart.fill",
                    color: .red
                )
                DataCard(
                    title: "Power",
                    value: "\(Int(workoutManager.cyclingPower))",
                    unit: "W",
                    icon: "bolt.fill",
                    color: .orange
                )
                DataCard(
                    title: "Cadence",
                    value: "\(Int(workoutManager.cyclingCadence))",
                    unit: "RPM",
                    icon: "speedometer",
                    color: .blue
                )
                DataCard(
                    title: "Devices",
                    value: "\(workoutManager.connectedDevices.count)",
                    unit: "Connected",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .green
                )
            }
            
            Spacer(minLength: 6)
            
            Button(action: {
                workoutManager.stopWorkout()
            }) {
                Text("Stop")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#if DEBUG
#Preview("Workout View") {
    let wm = WorkoutManager()
    wm.isWorkoutActive = true
    wm.heartRate = 128
    wm.cyclingPower = 245
    wm.cyclingCadence = 87
    wm.connectedDevices = ["ICSE"]
    return WorkoutView(workoutManager: wm)
}
#endif


