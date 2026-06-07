import SwiftUI

struct TreadmillWorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @AppStorage(AppSettings.distanceUnitKey) private var distanceUnitRaw = DistanceUnit.miles.rawValue
    
    private var metrics: [TreadmillMetric] { WorkoutMetricsLayout.treadmillMetrics() }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(formatDuration(workoutManager.workoutDuration))
                .font(.title2)
                .fontWeight(.semibold)
            
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
    private func metricCard(_ metric: TreadmillMetric) -> some View {
        switch metric {
        case .heartRate:
            DataCard(title: metric.title, value: heartRateValue, unit: "BPM", icon: metric.icon, color: .red)
        case .speed:
            let formatted = DistanceFormatter.formatSpeedMps(workoutManager.treadmillSpeedMps, unit: DistanceUnit(rawValue: distanceUnitRaw) ?? .miles)
            DataCard(title: metric.title, value: formatted.value, unit: formatted.unit, icon: metric.icon, color: .orange)
        case .incline:
            DataCard(title: metric.title, value: String(format: "%.1f", workoutManager.treadmillInclinePercent), unit: "%", icon: metric.icon, color: .blue)
        case .distance:
            let formatted = DistanceFormatter.formatDistance(workoutManager.distanceMeters, unit: DistanceUnit(rawValue: distanceUnitRaw) ?? .miles, decimals: 2)
            DataCard(title: metric.title, value: formatted.value, unit: formatted.unit, icon: metric.icon, color: .green)
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

#if DEBUG
#Preview("Treadmill Workout View") {
    let wm = WorkoutManager()
    wm.isWorkoutActive = true
    wm.heartRate = 145
    wm.treadmillSpeedMps = 2.68
    wm.treadmillInclinePercent = 2.5
    wm.distanceMeters = 1609.34
    return TreadmillWorkoutView(workoutManager: wm)
}
#endif
