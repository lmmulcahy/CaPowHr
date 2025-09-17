//
//  ContentView.swift
//  CaPowHr Watch App
//
//  Created by Luke Mulcahy on 9/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "bicycle")
                    .foregroundColor(.green)
                Text("CaPowHr")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.top, 4)
            
            // Workout Data Display
            if workoutManager.isWorkoutActive {
                VStack(spacing: 6) {
                    // Duration
                    Text(formatDuration(workoutManager.workoutDuration))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Connection status
                    if workoutManager.connectedDevices.isEmpty {
                        Text("Connecting sensors…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(workoutManager.connectedDevices.count) sensor(s) connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    // Data Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        // Heart Rate
                        DataCard(
                            title: "Heart Rate",
                            value: "\(Int(workoutManager.heartRate))",
                            unit: "BPM",
                            icon: "heart.fill",
                            color: .red
                        )
                        
                        // Power
                        DataCard(
                            title: "Power",
                            value: "\(Int(workoutManager.cyclingPower))",
                            unit: "W",
                            icon: "bolt.fill",
                            color: .orange
                        )
                        
                        // Cadence
                        DataCard(
                            title: "Cadence",
                            value: "\(Int(workoutManager.cyclingCadence))",
                            unit: "RPM",
                            icon: "speedometer",
                            color: .blue
                        )
                        
                        // Connected Devices
                        DataCard(
                            title: "Devices",
                            value: "\(workoutManager.connectedDevices.count)",
                            unit: "Connected",
                            icon: "antenna.radiowaves.left.and.right",
                            color: .green
                        )
                    }
                }
            } else {
                // Pre-workout state
                VStack(spacing: 8) {
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

                    Button("Connect Sensors") {
                        workoutManager.startScanningForTesting()
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding(.vertical, 0)
            }
            
            Spacer()
            
            // Start/Stop Button
            Button(action: {
                if workoutManager.isWorkoutActive {
                    workoutManager.stopWorkout()
                } else {
                    workoutManager.startWorkout()
                }
            }) {
                Text(workoutManager.isWorkoutActive ? "Stop" : "Start")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(workoutManager.isWorkoutActive ? Color.red : Color.green)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .onAppear {
            workoutManager.requestHealthKitAuthorization()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
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
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(6)
    }
}

#Preview {
    ContentView()
}
