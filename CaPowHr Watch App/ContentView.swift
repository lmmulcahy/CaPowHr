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
            // Body Content
            if workoutManager.isAwaitingSave {
                SaveDiscardView(workoutManager: workoutManager)
            } else if workoutManager.isWorkoutActive {
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

#Preview {
    ContentView()
}
