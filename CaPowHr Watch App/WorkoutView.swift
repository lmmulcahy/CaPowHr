import SwiftUI

struct WorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 2) {
            Text(formatDuration(workoutManager.workoutDuration))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                DataCard(
                    title: "HR",
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
                    title: "Distance",
                    value: "\(distanceValue)",
                    unit: "\(distanceUnit)",
                    icon: "map",
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
                    .frame(maxWidth: 150)
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
    
    private var distanceValue: String {
        let miles = workoutManager.distanceMeters / 1609.34
        return String(format: "%.1f", miles)
    }
    
    private var distanceUnit: String { "mi" }

    private var speedValue: String {
        let mph = workoutManager.cyclingSpeedMps * 2.23694
        return String(format: "%.1f", mph)
    }
    private var speedUnit: String { "mph" }
}

struct DataCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundColor(color)
                Text(title)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .baselineOffset(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(6)
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


