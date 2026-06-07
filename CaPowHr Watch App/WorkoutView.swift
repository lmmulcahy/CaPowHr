import SwiftUI

struct WorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @AppStorage(AppSettings.distanceUnitKey) private var distanceUnitRaw = DistanceUnit.miles.rawValue
    
    private var metrics: [BikeMetric] { WorkoutMetricsLayout.bikeMetrics() }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(formatDuration(workoutManager.workoutDuration))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(workoutManager.isWorkoutPaused ? .yellow : .primary)

            if let hrZone = HeartRateZone.zone(forHeartRate: workoutManager.heartRate) {
                Text(hrZone.label)
                    .font(.caption2)
                    .foregroundColor(hrZone.color)
            } else if let powerZone = PowerZone.zone(forPower: workoutManager.cyclingPower) {
                Text(powerZone.label)
                    .font(.caption2)
                    .foregroundColor(powerZone.color)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(metrics) { metric in
                    metricCard(metric)
                }
            }
            
            Spacer(minLength: 6)
            
            WorkoutControlsView(workoutManager: workoutManager) {
                workoutManager.stopWorkout()
            }
        }
    }
    
    @ViewBuilder
    private func metricCard(_ metric: BikeMetric) -> some View {
        switch metric {
        case .heartRate:
            DataCard(title: metric.title, value: heartRateValue, unit: "BPM", icon: metric.icon, color: .red)
        case .power:
            DataCard(title: metric.title, value: "\(Int(workoutManager.cyclingPower))", unit: "W", icon: metric.icon, color: .orange)
        case .cadence:
            DataCard(title: metric.title, value: "\(Int(workoutManager.cyclingCadence))", unit: "RPM", icon: metric.icon, color: .blue)
        case .distance:
            let formatted = DistanceFormatter.formatDistance(workoutManager.distanceMeters, unit: DistanceUnit(rawValue: distanceUnitRaw) ?? .miles)
            DataCard(title: metric.title, value: formatted.value, unit: formatted.unit, icon: metric.icon, color: .green)
        case .speed:
            let formatted = DistanceFormatter.formatSpeedMps(workoutManager.cyclingSpeedMps, unit: DistanceUnit(rawValue: distanceUnitRaw) ?? .miles)
            DataCard(title: metric.title, value: formatted.value, unit: formatted.unit, icon: metric.icon, color: .cyan)
        case .calories:
            DataCard(title: metric.title, value: "\(Int(workoutManager.activeEnergyKcal))", unit: "kcal", icon: metric.icon, color: .pink)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var heartRateValue: String {
        workoutManager.heartRate > 0 ? "\(Int(workoutManager.heartRate))" : "-"
    }
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
