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
                // Switch UI based on detected device type
                switch workoutManager.detectedDeviceType {
                case .treadmill:
                    TreadmillWorkoutView(workoutManager: workoutManager)
                case .rower:
                    RowerWorkoutView(workoutManager: workoutManager)
                case .bike, .unknown:
                    WorkoutView(workoutManager: workoutManager)
                }
            } else {
                StartView(workoutManager: workoutManager)
            }
            
            Spacer()
        }
        .onAppear { workoutManager.requestHealthKitAuthorization() }
    }
}

#Preview {
    ContentView()
}
