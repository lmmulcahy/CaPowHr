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
                // Key the layout off the workout the user chose, not the connected
                // hardware: a Run started before the treadmill connects should show
                // the treadmill layout, not the bike one.
                switch workoutManager.currentWorkoutType {
                case .indoorRun, .indoorWalk:
                    TreadmillWorkoutView(workoutManager: workoutManager)
                case .indoorRow:
                    RowerWorkoutView(workoutManager: workoutManager)
                case .indoorCycle:
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
