import SwiftUI

/// Post-workout progress screen shown while collection ends, the workout is
/// saved to Health, and any Strava upload runs. The save/discard decision
/// happens on the workout summary screen; this view only reports progress.
struct SaveDiscardView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaUploader: StravaUploader

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if stravaUploader.isUploading { return "Uploading to Strava..." }
        if workoutManager.isSavingWorkout { return "Saving workout..." }
        return "Processing workout..."
    }
}

#if DEBUG
#Preview {
    let wm = WorkoutManager()
    wm.isAwaitingSave = true
    wm.isSavingWorkout = true
    let authManager = StravaAuthManager()
    return SaveDiscardView(
        workoutManager: wm,
        stravaUploader: StravaUploader(authManager: authManager)
    )
}
#endif
