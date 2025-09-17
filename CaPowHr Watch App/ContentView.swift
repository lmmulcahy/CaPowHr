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
            
            // Body Content
            if workoutManager.isWorkoutActive {
                WorkoutView(workoutManager: workoutManager)
            } else {
                StartView(workoutManager: workoutManager)
            }
            
            Spacer()
        }
        .onAppear { workoutManager.requestHealthKitAuthorization() }
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
