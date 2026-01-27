//
//  ContentView.swift
//  CaPowHr Watch App
//
//  Created by Luke Mulcahy on 9/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var stravaAuthManager: StravaAuthManager
    @StateObject private var stravaUploader: StravaUploader
    
    init() {
        let authManager = StravaAuthManager()
        _stravaAuthManager = StateObject(wrappedValue: authManager)
        _stravaUploader = StateObject(wrappedValue: StravaUploader(authManager: authManager))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Body Content
            if workoutManager.isAwaitingSave {
                SaveDiscardView(
                    workoutManager: workoutManager,
                    stravaUploader: stravaUploader
                )
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
                StartView(
                    workoutManager: workoutManager,
                    stravaAuthManager: stravaAuthManager,
                    stravaUploader: stravaUploader
                )
            }
            
            Spacer()
        }
        .onAppear { workoutManager.requestHealthKitAuthorization() }
    }
}

#Preview {
    ContentView()
}

