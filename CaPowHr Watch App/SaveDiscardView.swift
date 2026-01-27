import SwiftUI

struct SaveDiscardView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaUploader: StravaUploader
    
    var body: some View {
        ZStack {
            // Processing indicator - overlaid when processing
            if workoutManager.isEndingCollection || stravaUploader.isUploading {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text(stravaUploader.isUploading ? "Uploading to Strava..." : "Processing workout...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Buttons - always in the hierarchy, but disabled when processing
            VStack(spacing: 8) {
                // Top discard button
                Button("Discard Workout") {
                    stravaUploader.resetStatus()
                    workoutManager.discardCurrentWorkout()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.red)
                .disabled(workoutManager.isEndingCollection || stravaUploader.isUploading)
                
                // Strava status indicator
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
                
                // Bottom save button
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
            .opacity(workoutManager.isEndingCollection || stravaUploader.isUploading ? 0 : 1)
        }
    }
    
    private func saveWorkoutAndUploadToStrava() {
        // Capture workout data before saving (save clears the data)
        let uploadData = WorkoutUploadData(
            workoutType: workoutManager.currentWorkoutType,
            startDate: Date().addingTimeInterval(-workoutManager.workoutDuration),
            durationSeconds: workoutManager.workoutDuration,
            distanceMeters: workoutManager.distanceMeters,
            averageHeartRate: workoutManager.heartRate > 0 ? workoutManager.heartRate : nil,
            averagePower: workoutManager.cyclingPower > 0 ? workoutManager.cyclingPower : nil,
            averageCadence: workoutManager.cyclingCadence > 0 ? workoutManager.cyclingCadence : nil
        )
        
        // Save to HealthKit first
        workoutManager.confirmSaveWorkout()
        
        // Then upload to Strava
        Task {
            await stravaUploader.uploadWorkout(uploadData)
        }
    }
}

#if DEBUG
#Preview {
    let wm = WorkoutManager()
    wm.isAwaitingSave = true
    wm.workoutDuration = 1800  // 30 minutes
    wm.distanceMeters = 10000  // 10 km
    let authManager = StravaAuthManager()
    return SaveDiscardView(
        workoutManager: wm,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}
#endif



