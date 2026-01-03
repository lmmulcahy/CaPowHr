import SwiftUI

struct SaveDiscardView: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 8) {
            if workoutManager.isEndingCollection {
                // Processing indicator - show only when processing
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text("Processing workout...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            } else {
                // Buttons - show only when not processing
                // Top discard button
                Button("Discard Workout") {
                    workoutManager.discardCurrentWorkout()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.red)
                
                Spacer(minLength: 12)
                
                // Bottom save button
                Button("Save Workout") {
                    workoutManager.confirmSaveWorkout()
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 6)
    }
}

#if DEBUG
#Preview {
    let wm = WorkoutManager()
    wm.isAwaitingSave = true
    return SaveDiscardView(workoutManager: wm)
}
#endif


