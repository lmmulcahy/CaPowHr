import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @StateObject private var stravaAuthManager: StravaAuthManager
    @StateObject private var stravaUploader: StravaUploader
    
    init() {
        let authManager = StravaAuthManager()
        _stravaAuthManager = StateObject(wrappedValue: authManager)
        _stravaUploader = StateObject(wrappedValue: StravaUploader(authManager: authManager))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if workoutManager.isShowingWorkoutSummary, let summary = workoutManager.workoutSummary {
                WorkoutSummaryView(
                    summary: summary,
                    stravaUploader: stravaUploader,
                    onSave: {
                        workoutManager.proceedFromSummaryToSaveDiscard()
                        guard let summary = workoutManager.workoutSummary else { return }
                        workoutManager.confirmSaveWorkout()
                        Task {
                            await stravaUploader.uploadWorkout(summary.uploadData)
                        }
                    },
                    onDiscard: {
                        stravaUploader.resetStatus()
                        workoutManager.discardCurrentWorkout()
                    }
                )
            } else if workoutManager.isAwaitingSave {
                SaveDiscardView(
                    workoutManager: workoutManager,
                    stravaUploader: stravaUploader
                )
            } else if workoutManager.isWorkoutActive {
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
        .onAppear {
            workoutManager.requestHealthKitAuthorization()
            WatchConnectivityManager.shared.delegate = stravaAuthManager
        }
        .onChange(of: workoutManager.isAwaitingSave) { _, awaiting in
            guard awaiting,
                  AppSettings.workoutSaveMode == .autoSave,
                  let summary = workoutManager.workoutSummary else { return }
            Task {
                await stravaUploader.uploadWorkout(summary.uploadData)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager())
}
