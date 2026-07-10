import SwiftUI

struct RowerWorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @AppStorage(AppSettings.distanceUnitKey) private var distanceUnitRaw = DistanceUnit.miles.rawValue
    
    private var metrics: [RowerMetric] { WorkoutMetricsLayout.rowerMetrics() }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(DurationFormatter.hoursMinutesSeconds(workoutManager.workoutDuration))
                .font(.title3)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 6) {
                ForEach(metrics) { metric in
                    rowerMetricCard(metric)
                }
            }
            
            WorkoutControlsView(workoutManager: workoutManager) {
                workoutManager.stopWorkout()
            }
        }
    }
    
    @ViewBuilder
    private func rowerMetricCard(_ metric: RowerMetric) -> some View {
        switch metric {
        case .pace:
            CompactMetric(value: paceValue, unit: "/500m", color: .cyan)
        case .strokeRate:
            CompactMetric(value: strokeRateValue, unit: "SPM", color: .orange)
        case .power:
            CompactMetric(value: powerValue, unit: "W", color: .yellow)
        case .distance:
            let formatted = DistanceFormatter.formatDistance(workoutManager.distanceMeters, unit: DistanceUnit(rawValue: distanceUnitRaw) ?? .miles, decimals: 1)
            CompactMetric(value: formatted.value, unit: formatted.unit, color: .green)
        case .heartRate:
            CompactMetric(value: heartRateValue, unit: "BPM", color: .red)
        }
    }
    
    private var paceValue: String {
        let seconds = workoutManager.rowerPaceSeconds500m
        guard seconds > 0 else { return "-:--" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    
    private var strokeRateValue: String {
        workoutManager.rowerStrokeRatePerMinute > 0 ? String(format: "%.0f", workoutManager.rowerStrokeRatePerMinute) : "-"
    }
    
    private var powerValue: String {
        workoutManager.cyclingPower > 0 ? "\(Int(workoutManager.cyclingPower))" : "-"
    }

    private var heartRateValue: String {
        workoutManager.heartRate > 0 ? "\(Int(workoutManager.heartRate))" : "-"
    }
}

private struct CompactMetric: View {
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .cornerRadius(6)
    }
}

#if DEBUG
#Preview("Rower Workout View") {
    let wm = WorkoutManager()
    wm.isWorkoutActive = true
    wm.heartRate = 152
    wm.rowerStrokeRatePerMinute = 28
    wm.rowerPaceSeconds500m = 125
    wm.distanceMeters = 2500
    wm.cyclingPower = 185
    return RowerWorkoutView(workoutManager: wm)
}
#endif
