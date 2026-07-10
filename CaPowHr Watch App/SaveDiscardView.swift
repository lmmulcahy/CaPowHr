import SwiftUI

struct SaveDiscardView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaUploader: StravaUploader
    
    var body: some View {
        ZStack {
            if workoutManager.isEndingCollection || workoutManager.isSavingWorkout || stravaUploader.isUploading {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if !workoutManager.isSavingWorkout {
                VStack(spacing: 8) {
                    Button("Discard Workout") {
                        stravaUploader.resetStatus()
                        workoutManager.discardCurrentWorkout()
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .disabled(workoutManager.isEndingCollection || stravaUploader.isUploading)
                    
                    if stravaUploader.lastUploadSuccess {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Uploaded to Strava")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = stravaUploader.lastUploadError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer(minLength: 12)
                    
                    Button("Save Workout") {
                        saveWorkoutAndUploadToStrava()
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .disabled(workoutManager.isEndingCollection || stravaUploader.isUploading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.vertical, 6)
            }
        }
    }

    private var statusText: String {
        if stravaUploader.isUploading { return "Uploading to Strava..." }
        if workoutManager.isSavingWorkout { return "Saving workout..." }
        return "Processing workout..."
    }
    
    private func saveWorkoutAndUploadToStrava() {
        // Fallback when no summary exists: omit the averages rather than passing
        // off the last instantaneous readings as workout averages.
        let uploadData = workoutManager.workoutSummary?.uploadData ?? WorkoutUploadData(
            workoutType: workoutManager.currentWorkoutType,
            startDate: Date().addingTimeInterval(-workoutManager.workoutDuration),
            durationSeconds: workoutManager.workoutDuration,
            distanceMeters: workoutManager.distanceMeters,
            averageHeartRate: nil,
            averagePower: nil,
            averageCadence: nil
        )
        
        workoutManager.confirmSaveWorkout()
        
        Task {
            await stravaUploader.uploadWorkout(uploadData)
        }
    }
}

#if DEBUG
#Preview {
    let wm = WorkoutManager()
    wm.isAwaitingSave = true
    wm.workoutDuration = 1800
    wm.distanceMeters = 10000
    let authManager = StravaAuthManager()
    return SaveDiscardView(
        workoutManager: wm,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}
#endif
