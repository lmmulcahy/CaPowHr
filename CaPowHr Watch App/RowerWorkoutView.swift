//
//  RowerWorkoutView.swift
//  CaPowHr Watch App
//
//  Displays rower-specific workout metrics: Stroke Rate, Pace, Distance, Power, HR.
//

import SwiftUI

struct RowerWorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 4) {
            // Duration at top
            Text(formatDuration(workoutManager.workoutDuration))
                .font(.title3)
                .fontWeight(.semibold)
            
            // Main metrics in 2x2 compact grid
            HStack(spacing: 6) {
                CompactMetric(value: paceValue, unit: "/500m", color: .cyan)
                CompactMetric(value: strokeRateValue, unit: "SPM", color: .orange)
            }
            
            HStack(spacing: 6) {
                CompactMetric(value: powerValue, unit: "W", color: .yellow)
                CompactMetric(value: distanceValue, unit: "m", color: .green)
            }
            
            // Heart rate inline
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
                Text(heartRateValue)
                    .font(.footnote)
                    .fontWeight(.semibold)
                Text("BPM")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            
            // Stop button
            Button(action: { workoutManager.stopWorkout() }) {
                Text("Stop")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: 120)
                    .padding(.vertical, 8)
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
    
    private var paceValue: String {
        let seconds = workoutManager.rowerPaceSeconds500m
        guard seconds > 0 else { return "-:--" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private var strokeRateValue: String {
        let rate = workoutManager.rowerStrokeRatePerMinute
        return rate > 0 ? String(format: "%.0f", rate) : "-"
    }
    
    private var powerValue: String {
        let watts = workoutManager.cyclingPower
        return watts > 0 ? "\(Int(watts))" : "-"
    }
    
    private var distanceValue: String {
        let meters = workoutManager.distanceMeters
        return meters > 0 ? String(format: "%.0f", meters) : "-"
    }

    private var heartRateValue: String {
        workoutManager.heartRate > 0 ? "\(Int(workoutManager.heartRate))" : "-"
    }
}

/// Compact metric display for rower view
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
    wm.connectedDevices = ["PM5"]
    return RowerWorkoutView(workoutManager: wm)
}
#endif
