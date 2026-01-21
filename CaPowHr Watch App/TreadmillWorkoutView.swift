//
//  TreadmillWorkoutView.swift
//  CaPowHr Watch App
//
//  Displays treadmill-specific workout metrics: Speed, Incline, Distance, HR.
//

import SwiftUI

struct TreadmillWorkoutView: View {
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
                    value: heartRateValue,
                    unit: "BPM",
                    icon: "heart.fill",
                    color: .red
                )
                DataCard(
                    title: "Speed",
                    value: speedValue,
                    unit: "mph",
                    icon: "figure.run",
                    color: .orange
                )
                DataCard(
                    title: "Incline",
                    value: inclineValue,
                    unit: "%",
                    icon: "arrow.up.right",
                    color: .blue
                )
                DataCard(
                    title: "Distance",
                    value: distanceValue,
                    unit: "mi",
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

    private var heartRateValue: String {
        workoutManager.heartRate > 0 ? "\(Int(workoutManager.heartRate))" : "-"
    }
    
    private var speedValue: String {
        let mph = workoutManager.treadmillSpeedMps * 2.23694
        return String(format: "%.1f", mph)
    }
    
    private var inclineValue: String {
        String(format: "%.1f", workoutManager.treadmillInclinePercent)
    }
    
    private var distanceValue: String {
        let miles = workoutManager.distanceMeters / 1609.34
        return String(format: "%.2f", miles)
    }
}

#if DEBUG
#Preview("Treadmill Workout View") {
    let wm = WorkoutManager()
    wm.isWorkoutActive = true
    wm.heartRate = 145
    wm.treadmillSpeedMps = 2.68  // ~6 mph
    wm.treadmillInclinePercent = 2.5
    wm.distanceMeters = 1609.34  // 1 mile
    wm.connectedDevices = ["Treadmill"]
    return TreadmillWorkoutView(workoutManager: wm)
}
#endif
